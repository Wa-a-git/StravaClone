# Notes de session — refonte Feed / Santé / Sport + thème arcade

Contexte pour reprendre le travail dans une session ultérieure. Développé sur
la branche `claude/vo2-max-data-display-43e3ee`.

## État actuel — tout ce qui suit est codé et poussé sur la branche

- **VO2 max** : détail des données du calcul (courses/points utilisés, plage
  FC/allure), catégorie fitness (Faible → Élite) par âge/sexe, champ sexe
  optionnel dans le profil. `lib/services/vo2_estimator_service.dart`
  (`categoryFor`), `lib/screens/health_metric_detail_screen.dart`.
- **Thème rétro-arcade** : palette dans `lib/theme.dart` (fond violet-noir,
  accents rose électrique / jaune doré / cyan / violet néon). Se propage
  partout via `AppColors`/`kNeon*`. Police pixel `Press Start 2P` disponible
  (`kArcadePixelFont`) mais **volontairement pas branchée** sur `kArcadeFont`
  (risque de débordement, voir "Points ouverts").
- **Onglets** : `Feed / Santé / Sport / Profil` (`shell_screen.dart`,
  `shellIndexProvider` : 0=Feed, 1=Santé, 2=Sport, 3=Profil). "Niveau" est
  maintenant le 3ᵉ sous-onglet de Sport (`sport_screen.dart`, `SportTab` :
  `course / musculation / progression`), plus d'onglet dédié en bas.
  `system_screen.dart` exporte `ProgressionSection` (plus de `Scaffold`
  propre, inséré comme `CourseSection`/`MusculationSection`).
- **Feed** (`lib/screens/feed_screen.dart`, nouvel écran) : calendrier
  minimaliste en haut (`_FeedCalendar`, pastilles rose=activité/violet=santé,
  surbrillance cyan aujourd'hui) + fil chronologique de posts (courses,
  résumés santé du jour), du plus récent au plus ancien. Ancien code déplacé
  depuis `health_dashboard_screen.dart` (`_HistoryEntry`, `_buildHistoryEntries`,
  `_DayFeedContent`, `_FeedPost`, `_ActivityFeedCard`) — ces classes n'existent
  plus dans `health_dashboard_screen.dart`.
- **Santé** (`health_dashboard_screen.dart`) : le feed/historique est parti
  dans son propre onglet. Structure actuelle : hero `_TodayCard` (Bio-Score +
  quêtes jour/semaine + sous-scores + XP, **sans** la grille de métriques,
  extraite) → section **COURT TERME** (`_MetricsGrid`, ex-"Métriques &
  tendances") → **RECOMMANDATIONS** (`_InsightsPanel`, affiché seulement si
  des insights existent) → **SUPERPOSITION · 30 JOURS** (`_SuperpositionCard`,
  2 sélecteurs de métrique, défaut Sommeil × Récupération, rendu par
  `OverlayTrendChart` dans `lib/widgets/health_charts.dart` — chaque courbe
  normalisée 0-1 indépendamment, pas de double axe chiffré) → **MOYEN TERME ·
  30 JOURS** (3 `TrendChart` : sommeil/récupération/activité) → **LONG TERME ·
  90 JOURS** (`_LongTermPanel`, poids, masqué si aucune donnée). La carte
  Sommeil (`_SubScoreCard`) route maintenant vers `SleepDetailScreen` (plus
  `ScoreBreakdownScreen`) — cet écran existait déjà mais n'était jamais appelé.
- **Sport / Course** : nouvelle carte **Records personnels**
  (`_PersonalRecordsCard` dans `home_screen.dart`) — distance/allure/D+ les
  plus performants tous temps confondus (même logique que la célébration en
  fin de course dans `tracking_screen.dart`, mais affichée en continu).
- **Sport / Musculation** : champ **charge (kg)** optionnel dans le flux de
  log rapide (`_ChargeStepperRow`, incréments de 2,5 kg), stocké dans
  `MusculationLogEntry.chargeKg` (défaut 0, rétro-compatible). `volumeKg`
  getter (séries × reps × charge). Export vault mis à jour (colonne Charge,
  volume total dans le frontmatter `total_volume_kg` et la ligne de note du
  jour).
