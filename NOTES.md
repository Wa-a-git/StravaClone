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
  extraite) → section **7 JOURS** (`_MetricsGrid`, ex-"Court terme") →
  **RECOMMANDATIONS** (`_InsightsPanel`, affiché seulement si des insights
  existent) → **SUPERPOSITION · 30 JOURS** (`_SuperpositionCard`,
  2 sélecteurs de métrique, défaut Sommeil × Récupération, rendu par
  `OverlayTrendChart` dans `lib/widgets/health_charts.dart` — chaque courbe
  normalisée 0-1 indépendamment, pas de double axe chiffré) → **MOYEN TERME ·
  30 JOURS** (3 `TrendChart` : sommeil/récupération/activité) → **LONG TERME ·
  90 JOURS** (`_LongTermPanel`, poids, masqué si aucune donnée). La carte
  Sommeil (`_SubScoreCard`) route maintenant vers `SleepDetailScreen` (plus
  `ScoreBreakdownScreen`) — cet écran existait déjà mais n'était jamais appelé.
- **Santé / "7 jours" regroupé + priorisé** (`_MetricsGrid` dans
  `health_dashboard_screen.dart`, implémentation réelle de la maquette
  validée en HTML plus tôt dans la session — visuel adapté au système de
  cadran `_HPanel`/`AppPanel` déjà en place plutôt qu'aux coins coupés façon
  hardware de la maquette, pour rester cohérent avec le reste de l'app
  restructurée sur `main` le 10 juillet) :
  - 4 groupes (`_MetricGroupId`) au lieu d'une grille en vrac : **Activité
    générale** (pas, distance, cal. actives, étages), **Vitaux & sommeil**
    (FC repos, respiration, SpO2 nocturne, durée de sommeil), **Récupération
    avancée** (HRV, VFC normalisée, sommeil profond, dette de sommeil, +
    `_ReadinessCard`), **Corps** (VO2 max + `_WeightMetricCard`). Chaque
    groupe garde ses cartes `_MetricCard` existantes (sparkline 7j + flèche
    de tendance déjà réelles, rien réinventé).
  - **VFC normalisée** (`HealthMetric.hrvZScore`), **sommeil profond**
    (`deepSleepRatio`) et **dette de sommeil** (`sleepDebtHours`) : calculés
    à chaque synchro (`health_connect_service.dart`, commit du 10 juillet)
    mais n'avaient jamais de carte sur ce dashboard — seulement atteignables
    via leur écran de détail si on savait qu'ils existaient. Exposés ici
    pour la première fois. Ces 3 champs vivent sur `DailyHealthRecord`, pas
    sur `HealthSnapshot` (besoin d'historique) — `_allMetricSpecs` lit
    `HealthStore.recordFor(DateTime.now())` séparément pour ça.
  - **Poids : vraie saisie manuelle depuis Santé** (`_WeightMetricCard` +
    `_WeighInSheet`) — jusqu'ici la seule façon de saisir le poids était
    Profil (`BodyProfileCard._edit`) ; la carte Poids du dashboard Santé
    était juste masquée s'il n'y avait aucune valeur. Le tap ouvre une
    feuille rapide (champ + pas ±0,1/±0,5) qui écrit via
    `HealthStore.setManualWeightToday` — même fonction que Profil, une
    seule source de vérité, les deux écrans restent synchronisés.
  - **Score de Préparation "maison"** (`_ReadinessCard`) : composite
    `recoveryScore*0.6 + sleepScore*0.4`, badge "MAISON" + note explicite
    que ce n'est ni le score EDA Fitbit (scan manuel au réveil) ni un
    statut basé sur la température cutanée — aucun des deux n'est exposé
    via Health Connect, vérifié dans `health_connect_service.dart`,
    irréalisable ici quel que soit l'effort de code.
  - **Dashboard qui priorise** (`_ObservationCard` + tri de `_groupDefs`
    dans `_MetricsGridState.build`) : le groupe dont le sous-score
    représentatif (`activityScore`/`sleepScore`/`recoveryScore`) dévie le
    plus défavorablement de sa baseline 7j (`HealthScoreService.trend`)
    remonte en tête de "7 jours" avec un badge SIGNALÉ, et un callout
    au-dessus nomme la tendance en langage clair — seulement affiché quand
    un signal dévie vraiment (même philosophie que `dayHighlight()` dans
    `feed_screen.dart`), jamais un ordre figé. Le groupe Corps (pas de
    sous-score) reste toujours en dernier.
  - Volontairement pas fait : le style visuel "coins coupés façon hardware
    + jauges à crans" de la maquette HTML n'a pas été repris tel quel —
    l'app a son propre système de cadran (`AppPanel`/`_HPanel`) déjà
    cohérent sur tous les écrans, et lui superposer une seconde esthétique
    juste pour Santé aurait cassé cette cohérence. Le contenu/l'architecture
    de la maquette est repris fidèlement, pas son chrome visuel exact.
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
  / **Sport** (kcal, dernière course, série), compteur "fait/total" dans la
  barre du haut, et **les quêtes du jour + de la semaine** (réclamation →
  XP → note vault) directement dans la carte, sous les indicateurs — décision
  produit : les quêtes vivent avec le personnage, pas dans une carte à part.
  `main` avait ajouté indépendamment une `_QuestsCard` séparée juste en
  dessous du HUD (même fonctionnalité de réclamation, ajoutée par ailleurs
  le 10 juillet) : au moment du merge de cette branche, ça affichait les
  quêtes deux fois. Résolu en fusionnant `_QuestsCard` dans `_ArcadeHudCard`
  (fonction `_claimQuest` au niveau du fichier, réutilisée par les deux
  listes jour/semaine ; `_QuestsList`/`_HealthQuestTile`/`_WeeklyQuestBars`
  réutilisés tels quels) et en supprimant la carte séparée — c'est bien la
  carte avec le sprite qui doit porter les quêtes.
  Tout branché sur des données réelles déjà calculées ailleurs
  (`healthDataProvider`, `playerProfileProvider`, `HealthQuestService`) — la
  pastille **Méditation** est la seule exception : pas de source de données
  (ni Health Connect, ni flux de log), affichée en attente (`--`) jusqu'à
  décision.
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

## Session du 19/07 — édition/suppression muscu, inclinaison tapis, indicateurs

**Contexte d'environnement, important pour la suite** : contrairement à ce que
disent les sections ci-dessus, cette session dispose d'un vrai toolchain
Flutter (`flutter analyze`, `dart run build_runner build`, `flutter test`
tournent tous) **et** le package `mycelium` est bien présent sur le disque
(`D:\mycelium`, en dehors de ce repo). Tout ce qui suit a été vérifié par
`flutter analyze` (aucune erreur/warning nouveau) et `flutter test` (tous
les tests passent, y compris 6 nouveaux — seul `test/widget_test.dart`
échoue, boilerplate `flutter create` jamais adapté à cette app, déjà cassé
avant cette session, hors périmètre).

- **Édition d'une série/bloc déjà enregistré** — jusqu'ici seule la
  suppression existait (`musculation_session_detail_screen.dart`). Nouveau
  `lib/screens/edit_musculation_set_sheet.dart`
  (`showEditMusculationSetSheet`) : feuille modale avec les mêmes contrôles
  que la saisie en direct (reps/charge/côté, ou durée/distance/fractionné
  pour le cardio, + repos), renvoie l'entrée corrigée via
  `MusculationLogEntry.copyWith` (nouveau, gère le côté L/R nullable avec
  une sentinelle pour distinguer "non passé" de "explicitement effacé").
  Persistée via `MusculationStore.updateEntry` (nouveau, écrase la même clé
  Hive contrairement à `addEntry`). Branchée à deux endroits : le détail
  d'une séance passée (tap sur une ligne, la croix reste pour supprimer) et
  la séance en direct (tap sur un bloc déjà loggé dans "BLOCS DE CETTE
  SÉANCE") — mêmes contrôles réutilisés aux deux endroits.
  - Extraction : les widgets de saisie (steppers reps/charge/durée/distance,
    chip sélectionnable, toggle gauche/droite) vivaient en privé dans
    `live_musculation_screen.dart` ; déplacés tels quels (juste rendus
    publics) dans `lib/widgets/musculation_set_fields.dart` pour être
    partagés avec la feuille d'édition, sans dupliquer ~180 lignes.
- **Suppression d'une séance entière depuis son écran détail** — existait
  déjà depuis la liste Historique (`musculation_history_screen.dart`,
  `_confirmDelete`) mais pas depuis `musculation_session_detail_screen.dart`
  lui-même. Icône corbeille ajoutée dans l'AppBar (même feuille de
  confirmation que l'historique, dupliquée à l'identique plutôt que
  factorisée — deux call sites, pas de troisième prévu), `Navigator.pop`
  après suppression puisque la séance affichée n'existe plus.
- **Inclinaison du tapis** — nouveau champ `Activity.inclinePercent`
  (`double?`, `HiveField(11)`, adaptateur régénéré via build_runner plutôt
  qu'à la main). Saisie dans `manual_cardio_entry_screen.dart` (panneau
  "INCLINAISON (OPTIONNELLE)", visible seulement pour le type Tapis —
  n'a pas de sens pour Course/Autre). Affichée dans `detail_screen.dart`
  (carte stat, si renseignée). Aller-retour export/import vault complet
  (`incline_pct` en frontmatter + carte dans le corps de la fiche côté
  `export_service.dart`, parsing côté `vault_import_service.dart`) — testé
  dans `test/export_service_test.dart` et `test/vault_import_service_test.dart`.
- **Indicateurs Musculation** — l'onglet menait direct à la bibliothèque
  d'exercices, aucun chiffre. Nouvelle carte `_IndicatorsCard` dans
  `musculation_screen.dart`, juste sous "DÉMARRER UNE SÉANCE" (donc avant
  la bibliothèque, qui reste plus bas, inchangée) : volume soulevé
  (aujourd'hui / 7 jours / 3 mois, lecture directe de `MusculationStore.all()`,
  pas de nouveau système de stats) + nombre de séances (7 jours / 3 mois,
  déduit des `sessionId` distincts). Fenêtres glissantes (7j/90j), pas
  calendaires — cohérent avec le reste de l'app (santé utilise déjà des
  fenêtres glissantes 7/30/90 jours). Masquée tant qu'aucune série n'a
  jamais été loggée.

### Tests ajoutés cette session

- `test/musculation_log_test.dart` (nouveau) : `copyWith`, en particulier
  la sentinelle pour le côté L/R nullable.
- `test/export_service_test.dart` / `test/vault_import_service_test.dart` :
  2 tests chacun pour l'inclinaison (présente → round-trip fidèle ; absente
  → pas de champ, pas d'erreur).

### Points ouverts (nouveaux)

- Pas de suppression individuelle d'un bloc *pendant* la séance en direct
  (seulement modification) — seul le flux "Annuler cette série" existe,
  et seulement avant confirmation. Pas demandé cette session, mais logique
  si quelqu'un veut retirer un bloc entier sans attendre la fin de séance.
- L'inclinaison n'est saisissable qu'à la création d'une activité tapis —
  pas de correction a posteriori depuis l'historique/détail course (contrairement
  aux séries muscu). Pas demandé, mais même angle mort que ci-dessus.
