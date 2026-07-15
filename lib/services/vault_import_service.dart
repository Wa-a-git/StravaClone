// lib/services/vault_import_service.dart
// Restauration ponctuelle : reconstruit les activités locales (Hive) à partir
// des fiches déjà exportées dans le vault (Sport/Exercice/*.md). Sert de filet
// de sécurité si la base locale est perdue (ex. désinstallation accidentelle)
// alors que les fiches, elles, survivent côté vault (Windroid ou dossier local).
//
// Fidélité de la reconstruction selon l'âge de la fiche : depuis l'ajout des
// champs `*_json` (laps, élévations, secondes par point, trace complète) à
// l'export, une fiche récente restaure l'activité à l'identique. Les fiches
// plus anciennes (avant ce changement) n'ont que les champs agrégés
// (distance, durée, allure, route échantillonnée ~80 points) — la course
// réapparaît avec ses stats globales correctes, mais sans détail par boucle
// ni profil d'altitude point par point.
import 'dart:convert';
import 'dart:io';

import 'package:mycelium/mycelium.dart';

import '../models/activity.dart';
import 'export_service.dart';
import 'hive_service.dart';

class VaultImportService {
  /// Reconstruit les activités manquantes depuis `Sport/Exercice/*.md`.
  /// Ignore toute fiche dont l'`id` (epoch ms, = date exacte de l'activité)
  /// correspond déjà à une activité locale — reste sûr à relancer plusieurs
  /// fois (idempotent, n'écrase jamais une activité déjà présente).
  static Future<VaultImportResult> importActivities() async {
    final source = await _resolveSource();
    if (source == null) {
      return const VaultImportResult(imported: 0, skipped: 0, failed: 0, total: 0);
    }

    final repo = VaultRepository(source);
    final entries = await repo.source.list();
    final ficheEntries = entries.where(
        (e) => e.path.startsWith('Sport/Exercice/') && e.path.endsWith('.md'));

    final existingDates = HiveService.getAllActivities()
        .map((a) => a.date.millisecondsSinceEpoch)
        .toSet();

    var imported = 0, skipped = 0, failed = 0, total = 0;
    for (final entry in ficheEntries) {
      total++;
      try {
        final raw = await repo.source.read(entry.path);
        if (raw == null) {
          failed++;
          continue;
        }
        final activity = _parseActivity(raw);
        if (activity == null) {
          failed++;
          continue;
        }
        if (existingDates.contains(activity.date.millisecondsSinceEpoch)) {
          skipped++;
          continue;
        }
        await HiveService.saveActivity(activity);
        existingDates.add(activity.date.millisecondsSinceEpoch);
        imported++;
      } catch (_) {
        failed++;
      }
    }
    return VaultImportResult(
        imported: imported, skipped: skipped, failed: failed, total: total);
  }

  static Future<VaultSource?> _resolveSource() async {
    final windroidUrl = ExportService.getWindroidBaseUrl();
    if (windroidUrl.isNotEmpty) {
      final http = HttpVaultSource(windroidUrl, timeout: const Duration(seconds: 6));
      if (await http.available()) return http;
    }
    final savedPath = ExportService.getSavedExportDirectory();
    if (savedPath == null) return null;
    // Même résolution que ExportService : si le dossier choisi est sous un
    // vrai vault Obsidian, les fiches ont été écrites sous "Sport/Exercice/"
    // relatif à la racine du vault (pas au dossier choisi lui-même).
    return LocalVaultSource(_findVaultRoot(savedPath) ?? savedPath);
  }

