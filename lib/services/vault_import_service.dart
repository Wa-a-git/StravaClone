// lib/services/vault_import_service.dart
// Restauration ponctuelle : reconstruit les activités locales (Hive) à partir
// des fiches déjà exportées dans le vault (Sport/Exercice/*.md). Sert de filet
// de sécurité si la base locale est perdue (ex. désinstallation accidentelle)
// alors que les fiches, elles, survivent côté vault (Windroid ou dossier local).
//
// Reconstruction partielle par nature : le frontmatter ne contient que les
// champs agrégés écrits par ExportService (distance, durée, allure, route
// échantillonnée à ~80 points...) — pas le détail par lap ni le profil
// d'altitude point par point. Les courses réapparaissent avec leurs stats
// globales correctes ; le détail fin (boucles, dénivelé) reste perdu.
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
  static Activity? _parseActivity(String raw) {
    final fm = splitFrontmatter(raw);
    final data = fm.data;
    final id = _asInt(data['id']);
    final distanceKm = _asDouble(data['distance_km']);
    final durationS = _asInt(data['duration_s']);
    if (id == null || distanceKm == null || durationS == null) return null;

    return Activity(
      date: DateTime.fromMillisecondsSinceEpoch(id),
      distance: distanceKm * 1000,
      duration: durationS,
      route: _parseRoute(data['route'] as String?),
      name: (data['name'] as String?)?.trim(),
      pauseDurationSeconds: _asInt(data['pause_s']) ?? 0,
      workoutType: _workoutTypeFor(data['sport'] as String?),
    );
  }

  static String? _workoutTypeFor(String? sportLabel) => switch (sportLabel) {
        'Fractionné' => 'interval',
        'Zone d\'allure' => 'pace_zone',
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