- Widget test manuel sur device non fait au moment d'écrire ce qui précède —
  correction : le téléphone a fini par être branché plus tard dans la même
  session, build installé via `adb install -r` (pas de perte de données,
  `firstInstallTime` inchangé). Voir session suivante ci-dessous pour la
  suite (refonte Santé), qui réutilise ce même flux d'install à chaque fois.

## Session du 19/07 (suite, même jour) — refonte Santé, cadran Méditation, score d'activité

Portée confirmée explicitement par l'utilisateur : "Tout le programme" (pas
un sous-ensemble). Contexte retrouvé via `search_session_transcripts` /
`list_events` : une session parallèle ("Écran Santé et widgets graphiques",
id `local_d2f5cef7`) avait déjà posé le hero (`_TodayCard`) avec anneau
Bio-Score + carrousel de pilules + radar "Équilibre du jour" + grille "7
JOURS" allégée, et la section Méditation (chrono/historique/FC, chip Feed) —
tout ça était déjà sur `main`, pas à refaire. Cette session a construit
au-dessus de cette base réelle (vérifiée en lisant le fichier, pas déduite
de ce NOTES.md qui était lui-même en retard de plusieurs commits).

- **Marqueurs d'exercice sur la courbe FC de séance** — `TrendChart` (
  `lib/widgets/health_charts.dart`) accepte maintenant `markers:
  List<ChartMarker>` (repère vertical + étiquette pivotée, position
  interpolée entre les deux échantillons de `dates` qui encadrent l'heure du
  repère — même échelle par index que la courbe). Branché dans
  `musculation_session_detail_screen.dart` (`_exerciseMarkers()`) : un
  repère à chaque changement d'exercice, sur la courbe FC de toute la
  séance, pour savoir "à quel exercice on est" sans recouper mentalement
  avec la liste des blocs plus bas.
