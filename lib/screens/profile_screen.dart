// lib/screens/profile_screen.dart
// Onglet Profil : tout ce qui est "compte" plutôt que "santé du jour" —
// connexions externes (Google Health), profil corporel, réglages d'export.
// Sorti du dashboard santé pour ne pas mélanger données du jour et réglages.
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/export_service.dart';
import '../services/google_health_api_service.dart';
import '../services/health_store.dart';
import '../theme.dart';
import '../widgets/ui_kit.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            expandedHeight: 100,
            pinned: true,
            backgroundColor: AppColors.surface,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.only(left: 20, bottom: 16),
              title: Text(
                'PROFIL',
                style: TextStyle(
                  fontFamily: kArcadeFont,
                  color: AppColors.textPrimary,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  shadows: [Shadow(color: AppColors.arcadeViolet, blurRadius: 12)],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  BodyProfileCard(),
                  SizedBox(height: 16),
                  GoogleHealthCard(),
                  SizedBox(height: 16),
                  _ExportSettingsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Réglages d'export ─────────────────────────────────────────────────────────
class _ExportSettingsCard extends StatelessWidget {
  const _ExportSettingsCard();

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('DONNÉES & EXPORT', color: kNeonCyan),
          const SizedBox(height: 10),
          const Text(
            'Choisis le dossier où sont enregistrés les exports .md de tes courses.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: 'CHOISIR LE DOSSIER D\'EXPORT',
            icon: Icons.folder_open_rounded,
            color: kNeonCyan,
            onPressed: () async {
              if (await Permission.manageExternalStorage.request().isGranted ||
                  await Permission.storage.request().isGranted) {
                final selectedDir = await FilePicker.getDirectoryPath(
                  dialogTitle: 'Choisir le dossier d\'export',
                );
                if (selectedDir != null) {
                  await ExportService.saveExportDirectory(selectedDir);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Dossier d\'export mis à jour : $selectedDir')),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Carte connexion Google Health API (OAuth) ─────────────────────────────────
class GoogleHealthCard extends StatefulWidget {
  const GoogleHealthCard({super.key});

  @override
  State<GoogleHealthCard> createState() => _GoogleHealthCardState();
}

class _GoogleHealthCardState extends State<GoogleHealthCard> {
  final _service = GoogleHealthApiService();
  bool _connected = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service.isConnected().then((v) {
      if (mounted) setState(() => _connected = v);
    });
  }

  /// Statut VO2 max lu depuis les données santé locales déjà synchronisées
  /// (le dashboard Santé se charge du fetch réel) — cette carte se contente
  /// de refléter l'état, plus de bouton de test manuel.
  String? get _vo2Status {
    if (!_connected) return null;
    final vo2 = HealthStore.recordFor(DateTime.now())?.vo2Max ?? 0;
    return vo2 > 0
        ? 'VO2 max synchronisé : ${vo2.toStringAsFixed(1)} ml/kg/min'
        : 'En attente de calibration montre (VO2 max pas encore dispo).';
  }

  Future<void> _toggle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_connected) {
        await _service.disconnect();
        if (mounted) setState(() => _connected = false);
      } else {
        final ok = await _service.connect();
        if (mounted) setState(() => _connected = ok);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = _connected ? kNeonGreen : kNeonAmber;
    return AppPanel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_connected ? Icons.cloud_done_rounded : Icons.cloud_rounded,
                  color: accent, size: 20),
              const SizedBox(width: 10),
              PanelTitle('GOOGLE HEALTH API', color: accent),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _connected
                ? 'Connecté ✓ — le VO2 max synchronise automatiquement dans l\'onglet Santé.'
                : 'Connecte-toi pour débloquer VO2 max, préparation et historique long, au-delà de Health Connect.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text('Erreur : $_error',
                style: const TextStyle(color: kNeonPink, fontSize: 11)),
          ],
          const SizedBox(height: 14),
          GlowButton(
            label: _connected ? 'DÉCONNECTER' : 'CONNECTER GOOGLE HEALTH',
            icon: _connected ? Icons.link_off_rounded : Icons.link_rounded,
            color: _connected ? AppColors.surfaceLight : accent,
            foreground: _connected ? Colors.white : Colors.black,
            busy: _busy,
            onPressed: _toggle,
          ),
          if (_vo2Status != null) ...[
            const SizedBox(height: 10),
            Text(_vo2Status!,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

// ── Carte profil corporel (poids / taille / IMC / âge) ────────────────────────
class BodyProfileCard extends StatefulWidget {
  const BodyProfileCard({super.key});

  @override
  State<BodyProfileCard> createState() => _BodyProfileCardState();
}

class _BodyProfileCardState extends State<BodyProfileCard> {
  @override
  Widget build(BuildContext context) {
    final w = HealthProfileStore.weightKg;
    final h = HealthProfileStore.heightCm;
    final age = HealthProfileStore.age;
    final bmi = HealthProfileStore.bmi;

    return AppPanel(
      accent: kNeonViolet,
      onTap: _edit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const PanelTitle('PROFIL CORPOREL', color: kNeonViolet),
              const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 16),
            ],
          ),
          const SizedBox(height: 14),
          if (!HealthProfileStore.isComplete)
            const Text(
              'Ajoute ton poids et ta taille pour débloquer l\'IMC et affiner tes calculs. Appuie ici.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            )
          else
            Row(
              children: [
                _ProfileStat(label: 'POIDS', value: w!.toStringAsFixed(0), unit: 'kg', color: kNeonCyan),
                _ProfileStat(label: 'TAILLE', value: h!.toStringAsFixed(0), unit: 'cm', color: kNeonGreen),
                _ProfileStat(
                    label: 'IMC',
                    value: bmi!.toStringAsFixed(1),
                    unit: HealthProfileStore.bmiCategory(bmi),
                    color: kNeonViolet),
                if (age != null)
                  _ProfileStat(label: 'ÂGE', value: age.toString(), unit: 'ans', color: kNeonAmber),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final wCtrl = TextEditingController(text: HealthProfileStore.weightKg?.toStringAsFixed(0) ?? '');
    final hCtrl = TextEditingController(text: HealthProfileStore.heightCm?.toStringAsFixed(0) ?? '');
    final aCtrl = TextEditingController(text: HealthProfileStore.age?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Profil corporel',
            style: TextStyle(fontFamily: kArcadeFont, color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _profileField(wCtrl, 'Poids', 'kg'),
            const SizedBox(height: 12),
            _profileField(hCtrl, 'Taille', 'cm'),
            const SizedBox(height: 12),
            _profileField(aCtrl, 'Âge', 'ans'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kNeonViolet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (saved == true) {
      final wv = double.tryParse(wCtrl.text.replaceAll(',', '.'));
      final hv = double.tryParse(hCtrl.text.replaceAll(',', '.'));
      final av = int.tryParse(aCtrl.text);
      if (wv != null && wv > 0) await HealthProfileStore.setWeight(wv);
      if (hv != null && hv > 0) await HealthProfileStore.setHeight(hv);
      if (av != null && av > 0) await HealthProfileStore.setAge(av);
      if (mounted) setState(() {});
    }
  }

  Widget _profileField(TextEditingController ctrl, String label, String unit) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, suffixText: unit),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;
  const _ProfileStat({required this.label, required this.value, required this.unit, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(fontFamily: kArcadeFont, color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
