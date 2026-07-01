// lib/services/game_service.dart
// Moteur de progression : XP, niveaux, paliers, stats, quêtes (jour & semaine).
//
// ⚙️ Toutes les constantes en haut sont volontairement faciles à ajuster.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/activity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Réglages (à équilibrer librement)
// ─────────────────────────────────────────────────────────────────────────────
class GameTuning {
  static const double xpPerKm = 20; // XP par km parcouru
  static const double xpPerMinute = 2; // XP par minute de mouvement
  static const double xpPerElevationMeter = 1; // XP par mètre de D+
  static const int xpFlatPerRun = 20; // bonus fixe par sortie enregistrée

  /// XP nécessaire pour passer du niveau [level] au niveau suivant.
  static int xpToNext(int level) => 100 * level;
}

// ─────────────────────────────────────────────────────────────────────────────
// Paliers de progression (noms sportifs neutres, couleurs néon du thème)
// ─────────────────────────────────────────────────────────────────────────────
class Tier {
  final String name;
  final Color color;
  final int minLevel;
  const Tier(this.name, this.color, this.minLevel);
}

const List<Tier> kTiers = [
  Tier('Débutant', Color(0xFF9AA0B5), 1),
  Tier('Régulier', Color(0xFF39FF14), 5),
  Tier('Confirmé', Color(0xFF00FFFF), 10),
  Tier('Athlète', Color(0xFF8A5EFF), 15),
  Tier('Élite', Color(0xFFF55CBD), 20),
  Tier('Légende', Color(0xFFFFC107), 30),
];

// ─────────────────────────────────────────────────────────────────────────────
// Stats RPG dérivées de l'effort réel
// ─────────────────────────────────────────────────────────────────────────────
class GameStats {
  final int force; // ← dénivelé cumulé
  final int endurance; // ← distance cumulée
  final int agilite; // ← meilleure allure
  final int vitalite; // ← temps de mouvement cumulé
  const GameStats({
    required this.force,
    required this.endurance,
    required this.agilite,
    required this.vitalite,
  });

  int get total => force + endurance + agilite + vitalite;
}

// ─────────────────────────────────────────────────────────────────────────────
// Profil joueur (résultat final)
// ─────────────────────────────────────────────────────────────────────────────
class PlayerProfile {
  final int level;
  final int totalXp;
  final int xpInLevel; // XP accumulée dans le niveau courant
  final int xpForLevel; // XP nécessaire pour finir le niveau courant
  final Tier tier;
  final Tier? nextTier;
  final GameStats stats;

  const PlayerProfile({
    required this.level,
    required this.totalXp,
    required this.xpInLevel,
    required this.xpForLevel,
    required this.tier,
    required this.nextTier,
    required this.stats,
  });

