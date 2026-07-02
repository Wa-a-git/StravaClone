import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:strava/models/activity.dart';
import 'package:strava/services/export_service.dart';

void main() {
  late Directory tmp;
  late String vaultRoot;
  late String exportDir;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('strava_export_');
    vaultRoot = tmp.path;
    Directory('$vaultRoot/.obsidian').createSync(); // marqueur de vault
    exportDir = '$vaultRoot/Strava';
    Directory(exportDir).createSync();

    Hive.init('${tmp.path}/hive');
    final box = await Hive.openBox('settings');
    await box.put('export_directory', exportDir);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Activity sampleRun() => Activity(
        date: DateTime(2026, 6, 13, 7, 25),
        distance: 2040, // m → 2.04 km
        duration: 1018,
        route: [
          [14.619, -61.100],
          [14.622, -61.098],
        ],
        name: 'Tour test',
        pauseDurationSeconds: 3,
      );

  test('écrit la fiche avec un frontmatter unifié (mycelium)', () async {
    final path = await ExportService.saveActivityAsMarkdown(sampleRun());
    expect(path, isNotNull);

    final content = File(path!).readAsStringSync();
    expect(content, contains('type: "[[strava]]"'));
    expect(content, contains('id: ${DateTime(2026, 6, 13, 7, 25).millisecondsSinceEpoch}'));
    expect(content, contains('date: 2026-06-13'));
    expect(content, contains('sport: Run'));
    expect(content, contains('distance_km: 2.04'));
    expect(content, contains('duration_s: 1018'));
    // le corps riche est préservé
    expect(content, contains('Statistiques Globales'));
    expect(content, contains('```leaflet'));
  });

  test('injecte un résumé dans la note du jour de la course', () async {
    await ExportService.saveActivityAsMarkdown(sampleRun());

    final daily = File('$vaultRoot/Notes/260613.md');
    expect(daily.existsSync(), isTrue);
    final content = daily.readAsStringSync();
    expect(content, contains('## Sport'));
    expect(content, contains('[[tour_test-2026-06-13_07h25]]')); // nom assaini
    expect(content, contains('2.04 km'));
  });

  test('ré-export = même fichier écrasé, pas de doublon', () async {
    await ExportService.saveActivityAsMarkdown(sampleRun());
    await ExportService.saveActivityAsMarkdown(sampleRun());

    final mdFiles = Directory(exportDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    expect(mdFiles.length, 1);
  });

  test('sans dossier .obsidian, pas d\'injection mais export OK', () async {
    // Nouveau layout sans marqueur de vault
    final flat = Directory.systemTemp.createTempSync('strava_flat_');
    final box = Hive.box('settings');
    await box.put('export_directory', flat.path);

    final path = await ExportService.saveActivityAsMarkdown(sampleRun());
    expect(path, isNotNull);
    expect(File(path!).existsSync(), isTrue);
    // aucune note du jour créée ailleurs
    expect(Directory('${flat.path}/Notes').existsSync(), isFalse);

    flat.deleteSync(recursive: true);
  });
}