- **Hero Santé réellement swipeable** — `_HeroPillCarousel` passe d'un
  `Column` + tap-sur-les-points à un vrai `PageView` (swipe au doigt, les
  points restent cliquables pour sauter à une page). 3ᵉ page ajoutée :
  Distance / Poids / VO2 max — Poids ouvre la feuille de saisie rapide
  (`_WeighInSheet`, comme avant) plutôt que l'écran de détail générique (pas
  d'historique montre à montrer, poids = saisie manuelle).
- **Groupes retirés de "7 JOURS"** — Activité générale, Vitaux & sommeil,
  Corps supprimés (`_MetricGroupId` réduit à `recovery` seul) : leurs
  métriques (Pas, FC repos, Sommeil, Distance, Respiration, Poids, VO2 max)
  vivent maintenant toutes dans le carrousel héros ci-dessus, les garder
  ici aurait fait doublon. Seule "Récupération avancée" reste (VFC
  normalisée, sommeil profond, dette sommeil, Score de Préparation).
  `_WeightMetricCard` (classe entière) supprimée : plus aucun appelant
  après le déplacement de Poids vers le hero.
- **Score d'activité corrigé pour compter les séances muscu** —
  `HealthScoreService.activityScore` ne pesait que pas/calories
  actives/étages (données montre Health Connect), 0% pour une séance muscu
  loggée dans l'app — explique pourquoi une vraie journée de sport pouvait
  quand même afficher un score bas (calories/étages en particulier
  peu fiables sur la Fitbit Charge 6 de l'utilisateur). Nouveau paramètre
  optionnel `musculationMinutes` (poids 30% de la formule, plein crédit à
  `HealthScoreTuning.musculationGoalMinutes` = 45 min), branché dans
  `health_connect_service.dart` `syncDay(day)` via
  `MusculationSessionStore.forDay(day)`. Testé dans
  `test/health_score_service_test.dart`.
- **Cadran Méditation dans le hero** — `_MeditationCard` (nouveau) : anneau
  minutes du jour vs objectif (10 min, constante locale), toggle
  Semaine/Mois (`SegmentedTabs`) pour le total de la période, série de jours
  consécutifs, tap → `MeditationScreen` (écran déjà existant, juste jamais
  raccroché au dashboard Santé jusqu'ici).
- **"Équilibre du jour" en 3 formes au choix** — nouveau `BarChart`
  (`health_charts.dart`, réutilise le modèle `RadarAxis` du radar existant)
  + réutilisation de `SegmentedRing` (déjà là, pour les stades de sommeil)
  comme vue "circulaire". `_BalanceRadar` devient stateful avec 3 boutons
  (radar/barres/donut) pour basculer. **3D explicitement pas fait** — hors
  de portée raisonnable pour une CustomPaint 2D sans dépendance externe ;
  arbitrage pas encore validé avec l'utilisateur, à voir si les 3 formes
  actuelles suffisent.

### Tests ajoutés cette session (suite)

- `test/health_score_service_test.dart` (nouveau) : la part musculation de
  `activityScore` (0 sans séance, plafonnée à 30% même au-delà de
  l'objectif, s'additionne avec la part pas plutôt que de l'exclure).

### Points ouverts (nouveaux, suite)

- 3D pour "Équilibre du jour" pas implémenté (voir ci-dessus) — décision à
  valider avec l'utilisateur plutôt que supposée.
- `musculationGoalMinutes` (45 min) et l'objectif méditation (10 min/jour)
  sont des constantes choisies arbitrairement, jamais confirmées par
  l'utilisateur — probable point de calibrage à revoir une fois utilisées
  en vrai quelques jours.
- Vu et testé sur le téléphone cette fois (`adb install -r`, lancement sans
  crash confirmé via logcat filtré sur le PID de l'app) mais pas navigué
  écran par écran manuellement par Claude — l'utilisateur a dit vouloir
  vérifier lui-même à ce stade de la session.
