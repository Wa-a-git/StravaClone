import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:arcade_health/models/activity.dart';
import 'package:arcade_health/services/export_service.dart';
import 'package:arcade_health/services/hive_service.dart';
import 'package:arcade_health/services/vault_import_service.dart';

void main() {
  late Directory tmp;
  late String vaultRoot;
  late String exportDir;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('strava_vault_import_');
    vaultRoot = tmp.path;
    Directory('$vaultRoot/.obsidian').createSync(); // marqueur de vault
    exportDir = '$vaultRoot/Sport/Exercice';
    Directory(exportDir).createSync(recursive: true);

    Hive.init('${tmp.path}/hive');
    if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ActivityAdapter());
    HiveService.setBoxForTesting(await Hive.openBox<Activity>('activities'));
    final settings = await Hive.openBox('settings');
    await settings.put('export_directory', exportDir);
    // Windroid désactivé : ces tests couvrent le fallback local (vault
    // Obsidian marqué .obsidian), sans réseau.
    await settings.put('windroid_base_url', '');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Activity sampleRun() => Activity(
        date: DateTime(2026, 7, 9, 7, 0),
        distance: 940,
        duration: 864,
        route: [
          [14.60407, -61.08405],
          [14.60409, -61.08412],
        ],
        name: 'retour Bellevue',
        pauseDurationSeconds: 220,
      );

  Activity sampleInterval() => Activity(
        date: DateTime(2026, 7, 8, 7, 0),
        distance: 3200,
        duration: 1500,
        route: const [],
        name: 'fractionné',
        workoutType: 'interval',
      );

  test('reconstruit une activité à partir de sa fiche exportée', () async {
    await ExportService.saveActivityAsMarkdown(sampleRun());
    expect(HiveService.getAllActivities(), isEmpty); // export seul, pas de save Hive

    final result = await VaultImportService.importActivities();

    expect(result.total, 1);
    expect(result.imported, 1);
    expect(result.skipped, 0);
    expect(result.failed, 0);

    final restored = HiveService.getAllActivities();
    expect(restored.length, 1);
    expect(restored.first.date, DateTime(2026, 7, 9, 7, 0));
    expect(restored.first.distance, 940);
    expect(restored.first.duration, 864);
    expect(restored.first.name, 'retour Bellevue');
    expect(restored.first.pauseDurationSeconds, 220);
    expect(restored.first.route, [
      [14.60407, -61.08405],
      [14.60409, -61.08412],
    ]);
  });

  test('reconstitue le workoutType (fractionné/zone d\'allure)', () async {
    await ExportService.saveActivityAsMarkdown(sampleInterval());

    final result = await VaultImportService.importActivities();
    expect(result.imported, 1);
    expect(HiveService.getAllActivities().first.workoutType, 'interval');
  });

  test('idempotent : ne réimporte pas une activité déjà présente', () async {
    await ExportService.saveActivityAsMarkdown(sampleRun());
    await VaultImportService.importActivities();
    expect(HiveService.getAllActivities().length, 1);

    final second = await VaultImportService.importActivities();
    expect(second.imported, 0);
    expect(second.skipped, 1);
    expect(HiveService.getAllActivities().length, 1); // pas de doublon
  });

  test('n\'écrase jamais une activité locale existante', () async {
    // Une activité déjà en Hive avec un nom différent, même horodatage.
    final local = sampleRun();
    local.name = 'nom local modifié à la main';
    await HiveService.saveActivity(local);

    await ExportService.saveActivityAsMarkdown(sampleRun());
    final result = await VaultImportService.importActivities();

    expect(result.skipped, 1);
    expect(result.imported, 0);
    expect(HiveService.getAllActivities().single.name, 'nom local modifié à la main');
  });

  test('aucune fiche dans le vault -> résultat vide, pas d\'erreur', () async {
    final result = await VaultImportService.importActivities();
    expect(result.total, 0);
    expect(result.imported, 0);
    expect(HiveService.getAllActivities(), isEmpty);
  });
}
