import 'dart:io';
import '../models/activity.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ExportService {
  static String _formatDateIsoUtc(DateTime dt) => dt.toUtc().toIso8601String();

  static String _formatDateLocal(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

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

      final dir = Directory(savedPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final dt = activity.date;
      final id = activity.date.millisecondsSinceEpoch.toString();
      final filenameDate = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}_${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
      final nameSegment = activity.name != null && activity.name!.isNotEmpty
          ? _sanitizeFileName(activity.name!)
          : 'run';
      final filename = '$nameSegment-$filenameDate.md';
      final file = File('${dir.path}/$filename');

      final avgSpeed = activity.duration > 0
          ? (activity.distance / activity.duration)
          : 0.0; // m/s

      final avgSpeedKmh = avgSpeed * 3.6;
      
      String avgPace = '--:--';
      if (activity.distance > 0 && activity.duration > 0) {
        final paceSeconds = (activity.duration / (activity.distance / 1000)).round();
        avgPace = '${(paceSeconds ~/ 60).toString().padLeft(2, '0')}:${(paceSeconds % 60).toString().padLeft(2, '0')}';
      }

      final readableDate = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} à ${dt.hour.toString().padLeft(2, '0')}h${dt.minute.toString().padLeft(2, '0')}';
      final safeTitle = activity.name?.isNotEmpty == true ? activity.name : '🏃 Sortie du $readableDate';

      // Extraction de la trace GPS pour générer la mini-map Obsidian Leaflet
      String leafletBlock = '';
      try {
        if (activity.route.isNotEmpty) {
          final route = activity.route as List<dynamic>;
          List<String> coords = [];
          double sLat = 0, sLng = 0;
          double minLat = 90.0, maxLat = -90.0;
          double minLng = 180.0, maxLng = -180.0;
          int step = (route.length / 80).ceil(); // On limite à ~80 points max pour ne pas surcharger la note
          if (step < 1) step = 1;
          
          for (int i = 0; i < route.length; i += step) {
            final pt = route[i];
            double lat = 0.0;
            double lng = 0.0;
            
            if (pt is List && pt.length >= 2) {
              lat = (pt[0] as num).toDouble();
              lng = (pt[1] as num).toDouble();
            } else if (pt is Map) {
              lat = ((pt['latitude'] ?? pt['lat']) as num).toDouble();
              lng = ((pt['longitude'] ?? pt['lng']) as num).toDouble();
            } else {
              lat = (pt.latitude as num).toDouble();
              lng = (pt.longitude as num).toDouble();
            }
            
            coords.add('[$lat, $lng]');
            sLat += lat; sLng += lng;
            if (lat < minLat) minLat = lat;
            if (lat > maxLat) maxLat = lat;
            if (lng < minLng) minLng = lng;
            if (lng > maxLng) maxLng = lng;
          }
          final centerLat = sLat / coords.length;
          final centerLng = sLng / coords.length;
          
          // Calcul dynamique du zoom pour encadrer parfaitement le trajet
          final latDiff = maxLat - minLat;
          final lngDiff = maxLng - minLng;
          final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;
          
          // Calcul dynamique du zoom pour encadrer le trajet au plus près
          int dynamicZoom = 17;
          if (maxDiff < 0.003) dynamicZoom = 18; // Quartier très précis
          else if (maxDiff < 0.008) dynamicZoom = 17; // Petit run (1-3km)
          else if (maxDiff < 0.020) dynamicZoom = 16; // Run classique (ex: 5-8km)
          else if (maxDiff < 0.045) dynamicZoom = 15; // Longue distance
          else if (maxDiff < 0.090) dynamicZoom = 14; // Semi-marathon
          else dynamicZoom = 13;

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
      } catch (_) {} // Si la route plante on l'ignore silencieusement

      // Création direct du JSON Echarts (Sans passer par DataviewJS, 100% garanti)
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
      buffer.writeln('---');
      buffer.writeln('id: $id');
      buffer.writeln('date: ${_formatDateLocal(activity.date)}');
      buffer.writeln('type: "[[strava]]"');
      buffer.writeln('sport: Run');
      buffer.writeln('distance_km: ${(activity.distance / 1000).toStringAsFixed(2)}');
      buffer.writeln('duration_s: ${activity.duration}');
      buffer.writeln('pause_s: ${activity.pauseDurationSeconds}');
      buffer.writeln('avg_speed_kmh: ${avgSpeedKmh.toStringAsFixed(2)}');
      buffer.writeln('avg_pace: "$avgPace"');
      if (activity.hasElevation) {
        buffer.writeln('elevation_gain_m: ${activity.elevationGainValue.round()}');
        buffer.writeln('elevation_loss_m: ${activity.elevationLossValue.round()}');
      }
      if (activity.name?.isNotEmpty == true) {
        buffer.writeln('name: "${activity.name}"');
      }
      buffer.writeln('---');
      buffer.writeln();

      // Titre avec un style HTML personnalisé (Néon)
      buffer.writeln('<h1 style="color: #F55CBD; border-bottom: 2px solid #00FFFF; padding-bottom: 10px; text-shadow: 0 0 10px rgba(245, 92, 189, 0.4); margin-bottom: 5px;">$safeTitle</h1>');
      buffer.writeln();
      buffer.writeln('> [!quote] 📋 **Rapport Technique**');
      buffer.writeln('> *Données télémétriques enregistrées via Wa\'a Strava.*');
      buffer.writeln();
      buffer.writeln('## 📊 Statistiques Globales');
      buffer.writeln();
      
      // Widget de statistiques en HTML / Flexbox pour un vrai style "Dashboard"
      buffer.writeln('<div style="display: flex; flex-wrap: wrap; gap: 10px; justify-content: space-around; background-color: #141419; padding: 20px; border-radius: 12px; border: 1px solid #F55CBD; box-shadow: 0 4px 15px rgba(245, 92, 189, 0.15); text-align: center; margin-bottom: 20px; font-family: sans-serif;">');
      buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">📏</span><br/><strong style="color: #00FFFF; font-size: 18px;">${(activity.distance / 1000).toStringAsFixed(2)} km</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Distance</span></div>');
      buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⏱️</span><br/><strong style="color: #00FFFF; font-size: 18px;">${activity.duration ~/ 60}m ${activity.duration % 60}s</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Mouvement</span></div>');
      buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⏸️</span><br/><strong style="color: #F8FF00; font-size: 18px;">${activity.pauseDurationSeconds ~/ 60}m ${activity.pauseDurationSeconds % 60}s</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Pause</span></div>');
      buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⚡</span><br/><strong style="color: #F55CBD; font-size: 18px;">${avgSpeedKmh.toStringAsFixed(2)} km/h</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Vitesse Moy.</span></div>');
      buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">🎯</span><br/><strong style="color: #F55CBD; font-size: 18px;">$avgPace /km</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Allure Moy.</span></div>');
      if (activity.hasElevation) {
        buffer.writeln('  <div style="flex: 1; min-width: 80px;"><span style="font-size: 24px;">⛰️</span><br/><strong style="color: #39FF14; font-size: 18px;">${activity.elevationGainValue.round()} m</strong><br/><span style="color: #AAAAAA; font-size: 12px;">Dénivelé +</span></div>');
      }
      buffer.writeln('</div>');
      buffer.writeln();
      
      if (leafletBlock.isNotEmpty) {
        buffer.writeln(leafletBlock);
      }

      if (activity.laps != null && activity.laps!.isNotEmpty) {
        buffer.writeln('## ⏱️ Analyse des Boucles');
        buffer.writeln();
        // Tableau HTML stylisé reprenant les couleurs néons
        buffer.writeln('<table style="width: 100%; text-align: center; border-collapse: collapse; margin-bottom: 20px; font-family: sans-serif;">');
        buffer.writeln('  <tr style="background-color: #141419; color: #00FFFF; border-bottom: 2px solid #F55CBD;">');
        buffer.writeln('    <th style="padding: 12px;">Boucle</th><th style="padding: 12px;">Distance (km)</th><th style="padding: 12px;">Temps</th><th style="padding: 12px;">Allure</th>');
        buffer.writeln('  </tr>');
        for (var lap in activity.laps!) {
          final lDuration = lap['duration'] as int;
          final lDist = ((lap['distance'] as num).toDouble() / 1000).toStringAsFixed(2);
          final lPaceSec = (lap['distance'] as num) > 0 ? (lDuration / ((lap['distance'] as num) / 1000)).round() : 0;
          final lPaceStr = '${(lPaceSec ~/ 60).toString().padLeft(2, '0')}:${(lPaceSec % 60).toString().padLeft(2, '0')}';
          buffer.writeln('  <tr style="border-bottom: 1px solid #333333;">');
          buffer.writeln('    <td style="padding: 10px; color: #AAAAAA;">#${lap['lapNumber']}</td><td style="padding: 10px; font-weight: bold;">$lDist</td><td style="padding: 10px;">${lDuration ~/ 60}m ${lDuration % 60}s</td><td style="padding: 10px; color: #F55CBD;">$lPaceStr /km</td>');
          buffer.writeln('  </tr>');
        }
        buffer.writeln('</table>');
        buffer.writeln();
        buffer.write(echartsBlock);
      }

      await file.writeAsString(buffer.toString());
      return file.path;
    } catch (e) {
      return null;
    }
  }
}
