// lib/screens/mascot_gallery_screen.dart
// Onglet "Mascotte" : galerie des humeurs du personnage qui vit dans le HUD
// du Feed. Permet de rejouer chaque animation à la demande et explique dans
// quelles conditions elle apparaît normalement, pour que le lien entre les
// données santé/sport et le personnage reste lisible même en dehors du HUD.
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/mascot_sprites.dart';

class _MoodInfo {
  final MascotMood mood;
  final String label;
  final String caption;
  const _MoodInfo(this.mood, this.label, this.caption);
}

const _kMoodInfos = [
  _MoodInfo(MascotMood.running, 'Course',
      "Tenue par défaut — prête à courir à tout moment."),
  _MoodInfo(MascotMood.meditating, 'Méditation',
      "Récupération avancée ≥ 80 : le corps est bien reposé."),
  _MoodInfo(MascotMood.tired, 'Fatiguée',
      "Sommeil difficile la nuit dernière (score de sommeil < 50)."),
  _MoodInfo(MascotMood.happyTired, 'Contente',
      "La course du jour est déjà dans la poche."),
  _MoodInfo(MascotMood.proud, 'Fierté',
      "3 jours de suite avec au moins une course."),
  _MoodInfo(MascotMood.celebrating, 'Victoire',
      "Toutes les quêtes du jour sont bouclées."),
  _MoodInfo(MascotMood.neutral, 'Repos',
      "Pose par défaut, visible sur l'onglet Profil."),
];

class MascotGalleryScreen extends StatefulWidget {
  const MascotGalleryScreen({super.key});

  @override
  State<MascotGalleryScreen> createState() => _MascotGalleryScreenState();
}

class _MascotGalleryScreenState extends State<MascotGalleryScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hop;
  MascotMood _selected = MascotMood.running;

  @override
  void initState() {
    super.initState();
    _hop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat();
  }

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _kMoodInfos.firstWhere((i) => i.mood == _selected);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: const FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'MASCOTTE',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _previewCard(info),
                const SizedBox(height: 20),
                const Text(
                  'HUMEURS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                _moodGrid(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewCard(_MoodInfo info) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kNeonPink.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: kNeonPink.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 18)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1A0E2C), Color(0xFF150A24), Color(0xFF0F0819)],
                  stops: [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.8),
                  radius: 1.1,
                  colors: [kNeonViolet.withOpacity(0.22), kNeonViolet.withOpacity(0)],
                ),
              ),
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 14),
              _scene(info.mood),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      info.label,
                      style: const TextStyle(
                        fontFamily: kArcadeFont,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      info.caption,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scene(MascotMood mood) {
    final (dir, prefix, frameCount) = kMascotSprites[mood]!;
    return SizedBox(
      height: 300,
      child: AnimatedBuilder(
        animation: _hop,
        builder: (context, child) {
          final t = _hop.value;
          final frame = (t * frameCount).floor() % frameCount + 1;
          return Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Positioned(
                bottom: 20,
                child: Container(
                  width: 76,
                  height: 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: RadialGradient(colors: [
                      Colors.black.withOpacity(0.4),
                      Colors.black.withOpacity(0),
                    ]),
                  ),
                ),
              ),
              Positioned(
                bottom: 24,
                child: Image.asset(
                  'assets/$dir/${prefix}_$frame.png',
                  height: 260,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _moodGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _kMoodInfos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, i) {
        final info = _kMoodInfos[i];
        final selected = info.mood == _selected;
        return GestureDetector(
          onTap: () => setState(() => _selected = info.mood),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? kNeonPink : AppColors.border,
                width: selected ? 2 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: kNeonPink.withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Image.asset(
                    mascotSpriteAsset(info.mood, 1),
                    filterQuality: FilterQuality.none,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? kNeonPink : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
