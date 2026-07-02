import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mycelium/mycelium.dart';

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
    // Windroid désactivé : ces tests couvrent le fallback local (et évitent
    // toute connexion réseau vers un vrai Windroid pendant les tests).
    await box.put('windroid_base_url', '');
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

  // Chemin "Windroid" : writeToVault sur une source quelconque (ici en mémoire)
  // → fiche dans Strava/ + résumé dans la note du jour, sans réseau.
  test('writeToVault écrit dans Strava/ et injecte la note du jour', () async {
    final source = _InMemoryVaultSource();
    final activity = sampleRun();
    final path = await ExportService.writeToVault(
      source,
      subdir: 'Strava',
      activity: activity,
      fileBase: 'tour_test-2026-06-13_07h25',
      id: activity.date.millisecondsSinceEpoch,
      fields: {'sport': 'Run', 'distance_km': '2.04'},
      body: '\n# Sortie\n',
      injectDaily: true,
    );

    expect(path, 'Strava/tour_test-2026-06-13_07h25.md');
    expect(source.files[path], contains('type: "[[strava]]"'));
    expect(source.files[path], contains('sport: Run'));

    final daily = source.files['Notes/260613.md'];
    expect(daily, isNotNull);
    expect(daily, contains('## Sport'));
    expect(daily, contains('[[tour_test-2026-06-13_07h25]]'));
  });
}

/// Source vault en mémoire pour tester writeToVault sans réseau ni disque.
class _InMemoryVaultSource implements VaultSource {
  final Map<String, String> files = {};

  @override
  int get readConcurrency => 4;
  @override
  Future<bool> available() async => true;
  @override
  Future<List<VaultEntry>> list() async =>
      files.keys.map((p) => VaultEntry(p, DateTime(2026, 7, 1))).toList();
  @override
  Future<String?> read(String path) async => files[path];
  @override
  Future<void> write(String path, String content) async => files[path] = content;
  @override
  Future<void> writeBytes(String path, List<int> bytes) async {}
  @override
  Future<void> delete(String path) async => files.remove(path);
  @override
  Future<bool> exists(String path) async => files.containsKey(path);
  @override
  Future<List<int>?> readAttachment(String name) async => null;
  @override
  Future<Map<String, String>?> readMany(List<String> paths) async =>
      {for (final p in paths) if (files[p] != null) p: files[p]!};
}
