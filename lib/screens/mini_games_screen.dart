// lib/screens/mini_games_screen.dart
import 'package:flutter/material.dart';
import '../services/game_result_store.dart';
import '../services/live_pace.dart';
import '../theme.dart';
import 'pace_zone_game_screen.dart';
import 'interval_game_screen.dart';

class MiniGamesScreen extends StatefulWidget {
  const MiniGamesScreen({super.key});

  @override
  State<MiniGamesScreen> createState() => _MiniGamesScreenState();
}

class _MiniGamesScreenState extends State<MiniGamesScreen> {
  Future<void> _open(Widget screen) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) setState(() {}); // refresh l'historique au retour
  }

  @override
  Widget build(BuildContext context) {
    final results = GameResultStore.all();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('MINI-JEUX',
            style: TextStyle(
                fontFamily: kArcadeFont,
                color: kNeonViolet,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                shadows: [Shadow(color: kNeonViolet, blurRadius: 12)])),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GameCard(
            icon: Icons.track_changes_rounded,
            title: 'ZONE D\'ALLURE',
            subtitle: 'Tiens ton allure cible, guidé par la voix',
            color: kNeonGreen,
            onTap: () => _open(const PaceZoneGameScreen()),
          ),
          const SizedBox(height: 14),
          _GameCard(
            icon: Icons.repeat_rounded,
            title: 'FRACTIONNÉ',
            subtitle: 'Intervalles effort / récup avec coach audio',
            color: kNeonPink,
            onTap: () => _open(const IntervalGameScreen()),
          ),
          const SizedBox(height: 28),
          const Text('DERNIERS RÉSULTATS',
              style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5)),
          const SizedBox(height: 12),
          if (results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Aucun résultat pour le moment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...results.map((r) => _ResultTile(data: r)),
        ],
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;
  const _GameCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.5), width: 1.3),
          boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 16)],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color, width: 1.3),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: kArcadeFont,
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.play_circle_fill_rounded, color: color, size: 30),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ResultTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = data['type'] as String;
    final date = DateTime.fromMillisecondsSinceEpoch(data['date'] as int);
    final isPace = type == 'pace';
    final color = isPace ? kNeonGreen : kNeonPink;

    String title;
    String detail;
    if (isPace) {
      title = 'Zone d\'allure';
      final pct = data['pctInZone'] ?? 0;
      final dist = ((data['distance'] ?? 0) as num).toDouble() / 1000;
      detail =
          '$pct % en zone • ${dist.toStringAsFixed(2)} km • cible ${formatPace(data['targetSec'] as int?)}/km';
    } else {
      title = 'Fractionné';
      final done = data['repsCompleted'] ?? 0;
      final reps = data['reps'] ?? 0;
      final dist = ((data['workDistance'] ?? 0) as num).toDouble() / 1000;
      detail = '$done/$reps reps • ${dist.toStringAsFixed(2)} km effort';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(detail,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('+${data['xp'] ?? 0} XP',
                  style: TextStyle(
                      fontFamily: kArcadeFont,
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text('${date.day}/${date.month}',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
