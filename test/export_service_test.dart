import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mycelium/mycelium.dart';

import 'package:arcade_health/data/exercise_library.dart';
import 'package:arcade_health/models/activity.dart';
import 'package:arcade_health/models/musculation_log.dart';
import 'package:arcade_health/models/musculation_session.dart';
import 'package:arcade_health/services/export_service.dart';

void main() {
  late Directory tmp;
  late String vaultRoot;
  late String exportDir;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('strava_export_');
    vaultRoot = tmp.path;
    Directory('$vaultRoot/.obsidian').createSync(); // marqueur de vault
    exportDir = '$vaultRoot/Sport/Exercice';
    Directory(exportDir).createSync(recursive: true);

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
    expect(content, contains('type: "[[exercice]]"'));
    expect(content, contains('id: ${DateTime(2026, 6, 13, 7, 25).millisecondsSinceEpoch}'));
    expect(content, contains('date: 2026-06-13'));
    expect(content, contains('sport: Run'));
    expect(content, contains('distance_km: 2.04'));
    expect(content, contains('duration_s: 1018'));
    // trace GPS compacte (aperçu du tracé côté Marble/Overview)
    expect(content, contains('route: "14.61900,-61.10000;14.62200,-61.09800"'));
    // trace complète, sans échantillonnage — pour restaurer l'activité à
    // l'identique si la base locale est perdue (pas juste un aperçu).
    expect(content, contains('route_full_json'));
    expect(content, contains('[[14.619,-61.1],[14.622,-61.098]]'));
    // le corps riche est préservé
    expect(content, contains('Statistiques Globales'));
    expect(content, contains('```leaflet'));
  });

  test('inclut laps/élévations/secondes par point en JSON quand présents',
      () async {
    final withDetail = Activity(
      date: DateTime(2026, 6, 13, 7, 25),
      distance: 2040,
      duration: 1018,
      route: [
        [14.619, -61.100],
        [14.622, -61.098],
      ],
      name: 'Tour test',
      laps: [
        {'lapNumber': 1, 'duration': 500, 'distance': 1000.0},
        {'lapNumber': 2, 'duration': 518, 'distance': 1040.0},
      ],
      elevations: [12.0, 13.5, 11.0],
      pointSeconds: [0, 30, 60],
    );

    final path = await ExportService.saveActivityAsMarkdown(withDetail);
    final content = File(path!).readAsStringSync();

    expect(content, contains('laps_json'));
    expect(content, contains(r'\"lapNumber\":1'));
    expect(content, contains(r'\"duration\":518'));
    expect(content, contains('elevations_json'));
    expect(content, contains('[12.0,13.5,11.0]'));
    expect(content, contains('point_seconds_json'));
    expect(content, contains('[0,30,60]'));
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
  // → fiche dans Sport/Exercice/ + résumé dans la note du jour, sans réseau.
  test('writeToVault écrit dans Sport/Exercice/ et injecte la note du jour', () async {
    final source = _InMemoryVaultSource();
    final activity = sampleRun();
    final path = await ExportService.writeToVault(
      source,
      subdir: 'Sport/Exercice',
      fileBase: 'tour_test-2026-06-13_07h25',
      id: activity.date.millisecondsSinceEpoch,
      date: activity.date,
      myceliumClass: 'exercice',
      fields: {'sport': 'Run', 'distance_km': '2.04'},
      body: '\n# Sortie\n',
      dailySection: 'Sport',
      dailyLine: '- 🏃 [[tour_test-2026-06-13_07h25]] — 2.04 km',
    );

    expect(path, 'Sport/Exercice/tour_test-2026-06-13_07h25.md');
    expect(source.files[path], contains('type: "[[exercice]]"'));
    expect(source.files[path], contains('sport: Run'));

    final daily = source.files['Notes/260613.md'];
    expect(daily, isNotNull);
    expect(daily, contains('## Sport'));
    expect(daily, contains('[[tour_test-2026-06-13_07h25]]'));
  });

  // Musculation n'avait jusqu'ici aucun export — rien ne remontait dans le
  // vault ni dans la note du jour. Mêmes garanties que pour une course :
  // fiche par SÉANCE (ré-écrite au même id, pas dupliquée) + résumé injecté
  // sous ## Sport. Chaque bloc = 1 set (comme produit par
  // live_musculation_screen.dart — sets vaut toujours 1 depuis le passage à
  // la séance en direct, plus jamais "4 séries" en une seule entrée).
  group('musculation', () {
    final day = DateTime(2026, 6, 13, 18, 0);
    MusculationSession sampleSession() =>
        MusculationSession(date: day, endDate: day.add(const Duration(hours: 1)));
    List<MusculationLogEntry> pushSession() => [
          MusculationLogEntry(
              date: day,
              exerciseId: 'bench',
              exerciseName: 'Développé couché',
              category: ExerciseCategory.barbell,
              sets: 1,
              reps: 8,
              chargeKg: 60),
          MusculationLogEntry(
              date: day.add(const Duration(minutes: 3)),
              exerciseId: 'ohp',
              exerciseName: 'Développé militaire',
              category: ExerciseCategory.dumbbell,
              sets: 1,
              reps: 10),
        ];

    test('écrit la fiche avec un frontmatter unifié (mycelium)', () async {
      final path = await ExportService.saveMusculationSessionAsMarkdown(
          sampleSession(), pushSession());
      expect(path, isNotNull);

      final content = File(path!).readAsStringSync();
      expect(content, contains('type: "[[musculation]]"'));
      expect(content, contains('id: ${day.millisecondsSinceEpoch}'));
      expect(content, contains('exercises: 2'));
      expect(content, contains('blocks: 2'));
      expect(content, contains('Développé couché'));
      expect(content, contains('Développé militaire'));
      expect(content, contains('8 reps'));
      expect(content, contains('10 reps'));
    });

    test('inclut la charge et le volume quand renseignés', () async {
      final entries = [
        MusculationLogEntry(
            date: day,
            exerciseId: 'bench',
            exerciseName: 'Développé couché',
            category: ExerciseCategory.barbell,
            sets: 1,
            reps: 8,
            chargeKg: 60),
      ];
      final path = await ExportService.saveMusculationSessionAsMarkdown(
          sampleSession(), entries);
      final content = File(path!).readAsStringSync();
      expect(content, contains('total_volume_kg: 480.0'));
      expect(content, contains('60.0 kg'));

      final daily = File('$vaultRoot/Notes/260613.md').readAsStringSync();
      expect(daily, contains('480 kg soulevés'));
    });

    test('injecte un résumé dans la note du jour', () async {
      await ExportService.saveMusculationSessionAsMarkdown(
          sampleSession(), pushSession());

      final daily = File('$vaultRoot/Notes/260613.md');
      expect(daily.existsSync(), isTrue);
      final content = daily.readAsStringSync();
      expect(content, contains('## Sport'));
      expect(content, contains('[[seance-2026-06-13_18h00]]'));
      expect(content, contains('2 exercices'));
      expect(content, contains('2 blocs'));
    });

    test('ré-export de la même séance = même fichier écrasé, pas de doublon',
        () async {
      final session = sampleSession();
      await ExportService.saveMusculationSessionAsMarkdown(
          session, pushSession());
      // Un bloc de plus, réexporté (comme après chaque série dans l'app).
      final updated = [
        ...pushSession(),
        MusculationLogEntry(
            date: day.add(const Duration(minutes: 6)),
            exerciseId: 'dips',
            exerciseName: 'Dips lestés',
            category: ExerciseCategory.bodyweight,
            sets: 1,
            reps: 12),
      ];
      await ExportService.saveMusculationSessionAsMarkdown(session, updated);

      final mdFiles = Directory('$vaultRoot/Sport/Musculation')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.md'))
          .toList();
      expect(mdFiles.length, 1);
      expect(mdFiles.first.readAsStringSync(), contains('Dips lestés'));
    });

    test('liste vide -> rien écrit (pas de fiche "0 exercice")', () async {
      final path = await ExportService.saveMusculationSessionAsMarkdown(
          sampleSession(), []);
      expect(path, isNull);
    });
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
