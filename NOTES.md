# Notes de session — refonte Feed / Santé / Sport + thème arcade

Contexte pour reprendre le travail dans une session ultérieure. Discussion menée
sur la branche `claude/vo2-max-data-display-43e3ee`.

## État actuel

### Fait et poussé sur la branche
- **VO2 max** : détail des données du calcul (courses/points utilisés, plage
  FC/allure), catégorie fitness (Faible → Élite) par âge/sexe, champ sexe
  optionnel dans le profil. Voir `lib/services/vo2_estimator_service.dart`
  (`categoryFor`) et `lib/screens/health_metric_detail_screen.dart`.
- **Thème rétro-arcade** : nouvelle palette (fond violet-noir, accents rose
  électrique / jaune doré / cyan / violet néon saturés) dans `lib/theme.dart`.
  Se propage automatiquement partout puisque l'app référence déjà
  `AppColors`/`kNeon*` plutôt que des couleurs codées en dur.
- Police **Press Start 2P** ajoutée aux assets (`assets/fonts/`, déclarée dans
  `pubspec.yaml`) sous la constante `kArcadePixelFont` — **disponible mais pas
  branchée** sur `kArcadeFont` (voir "À faire" ci-dessous).

### Pas encore implémenté (validé sur maquette seulement)
La restructuration Feed / Santé / Sport / Profil discutée n'est **pas** codée
dans l'app — seulement prototypée en HTML. Deux maquettes cliquables existent
(visibles depuis un compte claude.ai avec accès à cette session) :
- Version thème actuel (sombre, validée) :
  `https://claude.ai/code/artifact/8e620a0c-de77-4938-9e4b-573b5b888387`
- Version thème arcade (validée, celle dont la palette a été appliquée) :
  `https://claude.ai/code/artifact/ec538ba7-78c1-4da5-8932-6b8aaa192326`

Décisions validées à reprendre lors de l'implémentation réelle :

1. **Onglets** : `Feed / Santé / Sport / Profil` (4 au lieu de 5) — "Niveau"
   devient un 3ᵉ sous-onglet de Sport (`Course / Musculation / Progression`),
   plus d'onglet dédié en bas.
2. **Feed** (`shell_screen.dart` → nouvel onglet) :
   - Calendrier minimaliste en haut (façon plugin Calendar d'Obsidian —
     grille compacte, pastilles colorées par type d'événement).
   - Fil chronologique de posts (courses, séances muscu, résumés santé du
     jour précédent) — **jamais le jour courant** (il vit dans le hero de
     Santé tant qu'il n'est pas terminé).
   - Pas de label "Historique" : effet fil d'activité (bouton kudos/flamme
     toggle par post, aperçu de trace stylisé pour les courses).
   - Chaque post porte un repère visuel vers une note liée (icône + chemin,
     ex. `Journal/2026-07-08.md`) — **rien de branché**, voir "Marble"
     ci-dessous.
3. **Santé** : hero Bio-Score conservé en tête (avec les chiffres bruts du
   jour). Reste de l'écran regroupé en 3 blocs : court terme (aujourd'hui/7j),
   moyen terme (30j), long terme (90j+). Section "actionnable" (bandeau
   coloré + icône, ex. HRV basse) explicitement séparée des tuiles de
   données passives neutres (FC repos, pas, poids...).
   - **Graphique de superposition personnalisable** : deux sélecteurs — une
     métrique principale, puis soit un *repère* (jours de fractionné/
     musculation/nuit courte, en ticks sur un seul axe), soit une *seconde
     métrique* (FC repos/HRV/sommeil/poids/VO2 max/pas), rendue en courbe
     indexée sur sa propre plage min-max pour partager un seul axe — jamais
     de double axe. Défaut : FC repos × jours de fractionné.
   - Carte "Sommeil" doit router vers `SleepDetailScreen` (déjà codé,
     actuellement **orphelin**, jamais appelé nulle part dans l'app !) au
     lieu de `ScoreBreakdownScreen` — voir `lib/screens/sleep_detail_screen.dart`.
4. **Sport** — sous-onglet **Musculation** : ajouter un champ **charge (kg)**
   optionnel au flux de log rapide (`lib/models/musculation_log.dart`,
   `lib/screens/musculation_screen.dart`, actuellement séries×répétitions
   seulement, aucune charge). Permet volume de séance, 1RM estimé (formule
   d'Epley), progression par exercice. Sous-onglet **Course** : ajouter une
   carte "Records personnels" permanente (distance/allure/D+ — déjà calculés
   et célébrés à la volée dans `tracking_screen.dart`, mais jamais affichés
   en continu). Sous-onglet **Progression** : la stat RPG "Force" (dénivelé
   cumulé course uniquement aujourd'hui, voir `game_service.dart`) doit
   fusionner dénivelé + volume musculation une fois la charge trackée.
5. **Bouton +** : déjà présent dans l'app réelle (`shell_screen.dart`), rien
   à ajouter — juste à garder lors de la refonte.

## À faire / points ouverts

- **Press Start 2P pas encore appliquée à l'app réelle.** 94 usages de
  `kArcadeFont` répartis sur 20 écrans — police bien plus large qu'Orbitron,
  plusieurs cas de débordement rencontrés même sur les 4 écrans de la
  maquette. Pas de toolchain Flutter dans l'environnement où ce travail a
  été fait (impossible de lancer/screenshotter l'app pour vérifier). À
  appliquer écran par écran, uniquement sur du texte court (scores, XP,
  "NIVEAU 14"...), jamais sur un titre ou libellé de section, en vérifiant
  l'affichage réel à chaque fois.
- **Écrans avec palette codée en dur, indépendante de `theme.dart`** :
  `tracking_screen.dart`, `history_screen.dart`, `detail_screen.dart`,
  `widgets/system_window.dart`, `widgets/record_celebration.dart` —
  n'importent même pas `theme.dart`, utilisent leurs propres gris
  (`0xFF141419`, `0xFF333333`, etc.). Jamais migrés vers `AppColors`, même
  avant le changement de thème. Pas touché, hors périmètre de la passe
  couleur. À migrer si on veut une cohérence totale.
- **Vault Obsidian / "Marble"** : mis de côté explicitement, à traiter dans
  une session dédiée. Le repère visuel (icône + chemin) sous chaque post du
  Feed est pour l'instant décoratif uniquement. Note : le code contient déjà
  une référence à "Marble" comme source de deep links (`lib/main.dart`,
  commentaire sur `navigatorKey`) — a priori un projet/app compagnon déjà
  identifié côté utilisateur, pas à inventer from scratch.
- **Onglet Feed, Santé restructuré, Sport restructuré, champ charge
  musculation, carte records personnels, fusion stat Force** : tout ça reste
  à coder — seulement prototypé en HTML pour l'instant (liens ci-dessus).