- **Sport / Progression — fusion stat Force** : `GameService.statsFor`/
  `profileFor` acceptent `musculationVolumeKg` ; `force = dénivelé/10 +
  volumeMuscu/100` (arrondi). `playerProfileProvider` lit
  `MusculationStore.all()` et recalcule à chaque changement — un
  `musculationRevisionProvider` (StateProvider<int>, bumpé après chaque
  ajout/suppression d'exercice dans `musculation_screen.dart`) force le
  recalcul puisque `MusculationStore` (Hive) n'a pas de flux réactif propre.
- **Bouton +** : inchangé, toujours dans `shell_screen.dart`.
- **Feed — HUD d'arcade** (`_ArcadeHudCard` dans `feed_screen.dart`, en tête
  du Feed, au-dessus du calendrier) : sprite placeholder (carré rose) qui
  rebondit en continu via `AnimationController` — même mécanique
  d'animation prévue pour le vrai personnage plus tard, juste l'image à
  remplacer. Score (XP du jour, ticking), niveau, jauges Bio-Score/Pas,
  indicateurs du jour groupés **Santé** (sommeil, méditation, FC repos, HRV)
  / **Sport** (kcal, dernière course, série), et un compteur "fait/total"
  dans la barre du haut. Tout branché sur des données réelles déjà calculées
  ailleurs (`healthDataProvider`, `playerProfileProvider`,
  `HealthQuestService`) — la pastille **Méditation** est la seule exception :
  pas de source de données (ni Health Connect, ni flux de log), affichée en
  attente (`--`) jusqu'à décision. La liste détaillée des quêtes (jour +
  semaine, réclamation → XP) a été fusionnée avec `_QuestsCard`, ajoutée en
  parallèle sur `main` juste en dessous de ce HUD dans le Feed : la carte
  gardait initialement sa propre liste de quêtes en lecture seule, retirée
  pour ne pas doubler `_QuestsCard`.
- **Écran Sommeil** (`sleep_detail_screen.dart`) restructuré autour de la
  distinction "cette nuit" vs "les nuits en général" : hero/hypnogramme/
  répartition des stades inchangés, **carte Physio de cette nuit** ajoutée
  (FC moyenne, SpO2, respiration, ratio sommeil réparateur = (profond+REM)/
  total, chacune avec un badge delta vs les 7 nuits précédentes — recalculé
  dynamiquement selon la nuit consultée, pas juste "aujourd'hui"), et une
  **carte recommandation** basée sur cette nuit précise (`_nightInsight`,
  quelques règles simples : nuit courte, FC nocturne élevée, beaucoup de
  réveils, ou bonne récupération). L'ancienne carte "Tendance 14 jours" est
  **retirée** et remplacée par un lien "Tendances & croisements" qui bascule
  vers l'onglet Santé (`shellIndexProvider` = 1) — les tendances multi-nuits
  vivent là-bas (score de sommeil 30j déjà présent, superposition HRV ×
  sommeil déjà possible via `_SuperpositionCard`).

## Tests

- `test/vo2_estimator_service_test.dart`, `test/export_service_test.dart`
  (musculation : frontmatter, note du jour, ré-export, charge/volume),
  `test/game_service_test.dart` (fusion Force). **Aucun n'a été exécuté** —
  pas de toolchain Flutter/Dart dans cet environnement. À lancer en priorité
  à la reprise (`flutter test`).

## Points ouverts

- **Press Start 2P pas branchée à l'app réelle.** 94 usages de `kArcadeFont`
  sur ~20 écrans, police bien plus large qu'Orbitron. À appliquer écran par
  écran, uniquement sur du texte court, en vérifiant l'affichage réel à
  chaque fois (impossible à vérifier depuis cet environnement).
- **Écrans avec palette codée en dur, indépendante de `theme.dart`** :
  `tracking_screen.dart`, `history_screen.dart`, `detail_screen.dart`,
  `widgets/system_window.dart`, `widgets/record_celebration.dart` — hors
  périmètre de cette session, à migrer si on veut une cohérence totale.
- **Rien de tout ce travail n'a été compilé, testé ou vu à l'écran** — pas de
  toolchain Flutter dans cet environnement, pas d'accès au téléphone. Relu
  attentivement fichier par fichier (imports, symboles, types) mais un
  `flutter analyze` + `flutter test` + test manuel sur device restent à faire
  avant de considérer que c'est du solide.
- Le package `mycelium` (export vault) reste une dépendance locale
  (`../../mycelium`) absente de ce repo — `flutter pub get` échouerait ici,
  jamais testable dans cet environnement.