  double get levelProgress =>
      xpForLevel <= 0 ? 0 : (xpInLevel / xpForLevel).clamp(0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Quêtes hebdomadaires
// ─────────────────────────────────────────────────────────────────────────────
enum QuestMetric {
  weeklyDistance,
  weeklySessions,
  longestSingle,
  weeklyElevation,
  weeklyMinutes,
}

class QuestDef {
  final String id;
  final String title;
  final QuestMetric metric;
  final double target;
  final String unit;
  final int reward;
  const QuestDef({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    required this.unit,
    required this.reward,
  });
}

class QuestProgress {
  final QuestDef def;
  final double current;
  final bool claimed;
  const QuestProgress(
      {required this.def, required this.current, required this.claimed});

  bool get completed => current >= def.target;
  double get ratio => def.target <= 0 ? 0 : (current / def.target).clamp(0.0, 1.0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Service principal (logique pure)
// ─────────────────────────────────────────────────────────────────────────────
class GameService {
  // ── XP ────────────────────────────────────────────────────────────────────
  static int xpForActivity(Activity a) {
    final xp = a.distanceKmValue * GameTuning.xpPerKm +
        (a.duration / 60.0) * GameTuning.xpPerMinute +
        a.elevationGainValue * GameTuning.xpPerElevationMeter +
        GameTuning.xpFlatPerRun;
    return xp.round();
  }

  static int totalActivityXp(List<Activity> acts) =>
      acts.fold<int>(0, (s, a) => s + xpForActivity(a));

  // ── Niveau ──────────────────────────────────────────────────────────────────
  /// Calcule le niveau (1-based) à partir d'un total d'XP.
  static int levelFromXp(int totalXp) {
    int level = 1;
    int remaining = totalXp;
    while (level < 999) {
      final need = GameTuning.xpToNext(level);
      if (remaining < need) break;
      remaining -= need;
      level++;
    }
    return level;
  }

  static Tier tierForLevel(int level) {
    Tier result = kTiers.first;
    for (final t in kTiers) {
      if (level >= t.minLevel) result = t;
    }
    return result;
  }

  static Tier? nextTierAfter(Tier tier) {
    final idx = kTiers.indexWhere((t) => t.minLevel == tier.minLevel);
    if (idx >= 0 && idx < kTiers.length - 1) return kTiers[idx + 1];
    return null;
  }

  // ── Stats ────────────────────────────────────────────────────────────────────
  static GameStats statsFor(List<Activity> acts) {
    final totalDist =
        acts.fold<double>(0, (s, a) => s + a.distanceKmValue);
    final totalElev =
        acts.fold<double>(0, (s, a) => s + a.elevationGainValue);
    final totalMinutes =
        acts.fold<double>(0, (s, a) => s + a.duration / 60.0);
    final bestPaceSec = acts
        .where((a) => a.distanceKmValue >= 0.5)
        .map((a) => a.duration / a.distanceKmValue)
        .fold<double>(double.infinity, min);

    final agilite = bestPaceSec.isFinite && bestPaceSec > 0
        ? (36000 / bestPaceSec).round() // ~120 pour 5:00/km
        : 0;

    return GameStats(
      force: (totalElev / 10).round(),
      endurance: totalDist.round(),
      agilite: agilite,
      vitalite: (totalMinutes / 5).round(),
    );
  }

  // ── Profil complet ────────────────────────────────────────────────────────────
  static PlayerProfile profileFor(List<Activity> acts, {int bonusXp = 0}) {
    final totalXp = totalActivityXp(acts) + bonusXp;
    final level = levelFromXp(totalXp);

    // XP restante dans le niveau courant
    int remaining = totalXp;
    for (int l = 1; l < level; l++) {
      remaining -= GameTuning.xpToNext(l);
    }
    final tier = tierForLevel(level);

    return PlayerProfile(
      level: level,
      totalXp: totalXp,
      xpInLevel: remaining,
      xpForLevel: GameTuning.xpToNext(level),
      tier: tier,
      nextTier: nextTierAfter(tier),
      stats: statsFor(acts),
    );
  }

  // ── Quêtes hebdomadaires ──────────────────────────────────────────────────────
  static DateTime startOfWeek(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  static String weekKey(DateTime now) {
    final s = startOfWeek(now);
    return '${s.year}-${s.month.toString().padLeft(2, '0')}-${s.day.toString().padLeft(2, '0')}';
  }

  /// Génère 3 quêtes de la semaine, qui tournent d'une semaine à l'autre.
  static List<QuestDef> weeklyQuests(DateTime now) {
    final start = startOfWeek(now);
    final weekIndex = start.millisecondsSinceEpoch ~/ (7 * 24 * 3600 * 1000);

    // Slot 1 — distance hebdo
    const distTargets = [8.0, 12.0, 16.0, 20.0];
    final dist = distTargets[weekIndex % distTargets.length];

    // Slot 2 — nombre de sorties
    const sessTargets = [3.0, 4.0, 5.0];
    final sess = sessTargets[weekIndex % sessTargets.length];

    // Slot 3 — défi tournant
    final slot3 = weekIndex % 3;
    QuestDef third;
    if (slot3 == 0) {
      const t = [5.0, 8.0, 10.0];
      final v = t[weekIndex % t.length];
      third = QuestDef(
        id: 'long',
        title: 'Réalise une sortie de ${v.toStringAsFixed(0)} km',
        metric: QuestMetric.longestSingle,
        target: v,
        unit: 'km',
        reward: 220,
      );
    } else if (slot3 == 1) {
      const t = [100.0, 150.0, 250.0];
      final v = t[weekIndex % t.length];
      third = QuestDef(
        id: 'elev',
        title: 'Cumule ${v.toStringAsFixed(0)} m de D+ cette semaine',
        metric: QuestMetric.weeklyElevation,
        target: v,
        unit: 'm',
        reward: 200,
      );
    } else {
      const t = [60.0, 90.0, 120.0];
      final v = t[weekIndex % t.length];
      third = QuestDef(
        id: 'time',
        title: 'Cumule ${v.toStringAsFixed(0)} min cette semaine',
        metric: QuestMetric.weeklyMinutes,
        target: v,
        unit: 'min',
        reward: 200,
      );
    }

    return [
      QuestDef(
        id: 'dist',
        title: 'Parcours ${dist.toStringAsFixed(0)} km cette semaine',
        metric: QuestMetric.weeklyDistance,
        target: dist,
        unit: 'km',
        reward: 180,
      ),
      QuestDef(
        id: 'sessions',
        title: 'Cours ${sess.toStringAsFixed(0)} fois cette semaine',
        metric: QuestMetric.weeklySessions,
        target: sess,
        unit: 'x',
        reward: 200,
      ),
      third,
    ];
  }

  static List<Activity> activitiesThisWeek(List<Activity> acts, DateTime now) {
    final start = startOfWeek(now);
    return acts.where((a) => !a.date.isBefore(start)).toList();
  }

  // ── Quêtes quotidiennes ───────────────────────────────────────────────────────
  static String dayKey(DateTime now) {
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static List<Activity> activitiesToday(List<Activity> acts, DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    return acts.where((a) => !a.date.isBefore(start)).toList();
  }

  /// 2 quêtes du jour (l'une fixe, l'autre tournante selon le jour).
  static List<QuestDef> dailyQuests(DateTime now) {
    final dayIndex =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/
            (24 * 3600 * 1000);

    QuestDef rotating;
    if (dayIndex.isEven) {
      const t = [3.0, 4.0, 5.0];
      final v = t[dayIndex % t.length];
      rotating = QuestDef(
        id: 'd_dist',
        title: 'Parcours ${v.toStringAsFixed(0)} km aujourd\'hui',
        metric: QuestMetric.weeklyDistance, // mesuré sur les sorties du jour
        target: v,
        unit: 'km',
        reward: 70,
      );
    } else {
      const t = [20.0, 30.0, 40.0];
      final v = t[dayIndex % t.length];
      rotating = QuestDef(
        id: 'd_time',
        title: 'Cumule ${v.toStringAsFixed(0)} min aujourd\'hui',
        metric: QuestMetric.weeklyMinutes,
        target: v,
        unit: 'min',
        reward: 70,
      );
    }

    return [
      const QuestDef(
        id: 'd_run',
        title: 'Cours au moins une fois aujourd\'hui',
        metric: QuestMetric.weeklySessions,
        target: 1,
        unit: 'x',
        reward: 60,
      ),
      rotating,
    ];
  }

  static double questCurrent(QuestDef q, List<Activity> weekActs) {
    switch (q.metric) {
      case QuestMetric.weeklyDistance:
        return weekActs.fold<double>(0, (s, a) => s + a.distanceKmValue);
      case QuestMetric.weeklySessions:
        return weekActs.length.toDouble();
      case QuestMetric.longestSingle:
        return weekActs
            .map((a) => a.distanceKmValue)
            .fold<double>(0, max);
      case QuestMetric.weeklyElevation:
        return weekActs.fold<double>(0, (s, a) => s + a.elevationGainValue);
      case QuestMetric.weeklyMinutes:
        return weekActs.fold<double>(0, (s, a) => s + a.duration / 60.0);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Persistance des quêtes (boîte Hive 'settings', pas de codegen requis)
// ─────────────────────────────────────────────────────────────────────────────
class GameStore {
  static Box get _box => Hive.box('settings');

  static int get questBonusXp =>
      (_box.get('questBonusXp', defaultValue: 0) as num).toInt();

  static List<String> get _claims =>
      (_box.get('questClaims', defaultValue: <String>[]) as List).cast<String>();

  static bool isClaimed(String uid) => _claims.contains(uid);

  /// Réclame la récompense d'une quête (idempotent). Retourne l'XP ajoutée.
  static Future<int> claim(String uid, int reward) async {
    final c = _claims;
    if (c.contains(uid)) return 0;
    c.add(uid);
    await _box.put('questClaims', c);
    await _box.put('questBonusXp', questBonusXp + reward);
    return reward;
  }

  /// Ajoute de l'XP bonus (mini-jeux, etc.) au même pool que les quêtes.
  static Future<void> addBonusXp(int xp) async {
    if (xp <= 0) return;
    await _box.put('questBonusXp', questBonusXp + xp);
  }

  // ── Mini-profil (âge, etc.) ───────────────────────────────────────────────────
  static int? get age {
    final v = _box.get('player_age');
    return v is int ? v : null;
  }

  static Future<void> setAge(int years) => _box.put('player_age', years);
}

// ─────────────────────────────────────────────────────────────────────────────
// Échelle de déblocages (affichée dans l'écran Système)
// ─────────────────────────────────────────────────────────────────────────────
class Unlock {
  final int level;
  final String title;
  final String description;
  const Unlock(this.level, this.title, this.description);
}

const List<Unlock> kUnlocks = [
  Unlock(1, 'Premiers pas', 'Bienvenue, ta progression commence ici.'),
  Unlock(3, 'Renommer ses courses', 'Corrige le nom de tes sessions.'),
  Unlock(5, 'Palier Régulier', 'Premier palier franchi.'),
  Unlock(8, 'Quêtes avancées', 'Des défis hebdomadaires plus exigeants.'),
  Unlock(10, 'Palier Confirmé', 'Ton niveau grimpe sérieusement.'),
  Unlock(15, 'Palier Athlète', 'Tu deviens un vrai athlète.'),
  Unlock(20, 'Palier Élite', 'Tu rejoins l\'élite des coureurs.'),
  Unlock(30, 'Palier Légende', 'Le sommet de la progression.'),
];