  /// Remonte depuis [start] jusqu'à trouver un dossier contenant `.obsidian`
  /// — même logique que le `_findVaultRoot` privé de ExportService.
  static String? _findVaultRoot(String start) {
    var dir = Directory(start);
    for (var i = 0; i < 5; i++) {
      if (Directory('${dir.path}/.obsidian').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// Reconstruit une [Activity] à partir du frontmatter d'une fiche
  /// `Sport/Exercice/*.md` — mêmes clés que celles écrites par
  /// `ExportService.saveActivityAsMarkdown`. Null si les champs minimaux
  /// (id, distance, durée) sont absents ou invalides.
  ///
  /// `route_full_json`/`laps_json`/`elevations_json`/`point_seconds_json`
  /// (fiches exportées après le 09/07) donnent une reconstruction fidèle ;
  /// à défaut, repli sur la trace échantillonnée `route` (~80 pts) — fiches
  /// plus anciennes, ou laps/élévations simplement absents de cette course.
  static Activity? _parseActivity(String raw) {
    final fm = splitFrontmatter(raw);
    final data = fm.data;

    // Format natif (export de l'app courante) : distance_km / duration_s /
    // id = epoch ms de la date.
    final id = _asInt(data['id']);
    final distanceKm = _asDouble(data['distance_km']);
    final durationS = _asInt(data['duration_s']);
    if (id != null && distanceKm != null && durationS != null) {
      final fullRoute = _parseRouteJson(data['route_full_json'] as String?);
      final laps = _parseLaps(data['laps_json'] as String?);

      return Activity(
        date: DateTime.fromMillisecondsSinceEpoch(id),
        distance: distanceKm * 1000,
        duration: durationS,
        route: fullRoute ?? _parseRoute(data['route'] as String?),
        name: (data['name'] as String?)?.trim(),
        pauseDurationSeconds: _asInt(data['pause_s']) ?? 0,
        workoutType: _workoutTypeFor(data['sport'] as String?),
        laps: laps,
        lapCount: laps?.length ?? 0,
        elevations: _parseDoubleListJson(data['elevations_json'] as String?),
        pointSeconds: _parseIntListJson(data['point_seconds_json'] as String?),
      );
    }

    // Format legacy (import Strava d'origine, fiches antérieures à l'export
    // de cette app) : start_date (ISO) / moving_time (s) / distance (m).
    // `id` y est le vrai identifiant Strava — inutilisable comme epoch ms,
    // on prend `start_date` à la place. Pas de trace GPS/laps dans ce format.
    final startDate = _asDateTime(data['start_date']);
    final movingTime = _asInt(data['moving_time']);
    final distanceM = _asDouble(data['distance']);
    if (startDate != null && movingTime != null && distanceM != null) {
      return Activity(
        date: startDate,
        distance: distanceM,
        duration: movingTime,
        route: const [],
        workoutType: _workoutTypeFor(data['sport_type'] as String?),
      );
    }

    return null;
  }

  static DateTime? _asDateTime(Object? v) {
    if (v is! String || v.isEmpty) return null;
    return DateTime.tryParse(v)?.toLocal();
  }

  static String? _workoutTypeFor(String? sportLabel) => switch (sportLabel) {
        'Fractionné' => 'interval',
        'Zone d\'allure' => 'pace_zone',
        'Tapis' => 'treadmill',
        'Course (manuel)' => 'run_manual',
        'Cardio' => 'other_cardio',
        _ => null,
      };

  static List<List<double>> _parseRoute(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const [];
    final points = <List<double>>[];
    for (final pair in encoded.split(';')) {
      final parts = pair.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat != null && lng != null) points.add([lat, lng]);
    }
    return points;
  }

  static List<List<double>>? _parseRouteJson(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final decoded = jsonDecode(encoded) as List;
      return [
        for (final pt in decoded)
          [for (final v in pt as List) (v as num).toDouble()],
      ];
    } catch (_) {
      return null;
    }
  }

  static List<dynamic>? _parseLaps(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return jsonDecode(encoded) as List;
    } catch (_) {
      return null;
    }
  }

  static List<double>? _parseDoubleListJson(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return [for (final v in jsonDecode(encoded) as List) (v as num).toDouble()];
    } catch (_) {
      return null;
    }
  }

  static List<int>? _parseIntListJson(String? encoded) {
    if (encoded == null || encoded.isEmpty) return null;
    try {
      return [for (final v in jsonDecode(encoded) as List) (v as num).toInt()];
    } catch (_) {
      return null;
    }
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static double? _asDouble(Object? v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

class VaultImportResult {
  final int imported;
  final int skipped;
  final int failed;
  final int total;
  const VaultImportResult(
      {required this.imported,
      required this.skipped,
      required this.failed,
      required this.total});
}
