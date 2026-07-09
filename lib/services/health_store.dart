// lib/services/health_store.dart
// Persistance des instantanés santé quotidiens + calculs dérivés
// (baselines, séries temporelles, streaks). Calqué sur GameStore : boîte Hive
// simple, aucune génération d'adaptateur.
import 'package:hive_flutter/hive_flutter.dart';
import '../models/daily_health_record.dart';

/// Préférence d'affichage de la grille de métriques du dashboard santé
/// ("Personnaliser") — quelles cartes l'utilisateur a choisi de masquer.
/// Persistée dans la boîte 'settings'. Par défaut, rien n'est masqué.
class MetricsPreferenceStore {
  static Box get _box => Hive.box('settings');
  static const _key = 'dashboard_hidden_metrics';

  static Set<String> get _hidden {
    final raw = _box.get(_key);
    return raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
  }

  static bool isHidden(HealthMetric m) => _hidden.contains(m.name);

  static Future<void> setHidden(HealthMetric m, bool hidden) async {
    final s = _hidden;
    if (hidden) {
      s.add(m.name);
    } else {
      s.remove(m.name);
    }
    await _box.put(_key, s.toList());
  }
}

/// Profil corporel de l'utilisateur (poids/taille/âge), saisi manuellement et
/// persisté dans la boîte 'settings' (partagée avec GameStore).
class HealthProfileStore {
  static Box get _box => Hive.box('settings');

  static double? get weightKg {
    final v = _box.get('profile_weight_kg');
    return v is num ? v.toDouble() : null;
  }

  static double? get heightCm {
    final v = _box.get('profile_height_cm');
    return v is num ? v.toDouble() : null;
  }

  static int? get age {
    final v = _box.get('player_age'); // même clé que GameStore
    return v is int ? v : null;
  }

  /// 'M' ou 'F' — optionnel, uniquement utilisé pour affiner des références
  /// par sexe (ex. catégorie de VO2 max). `null` tant que non renseigné,
  /// jamais déduit ni supposé.
  static String? get sex {
    final v = _box.get('profile_sex');
    return v is String ? v : null;
  }

  static Future<void> setWeight(double kg) =>
      _box.put('profile_weight_kg', kg);
  static Future<void> setHeight(double cm) =>
      _box.put('profile_height_cm', cm);
  static Future<void> setAge(int years) => _box.put('player_age', years);
  static Future<void> setSex(String sex) => _box.put('profile_sex', sex);

  /// IMC = poids / taille² (m). Null si incomplet.
  static double? get bmi {
    final w = weightKg, h = heightCm;
    if (w == null || h == null || h <= 0) return null;
    final m = h / 100.0;
    return w / (m * m);
  }

  /// Catégorie OMS de l'IMC.
  static String bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Maigreur';
    if (bmi < 25) return 'Normal';
    if (bmi < 30) return 'Surpoids';
    return 'Obésité';
  }

  static bool get isComplete => weightKg != null && heightCm != null;
}

/// Feedback utilisateur sur les insights santé (pouce haut/bas).
/// Un insight « rejeté » est masqué pour la journée en cours (il pourra
/// réapparaître un autre jour s'il est toujours pertinent). Persisté dans la
/// boîte 'settings'.
class HealthFeedbackStore {
  static Box get _box => Hive.box('settings');

  static String _dayKey() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static String get _dismissKey => 'insight_dismissed_${_dayKey()}';
  static String get _likeKey => 'insight_liked_${_dayKey()}';

  static Set<String> get _dismissed {
    final raw = _box.get(_dismissKey);
    return raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
  }

  static Set<String> get _liked {
    final raw = _box.get(_likeKey);
    return raw is List ? raw.map((e) => e.toString()).toSet() : <String>{};
  }

  static bool isDismissed(String id) => _dismissed.contains(id);
  static bool isLiked(String id) => _liked.contains(id);

  static Future<void> dismiss(String id) async {
    final s = _dismissed..add(id);
    await _box.put(_dismissKey, s.toList());
  }

  static Future<void> like(String id) async {
    final s = _liked..add(id);
    await _box.put(_likeKey, s.toList());
  }

  static Future<void> undoLike(String id) async {
    final s = _liked..remove(id);
    await _box.put(_likeKey, s.toList());
  }
}

class HealthStore {
  static const String boxName = 'health_history';

  static Box get _box => Hive.box(boxName);

  /// Enregistre / met à jour le jour donné.
  static Future<void> upsertDay(DailyHealthRecord record) async {
    await _box.put(record.key, record.toMap());
  }

  /// Enregistrement d'un jour précis (null si absent).
  static DailyHealthRecord? recordFor(DateTime day) {
    final raw = _box.get(DailyHealthRecord.keyFor(day));
    if (raw is Map) return DailyHealthRecord.fromMap(raw);
    return null;
  }

  static bool hasDay(DateTime day) =>
      _box.containsKey(DailyHealthRecord.keyFor(day));

  /// Tous les enregistrements triés du plus ancien au plus récent.
  static List<DailyHealthRecord> all() {
    final list = _box.values
        .whereType<Map>()
        .map((m) => DailyHealthRecord.fromMap(m))
        .toList();
    list.sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Les [n] derniers jours (calendaires) jusqu'à aujourd'hui inclus, dans
  /// l'ordre chronologique. Les jours sans donnée sont omis.
  static List<DailyHealthRecord> lastNDays(int n) {
    final all = HealthStore.all();
    if (all.isEmpty) return [];
    final cutoff = DateTime.now().subtract(Duration(days: n - 1));
    final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    return all.where((r) => !r.date.isBefore(cutoffDay)).toList();
  }

  static int get dayCount => _box.length;

  /// Moyenne glissante d'une métrique sur les [window] derniers jours,
  /// en excluant éventuellement aujourd'hui (pour comparer « aujourd'hui vs
  /// baseline »). Ignore les valeurs nulles/zéro non pertinentes.
  static double baseline(
    HealthMetric metric, {
    int window = 7,
    bool excludeToday = true,
  }) {
    final records = lastNDays(window + (excludeToday ? 1 : 0));
    final todayKey = DailyHealthRecord.keyFor(DateTime.now());
    final vals = <double>[];
    for (final r in records) {
      if (excludeToday && r.key == todayKey) continue;
      final v = metric.valueOf(r);
      if (v > 0) vals.add(v);
    }
    if (vals.isEmpty) return 0;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Série (date, valeur) d'une métrique sur les [n] derniers jours.
  static List<MapEntry<DateTime, double>> series(HealthMetric metric, int n) {
    return lastNDays(n)
        .map((r) => MapEntry(r.date, metric.valueOf(r)))
        .toList();
  }

  /// Nombre de jours consécutifs (en terminant aujourd'hui ou hier) où
  /// [test] est vrai. Sert aux streaks.
  static int streak(bool Function(DailyHealthRecord) test) {
    final all = HealthStore.all();
    if (all.isEmpty) return 0;
    final byKey = {for (final r in all) r.key: r};

    int count = 0;
    var cursor = DateTime.now();
    // Tolère que la journée en cours ne soit pas encore « validée » :
    // on démarre le comptage à partir du dernier jour qui satisfait le test.
    for (int i = 0; i < 400; i++) {
      final key = DailyHealthRecord.keyFor(cursor);
      final r = byKey[key];
      final ok = r != null && test(r);
      if (ok) {
        count++;
      } else if (i == 0) {
        // aujourd'hui pas encore atteint : on ne casse pas, on regarde hier
      } else {
        break;
      }
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  static Future<void> clearAll() async => _box.clear();
}
