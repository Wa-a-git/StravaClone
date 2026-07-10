import 'dart:convert';
import 'dart:io';
import '../data/exercise_library.dart' show ExerciseCategoryX;
import '../models/activity.dart';
import '../models/daily_health_record.dart';
import '../models/musculation_log.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mycelium/mycelium.dart';
import 'package:permission_handler/permission_handler.dart';

class ExportService {
  /// URL Windroid par défaut (Tailscale du PC), partagée avec les autres apps.
  static const String defaultWindroidBaseUrl = 'http://100.66.241.12:8765';

  static String _sanitizeFileName(String text) {
    return text
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), '_')
        .toLowerCase();
  }

  static String? getSavedExportDirectory() {
    final box = Hive.box('settings');
    return box.get('export_directory') as String?;
  }

  static Future<void> saveExportDirectory(String path) async {
    final box = Hive.box('settings');
    await box.put('export_directory', path);
  }

  /// URL Windroid effective : réglage `windroid_base_url` s'il existe (chaîne
  /// vide = Windroid désactivé, écriture locale seule), sinon la valeur par défaut.
  static String getWindroidBaseUrl() {
    final v = Hive.box('settings').get('windroid_base_url') as String?;
    return v ?? defaultWindroidBaseUrl;
  }

  static Future<void> saveWindroidBaseUrl(String url) async {
    await Hive.box('settings').put('windroid_base_url', url.trim());
  }

  /// Résout le dossier d'export (déjà configuré, ou demande la permission +
  /// le sélecteur si c'est la toute première fois) puis exporte l'activité.
  /// Utilisé par tous les écrans qui produisent une vraie sortie (course
  /// libre, fractionné, zone d'allure) — évite de dupliquer la résolution
  /// de dossier dans chacun.
  static Future<String?> exportActivityToConfiguredDirectory(
      Activity activity) async {
    String? dirPath = getSavedExportDirectory();
    if (dirPath == null) {
      if (await Permission.manageExternalStorage.request().isGranted ||
          await Permission.storage.request().isGranted) {
        final selectedDir =
            await FilePicker.getDirectoryPath(dialogTitle: 'Choisir le dossier lié à Drive');
        if (selectedDir != null) {
          await saveExportDirectory(selectedDir);
          dirPath = selectedDir;
        }
      }
    }
    if (dirPath == null) return null;
    return saveActivityAsMarkdown(activity);
  }

  static Future<String?> saveActivityAsMarkdown(
    Activity activity, {
    bool useDownloads = false, // Paramètre ignoré maintenant
  }) async {
    try {
      final dt = activity.date;
      final id = activity.date.millisecondsSinceEpoch;
      final filenameDate =
          '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
      final nameSegment = activity.name != null && activity.name!.isNotEmpty
          ? _sanitizeFileName(activity.name!)
          : 'run';
      final fileBase = '$nameSegment-$filenameDate';

      final avgSpeedKmh = activity.avgSpeedKmhValue;
      final avgPace = activity.avgPace;

      // --- Frontmatter unifié via mycelium (id/date/type standardisés) ---
      final fields = <String, Object?>{
        'sport': _sportLabel(activity.workoutType),
        'distance_km': (activity.distance / 1000).toStringAsFixed(2),
        'duration_s': activity.duration,
        'pause_s': activity.pauseDurationSeconds,
        'avg_speed_kmh': avgSpeedKmh.toStringAsFixed(2),
        'avg_pace': avgPace,
        if (activity.hasElevation)
          'elevation_gain_m': activity.elevationGainValue.round(),
        if (activity.hasElevation)
          'elevation_loss_m': activity.elevationLossValue.round(),
        if (activity.name?.isNotEmpty == true) 'name': activity.name,
        // "route" : version échantillonnée (~80 pts) pour l'aperçu carte
        // Marble/Overview. "route_full_json" : trace complète, pour que la
        // fiche soit une sauvegarde fidèle même si la base locale est perdue
        // (voir incident du 09/07 — les fiches n'avaient jusqu'ici que
        // l'agrégat, pas de quoi reconstruire une activité à l'identique).
        if (activity.route.isNotEmpty) 'route': _encodeRoute(activity),
        if (activity.route.isNotEmpty)
          'route_full_json': jsonEncode(activity.route),
        if (activity.laps != null && activity.laps!.isNotEmpty)
          'laps_json': jsonEncode(activity.laps),
        if (activity.elevations != null && activity.elevations!.isNotEmpty)
          'elevations_json': jsonEncode(activity.elevations),
        if (activity.pointSeconds != null && activity.pointSeconds!.isNotEmpty)
          'point_seconds_json': jsonEncode(activity.pointSeconds),
      };

      final body =
          _buildBody(activity, id: id, avgPace: avgPace, avgSpeedKmh: avgSpeedKmh);

      // 1) PRIMAIRE : Windroid (souverain, écrit direct sur le PC via mycelium).
      final windroidUrl = getWindroidBaseUrl();
      if (windroidUrl.isNotEmpty) {
        final http = HttpVaultSource(windroidUrl,
            timeout: const Duration(seconds: 4), ignoredDirs: kIgnoredDirs);
        if (await http.available()) {
          try {
            final path = await writeToVault(http,
                subdir: 'Sport/Exercice',
                fileBase: fileBase,
                id: id,
                date: activity.date,
                myceliumClass: 'exercice',
                fields: fields,
                body: body,
                dailySection: 'Sport',
                dailyLine: _dailyLine(activity, fileBase));
            return 'Windroid: $path';
          } catch (_) {
            // Windroid a lâché en cours de route → on bascule sur le local.
          }
        }
      }

      // 2) FALLBACK : dossier local synchronisé Drive (PC injoignable).
      final savedPath = getSavedExportDirectory();
      if (savedPath == null) return null;

      // Racine du vault connue → on écrit dans Sport/Exercice/ + note du jour,
      // comme via Windroid. Sinon écriture directe dans le dossier choisi
      // (sans note du jour).
      final vaultRoot = _findVaultRoot(savedPath);
      if (vaultRoot != null) {
        final path = await writeToVault(LocalVaultSource(vaultRoot),
            subdir: 'Sport/Exercice',
            fileBase: fileBase,
            id: id,
            date: activity.date,
            myceliumClass: 'exercice',
            fields: fields,
            body: body,
            dailySection: 'Sport',
            dailyLine: _dailyLine(activity, fileBase));
        return '$vaultRoot/$path';
      }
      final path = await writeToVault(LocalVaultSource(savedPath),
          subdir: '',
          fileBase: fileBase,
          id: id,
          date: activity.date,
          myceliumClass: 'exercice',
          fields: fields,
          body: body);
      return '$savedPath/$path';
    } catch (e) {
      return null;
    }
  }

  /// Écrit la fiche santé du jour dans `Sport/Santé/` (une fiche par jour,
  /// ré-écrite à chaque synchro) + injecte un résumé sous `## Santé` dans la
  /// note du jour. Best-effort : jamais d'exception propagée (appelé en
  /// fire-and-forget depuis le provider santé).
  static Future<String?> saveHealthDayAsMarkdown(DailyHealthRecord record) async {
    try {
      final fileBase = record.key; // yyyy-MM-dd, une fiche par jour
      final fields = <String, Object?>{
        'steps': record.steps,
        'distance_km': record.distanceKm.toStringAsFixed(2),
        'active_calories': record.activeCalories.round(),
        if (record.restingHeartRate > 0)
          'resting_heart_rate': record.restingHeartRate.round(),
        if (record.hrv > 0) 'hrv': record.hrv.round(),
        if (record.spo2 > 0) 'spo2': record.spo2.round(),
        if (record.respiratoryRate > 0)
          'respiratory_rate': double.parse(record.respiratoryRate.toStringAsFixed(1)),
        if (record.vo2Max > 0)
          'vo2_max': double.parse(record.vo2Max.toStringAsFixed(1)),
        if (record.weightKg > 0)
          'weight_kg': double.parse(record.weightKg.toStringAsFixed(1)),
        'sleep_hours': double.parse((record.totalSleepMin / 60.0).toStringAsFixed(1)),
        'bio_score': record.bioScore,
        'sleep_score': record.sleepScore,
        'recovery_score': record.recoveryScore,
        'activity_score': record.activityScore,
      };
      final body = _buildHealthBody(record);
      final dailyLine = _healthDailyLine(record);
      // id stable (minuit du jour) : une fiche santé par jour, ré-exportée
      // idempotente au même id, comme les fiches d'activité.
      final id = record.date.millisecondsSinceEpoch;

      final windroidUrl = getWindroidBaseUrl();
      if (windroidUrl.isNotEmpty) {
        final http = HttpVaultSource(windroidUrl,
            timeout: const Duration(seconds: 4), ignoredDirs: kIgnoredDirs);
        if (await http.available()) {
          try {
            final path = await writeToVault(http,
                subdir: 'Sport/Santé',
                fileBase: fileBase,
                id: id,
                date: record.date,
                myceliumClass: 'sante',
                fields: fields,
                body: body,
                dailySection: 'Santé',
                dailyLine: dailyLine);
            return 'Windroid: $path';
          } catch (_) {
            // fallback local ci-dessous
          }
        }
      }

      final savedPath = getSavedExportDirectory();
      if (savedPath == null) return null;
      final vaultRoot = _findVaultRoot(savedPath);
      if (vaultRoot != null) {
        final path = await writeToVault(LocalVaultSource(vaultRoot),
            subdir: 'Sport/Santé',
            fileBase: fileBase,
            id: id,
            date: record.date,
            myceliumClass: 'sante',
            fields: fields,
            body: body,
            dailySection: 'Santé',
            dailyLine: dailyLine);
        return '$vaultRoot/$path';
      }
      return null; // pas de racine de vault connue : pas de fiche isolée hors contexte
    } catch (_) {
      return null;
    }
  }

  /// Écrit la séance de musculation du jour dans `Sport/Musculation/` (une
  /// fiche par jour, ré-écrite à chaque exercice ajouté/retiré — même
  /// principe idempotent que `saveHealthDayAsMarkdown`) + injecte un résumé
  /// sous `## Sport` dans la note du jour. Best-effort, jamais d'exception
  /// propagée. [entries] doit couvrir tout le jour [day] (voir
  /// `MusculationStore.entriesFor` côté appelant) ; rien n'est écrit si vide,
  /// pour ne pas créer de fiche "0 exercice" au premier tap annulé.
  static Future<String?> saveMusculationDayAsMarkdown(
      DateTime day, List<MusculationLogEntry> entries) async {
    if (entries.isEmpty) return null;
    try {
      final fileBase = MusculationLogEntry.keyFor(day); // yyyy-MM-dd
      final totalSets = entries.fold<int>(0, (s, e) => s + e.sets);
      final totalVolumeKg = entries.fold<double>(0, (s, e) => s + e.volumeKg);
      final fields = <String, Object?>{
        'exercises': entries.length,
        'total_sets': totalSets,
        'total_volume_kg': totalVolumeKg.toStringAsFixed(1),
        'categories': entries.map((e) => e.category.label).toSet().join(', '),
      };
      final body = _buildMusculationBody(entries);
      final dailyLine = _musculationDailyLine(fileBase, entries);
      // id stable (minuit du jour) : une fiche musculation par jour, comme
      // les fiches santé.
      final id = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;

      final windroidUrl = getWindroidBaseUrl();
      if (windroidUrl.isNotEmpty) {
        final http = HttpVaultSource(windroidUrl,
            timeout: const Duration(seconds: 4), ignoredDirs: kIgnoredDirs);
        if (await http.available()) {
          try {
            final path = await writeToVault(http,
                subdir: 'Sport/Musculation',
                fileBase: fileBase,
                id: id,
                date: day,
                myceliumClass: 'musculation',
                fields: fields,
                body: body,
                dailySection: 'Sport',
                dailyLine: dailyLine);
            return 'Windroid: $path';
          } catch (_) {
            // fallback local ci-dessous
          }
        }
      }

      final savedPath = getSavedExportDirectory();
      if (savedPath == null) return null;
      final vaultRoot = _findVaultRoot(savedPath);
      if (vaultRoot != null) {
        final path = await writeToVault(LocalVaultSource(vaultRoot),
            subdir: 'Sport/Musculation',
            fileBase: fileBase,
            id: id,
            date: day,
            myceliumClass: 'musculation',
            fields: fields,
            body: body,
            dailySection: 'Sport',
            dailyLine: dailyLine);
        return '$vaultRoot/$path';
      }
      return null; // pas de racine de vault connue : pas de fiche isolée hors contexte
    } catch (_) {
      return null;
    }
  }

  /// Écrit une fiche (+ éventuellement le résumé du jour) via une source vault
  /// quelconque (Windroid `HttpVaultSource` ou locale `LocalVaultSource`).
  /// Isolé et public pour être testable avec une source en mémoire. Renvoie
  /// le chemin relatif de la fiche créée.
  static Future<String> writeToVault(
    VaultSource source, {
    required String subdir,
    required String fileBase,
    required int id,
    required DateTime date,
    required String myceliumClass,
    required Map<String, Object?> fields,
    required String body,
    String? dailySection,
    String? dailyLine,
  }) async {
    final repo = VaultRepository(source);
    final note = await EntryWriter(repo).createEntry(
      subdir: subdir,
      fileName: fileBase,
      myceliumClass: myceliumClass,
      id: id,
      date: date,
      fields: fields,
      body: body,
      overwrite: true, // ré-export = même chemin, pas de doublon
    );
    if (dailySection != null && dailyLine != null) {
      try {
        await DailyNoteService(repo)
            .appendToToday(section: dailySection, content: dailyLine, day: date);
      } catch (_) {
        // Note du jour best-effort : n'empêche pas l'écriture de la fiche.
      }
    }
    return note.path;
  }

  /// Libellé lisible du type de séance, pour le frontmatter `sport:` — sert
  /// à ce que l'aperçu Marble/Overview distingue fractionné/zone d'allure
  /// d'une course libre plutôt que de tout afficher comme "Run".
  static String _sportLabel(String? workoutType) => switch (workoutType) {
        'interval' => 'Fractionné',
        'pace_zone' => 'Zone d\'allure',
        _ => 'Run',
      };

  /// Trace GPS compacte pour le frontmatter (`lat,lng;lat,lng;...`) — sert à
  /// afficher un aperçu du tracé dans l'Overview de Marble sans dupliquer la
  /// carte Leaflet complète du corps. Même sous-échantillonnage (~80 points)
  /// que la carte, en string plutôt qu'en liste imbriquée (le frontmatter YAML
  /// de mycelium ne sérialise que des scalaires pour l'instant).
  static String? _encodeRoute(Activity activity) {
    final route = activity.route;
    if (route.isEmpty) return null;
    final step = (route.length / 80).ceil().clamp(1, route.length);
    final parts = <String>[];
    for (int i = 0; i < route.length; i += step) {
      final pt = route[i];
      final lat = (pt[0]).toDouble();
      final lng = (pt[1]).toDouble();
      parts.add('${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}');
    }
    return parts.join(';');
  }

  /// Ligne de résumé injectée dans la note du jour (modèle "push" du plan).
  static String _dailyLine(Activity activity, String fileBase) {
    final dist = (activity.distance / 1000).toStringAsFixed(2);
    return '- 🏃 [[$fileBase]] — $dist km en ${activity.durationFormatted} (${activity.avgPace}/km)';
  }

  /// Ligne de résumé santé injectée dans la note du jour.
  static String _healthDailyLine(DailyHealthRecord record) {
    final h = record.totalSleepMin ~/ 60;
    final m = (record.totalSleepMin % 60).round();
    return '- 🫀 [[${record.key}]] — Bio-Score ${record.bioScore}/100, '
        'sommeil ${h}h${m.toString().padLeft(2, '0')}, ${record.steps} pas';
  }

  /// Ligne de résumé musculation injectée dans la note du jour.
  static String _musculationDailyLine(
      String fileBase, List<MusculationLogEntry> entries) {
    final totalSets = entries.fold<int>(0, (s, e) => s + e.sets);
    final totalVolumeKg = entries.fold<double>(0, (s, e) => s + e.volumeKg);
    final n = entries.length;
    final volumeSuffix =
        totalVolumeKg > 0 ? ', ${totalVolumeKg.toStringAsFixed(0)} kg soulevés' : '';
    return '- 🏋️ [[$fileBase]] — $n exercice${n > 1 ? 's' : ''}, '
        '$totalSets série${totalSets > 1 ? 's' : ''}$volumeSuffix';
  }

  /// Remonte depuis [start] jusqu'à trouver un dossier contenant `.obsidian`
  /// (marqueur de racine de vault Obsidian). null si introuvable (≤ 5 niveaux).
  static String? _findVaultRoot(String start) {
    var dir = Directory(start);
    for (var i = 0; i < 5; i++) {
      if (Directory('${dir.path}/.obsidian').existsSync()) return dir.path;
      final parent = dir.parent;
      if (parent.path == dir.path) break; // racine du disque atteinte
      dir = parent;
    }
    return null;
  }

  /// Construit le corps markdown de la fiche (hors frontmatter) : titre néon,
  /// dashboard de stats, carte Leaflet, tableau des boucles + graphe Echarts.
  static String _buildBody(
    Activity activity, {
    required int id,
    required String avgPace,
    required double avgSpeedKmh,
  }) {
    final dt = activity.date;
    final readableDate =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
    final safeTitle = activity.name?.isNotEmpty == true
        ? activity.name
        : '🏃 Sortie du $readableDate';

    // Extraction de la trace GPS pour la mini-map Obsidian Leaflet
    String leafletBlock = '';
    try {
      if (activity.route.isNotEmpty) {
        final route = activity.route;
        List<String> coords = [];
        double sLat = 0, sLng = 0;
        double minLat = 90.0, maxLat = -90.0;
        double minLng = 180.0, maxLng = -180.0;
        int step = (route.length / 80).ceil();
        if (step < 1) step = 1;

        for (int i = 0; i < route.length; i += step) {
          final pt = route[i];
          final lat = (pt[0]).toDouble();
          final lng = (pt[1]).toDouble();
          coords.add('[$lat, $lng]');
          sLat += lat;
          sLng += lng;
          if (lat < minLat) minLat = lat;
          if (lat > maxLat) maxLat = lat;
          if (lng < minLng) minLng = lng;
          if (lng > maxLng) maxLng = lng;
        }
        final centerLat = sLat / coords.length;
        final centerLng = sLng / coords.length;

        final latDiff = maxLat - minLat;
        final lngDiff = maxLng - minLng;
        final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

        int dynamicZoom = 17;
        if (maxDiff < 0.003) {
          dynamicZoom = 18;
        } else if (maxDiff < 0.008) {
          dynamicZoom = 17;
        } else if (maxDiff < 0.020) {
          dynamicZoom = 16;
        } else if (maxDiff < 0.045) {
          dynamicZoom = 15;
        } else if (maxDiff < 0.090) {
          dynamicZoom = 14;
        } else {
          dynamicZoom = 13;
        }

        final startPt = coords.first.replaceAll('[', '').replaceAll(']', '');
        final endPt = coords.last.replaceAll('[', '').replaceAll(']', '');

        leafletBlock = '''
### 🗺️ Carte du parcours

```leaflet
id: route_$id
lat: $centerLat
long: $centerLng
defaultZoom: $dynamicZoom
maxZoom: 19
width: 100%
height: 450px
tileServer: https://tile.openstreetmap.org/{z}/{x}/{y}.png
path: [${coords.join(', ')}]
marker: default, $startPt
marker: default, $endPt
```
''';
      }
    } catch (_) {}

    // Graphe Echarts de l'allure par boucle
    String echartsBlock = '';
    if (activity.laps != null && activity.laps!.isNotEmpty) {
      List<String> labels = [];
      List<double> data = [];
      for (var lap in activity.laps!) {
        labels.add('"B${lap['lapNumber']}"');
        final lDuration = lap['duration'] as int;
        final lDist = (lap['distance'] as num).toDouble();
        final lPaceSec = lDist > 0 ? (lDuration / (lDist / 1000)).round() : 0;
        data.add(double.parse((lPaceSec / 60.0).toStringAsFixed(2)));
      }
      echartsBlock = '''
### 📈 Évolution de l'allure

```echarts
{
  "tooltip": { "trigger": "axis", "formatter": "{b}: {c} min/km" },
  "xAxis": { "type": "category", "data": [${labels.join(', ')}] },
  "yAxis": { "type": "value", "inverse": true, "name": "Allure (min/km)", "nameLocation": "middle", "nameGap": 30 },
  "series": [{ "data": [${data.join(', ')}], "type": "line", "smooth": true, "itemStyle": { "color": "#F55CBD" }, "areaStyle": { "color": "rgba(245, 92, 189, 0.2)" } }]
}
```
''';
    }

    final buffer = StringBuffer();
    buffer.writeln(); // ligne vide sous le frontmatter

    buffer.writeln(
        '<h1 style="color: #F55CBD; border-bottom: 2px solid #00FFFF; padding-bottom: 10px; text-shadow: 0 0 10px rgba(245, 92, 189, 0.4); margin-bottom: 5px;">$safeTitle</h1>');
    buffer.writeln();
    buffer.writeln('> [!quote] 📋 **Rapport Technique**');
    buffer.writeln('> *Données télémétriques enregistrées via Arcade Health.*');
    buffer.writeln();
    buffer.writeln('## 📊 Statistiques Globales');
    buffer.writeln();

    buffer.writeln(
        '<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-around; background-color: #141419; padding: 20px; border-radius: 12px; border: 1px solid #F55CBD; box-shadow: 0 4px 15px rgba(245, 92, 189, 0.15); text-align: center; margin-bottom: 20px; font-family: sans-serif;">');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">📏</span><br/><strong style="color: #00FFFF; font-size: 18px;">${(activity.distance / 1000).toStringAsFixed(2)} km</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Distance</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⏱️</span><br/><strong style="color: #00FFFF; font-size: 18px;">${activity.duration ~/ 60}m ${activity.duration % 60}s</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Mouvement</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⏸️</span><br/><strong style="color: #F8FF00; font-size: 18px;">${activity.pauseDurationSeconds ~/ 60}m ${activity.pauseDurationSeconds % 60}s</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Pause</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⚡</span><br/><strong style="color: #F55CBD; font-size: 18px;">${avgSpeedKmh.toStringAsFixed(2)} km/h</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Vitesse Moy.</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🎯</span><br/><strong style="color: #F55CBD; font-size: 18px;">$avgPace /km</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Allure Moy.</span></div>');
    if (activity.hasElevation) {
      buffer.writeln(
          '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⛰️</span><br/><strong style="color: #39FF14; font-size: 18px;">${activity.elevationGainValue.round()} m</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Dénivelé +</span></div>');
    }
    buffer.writeln('</div>');
    buffer.writeln();

    if (leafletBlock.isNotEmpty) {
      buffer.writeln(leafletBlock);
    }

    if (activity.laps != null && activity.laps!.isNotEmpty) {
      buffer.writeln('## ⏱️ Analyse des Boucles');
      buffer.writeln();
      buffer.writeln(
          '<table style="width: 100%; text-align: center; border-collapse: collapse; margin-bottom: 20px; font-family: sans-serif;">');
      buffer.writeln(
          '  <tr style="background-color: #141419; color: #00FFFF; border-bottom: 2px solid #F55CBD;">');
      buffer.writeln(
          '    <th style="padding: 12px;">Boucle</th><th style="padding: 12px;">Distance (km)</th><th style="padding: 12px;">Temps</th><th style="padding: 12px;">Allure</th>');
      buffer.writeln('  </tr>');
      for (var lap in activity.laps!) {
        final lDuration = lap['duration'] as int;
        final lDist =
            ((lap['distance'] as num).toDouble() / 1000).toStringAsFixed(2);
        final lPaceSec = (lap['distance'] as num) > 0
            ? (lDuration / ((lap['distance'] as num) / 1000)).round()
            : 0;
        final lPaceStr =
            '${(lPaceSec ~/ 60).toString().padLeft(2, '0')}:${(lPaceSec % 60).toString().padLeft(2, '0')}';
        buffer.writeln('  <tr style="border-bottom: 1px solid #333333;">');
        buffer.writeln(
            '    <td style="padding: 10px; color: #AAAAAA;">#${lap['lapNumber']}</td><td style="padding: 10px; font-weight: bold;">$lDist</td><td style="padding: 10px;">${lDuration ~/ 60}m ${lDuration % 60}s</td><td style="padding: 10px; color: #F55CBD;">$lPaceStr /km</td>');
        buffer.writeln('  </tr>');
      }
      buffer.writeln('</table>');
      buffer.writeln();
      buffer.write(echartsBlock);
    }

    return buffer.toString();
  }

  /// Construit le corps markdown de la fiche santé quotidienne — même
  /// habillage néon que les fiches de course (dashboard de stats + détail
  /// sommeil), pour rester au même niveau visuel.
  static String _buildHealthBody(DailyHealthRecord record) {
    final dt = record.date;
    final readableDate =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final h = record.totalSleepMin ~/ 60;
    final m = (record.totalSleepMin % 60).round();

    final buffer = StringBuffer();
    buffer.writeln();
    buffer.writeln(
        '<h1 style="color: #F55CBD; border-bottom: 2px solid #00FFFF; padding-bottom: 10px; text-shadow: 0 0 10px rgba(245, 92, 189, 0.4); margin-bottom: 5px;">🫀 Santé du $readableDate</h1>');
    buffer.writeln();
    buffer.writeln('> [!quote] 📋 **Aptitude du jour**');
    buffer.writeln('> *Données enregistrées via Arcade Health.*');
    buffer.writeln();
    buffer.writeln('## 📊 Scores');
    buffer.writeln();
    buffer.writeln(
        '<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-around; background-color: #141419; padding: 20px; border-radius: 12px; border: 1px solid #F55CBD; box-shadow: 0 4px 15px rgba(245, 92, 189, 0.15); text-align: center; margin-bottom: 20px; font-family: sans-serif;">');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🧬</span><br/><strong style="color: #00FFFF; font-size: 18px;">${record.bioScore}/100</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Bio-Score</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">😴</span><br/><strong style="color: #9D4EFF; font-size: 18px;">${record.sleepScore}/100</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Sommeil</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🔋</span><br/><strong style="color: #00FFFF; font-size: 18px;">${record.recoveryScore}/100</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Récupération</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🏃</span><br/><strong style="color: #39FF14; font-size: 18px;">${record.activityScore}/100</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Activité</span></div>');
    buffer.writeln('</div>');
    buffer.writeln();

    buffer.writeln('## 🩺 Indicateurs');
    buffer.writeln();
    buffer.writeln(
        '<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-around; background-color: #141419; padding: 20px; border-radius: 12px; border: 1px solid #00FFFF; text-align: center; margin-bottom: 20px; font-family: sans-serif;">');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">👣</span><br/><strong style="color: #F55CBD; font-size: 18px;">${record.steps}</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Pas</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">📏</span><br/><strong style="color: #F55CBD; font-size: 18px;">${record.distanceKm.toStringAsFixed(2)} km</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Distance</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">😴</span><br/><strong style="color: #9D4EFF; font-size: 18px;">${h}h${m.toString().padLeft(2, '0')}</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Sommeil</span></div>');
    if (record.restingHeartRate > 0) {
      buffer.writeln(
          '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">❤️</span><br/><strong style="color: #FF2E88; font-size: 18px;">${record.restingHeartRate.round()} bpm</strong><br/><span style="color: #AAAAAA; font-size: 12px;">FC repos</span></div>');
    }
    if (record.hrv > 0) {
      buffer.writeln(
          '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">💓</span><br/><strong style="color: #00FFFF; font-size: 18px;">${record.hrv.round()} ms</strong><br/><span style="color: #AAAAAA; font-size: 12px;">HRV</span></div>');
    }
    if (record.vo2Max > 0) {
      buffer.writeln(
          '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🫁</span><br/><strong style="color: #39FF14; font-size: 18px;">${record.vo2Max.toStringAsFixed(1)}</strong><br/><span style="color: #AAAAAA; font-size: 12px;">VO2 max</span></div>');
    }
    buffer.writeln('</div>');

    if (record.totalSleepMin > 0) {
      final deepH = record.sleepDeepMin ~/ 60, deepM = (record.sleepDeepMin % 60).round();
      final remH = record.sleepRemMin ~/ 60, remM = (record.sleepRemMin % 60).round();
      final lightH = record.sleepLightMin ~/ 60, lightM = (record.sleepLightMin % 60).round();
      buffer.writeln();
      buffer.writeln('## 🛌 Détail sommeil');
      buffer.writeln();
      buffer.writeln('- Profond : ${deepH}h${deepM.toString().padLeft(2, '0')}');
      buffer.writeln('- Paradoxal : ${remH}h${remM.toString().padLeft(2, '0')}');
      buffer.writeln('- Léger : ${lightH}h${lightM.toString().padLeft(2, '0')}');
    }

    return buffer.toString();
  }

  /// Construit le corps markdown de la fiche musculation — même habillage
  /// néon que les fiches de course/santé, pour rester au même niveau visuel.
  static String _buildMusculationBody(List<MusculationLogEntry> entries) {
    final totalSets = entries.fold<int>(0, (s, e) => s + e.sets);
    final totalVolumeKg = entries.fold<double>(0, (s, e) => s + e.volumeKg);

    final buffer = StringBuffer();
    buffer.writeln();
    buffer.writeln(
        '<h1 style="color: #F55CBD; border-bottom: 2px solid #00FFFF; padding-bottom: 10px; text-shadow: 0 0 10px rgba(245, 92, 189, 0.4); margin-bottom: 5px;">🏋️ Séance musculation</h1>');
    buffer.writeln();
    buffer.writeln('> [!quote] 📋 **Rapport Technique**');
    buffer.writeln('> *Données enregistrées via Arcade Health.*');
    buffer.writeln();
    buffer.writeln('## 📊 Résumé');
    buffer.writeln();
    buffer.writeln(
        '<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-around; background-color: #141419; padding: 20px; border-radius: 12px; border: 1px solid #F55CBD; box-shadow: 0 4px 15px rgba(245, 92, 189, 0.15); text-align: center; margin-bottom: 20px; font-family: sans-serif;">');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🏋️</span><br/><strong style="color: #00FFFF; font-size: 18px;">${entries.length}</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Exercices</span></div>');
    buffer.writeln(
        '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🔁</span><br/><strong style="color: #F55CBD; font-size: 18px;">$totalSets</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Séries totales</span></div>');
    if (totalVolumeKg > 0) {
      buffer.writeln(
          '  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⚖️</span><br/><strong style="color: #FFD23F; font-size: 18px;">${totalVolumeKg.toStringAsFixed(0)}</strong><br/><span style="color: #AAAAAA; font-size: 12px;">kg (volume)</span></div>');
    }
    buffer.writeln('</div>');
    buffer.writeln();

    buffer.writeln('## 💪 Détail des exercices');
    buffer.writeln();
    buffer.writeln(
        '<table style="width: 100%; text-align: center; border-collapse: collapse; margin-bottom: 20px; font-family: sans-serif;">');
    buffer.writeln(
        '  <tr style="background-color: #141419; color: #00FFFF; border-bottom: 2px solid #F55CBD;">');
    buffer.writeln(
        '    <th style="padding: 12px;">Exercice</th><th style="padding: 12px;">Catégorie</th><th style="padding: 12px;">Séries × Reps</th><th style="padding: 12px;">Charge</th>');
    buffer.writeln('  </tr>');
    for (final e in entries) {
      final charge = e.chargeKg > 0 ? '${e.chargeKg.toStringAsFixed(1)} kg' : '—';
      buffer.writeln('  <tr style="border-bottom: 1px solid #333333;">');
      buffer.writeln(
          '    <td style="padding: 10px; font-weight: bold;">${e.exerciseName}</td><td style="padding: 10px; color: #AAAAAA;">${e.category.label}</td><td style="padding: 10px; color: #F55CBD;">${e.sets} × ${e.reps}</td><td style="padding: 10px; color: #FFD23F;">$charge</td>');
      buffer.writeln('  </tr>');
    }
    buffer.writeln('</table>');

    return buffer.toString();
  }
}
