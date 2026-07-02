import 'dart:io';
import '../models/activity.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:mycelium/mycelium.dart';

class ExportService {
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

  static Future<String?> saveActivityAsMarkdown(
    Activity activity, {
    bool useDownloads = false, // Paramètre ignoré maintenant
  }) async {
    try {
      final savedPath = getSavedExportDirectory();
      if (savedPath == null) return null; // Sécurité

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
        'sport': 'Run',
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
      };

      final body = _buildBody(activity, id: id, avgPace: avgPace, avgSpeedKmh: avgSpeedKmh);

      // Écrit dans le dossier d'export choisi (racine = dossier lié à Drive).
      final repo = VaultRepository(LocalVaultSource(savedPath));
      final writer = EntryWriter(repo);
      final note = await writer.createEntry(
        subdir: '',
        fileName: fileBase,
        myceliumClass: 'strava',
        id: id,
        date: activity.date,
        fields: fields,
        body: body,
        overwrite: true, // ré-export = même chemin, pas de doublon
      );

      final exportedPath = '$savedPath/${note.path}';

      // --- "Push" : résumé injecté dans la note du jour (best-effort) ---
      await _injectDailySummary(savedPath, activity, fileBase);

      return exportedPath;
    } catch (e) {
      return null;
    }
  }

  /// Injecte une ligne de résumé de la course dans la note quotidienne du
  /// vault (modèle "push" du plan Marble). Best-effort : ne bloque jamais
  /// l'export. N'écrit que si la racine du vault est identifiable (dossier
  /// `.obsidian`), pour ne pas éparpiller des notes ailleurs.
  static Future<void> _injectDailySummary(
      String exportDir, Activity activity, String fileBase) async {
    try {
      final vaultRoot = _findVaultRoot(exportDir);
      if (vaultRoot == null) return;

      final dist = (activity.distance / 1000).toStringAsFixed(2);
      final line =
          '- 🏃 [[$fileBase]] — $dist km en ${activity.durationFormatted} (${activity.avgPace}/km)';

      final service = DailyNoteService(VaultRepository(LocalVaultSource(vaultRoot)));
      await service.appendToToday(
          section: 'Sport', content: line, day: activity.date);
    } catch (_) {
      // Vault injoignable / pas de racine : on n'empêche pas l'export.
    }
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
    buffer.writeln('> *Données télémétriques enregistrées via Wa\'a Strava.*');
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
}
