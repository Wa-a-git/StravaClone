// lib/screens/profile_screen.dart
// Onglet Profil : tout ce qui est "compte" plutôt que "santé du jour" —
// connexions externes (Google Health), profil corporel, réglages d'export.
// Sorti du dashboard santé pour ne pas mélanger données du jour et réglages.
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/activity_provider.dart';
import '../services/export_service.dart';
import '../services/google_health_api_service.dart';
import '../services/health_store.dart';
import '../services/vault_import_service.dart';
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
class _ExportSettingsCard extends ConsumerStatefulWidget {
  const _ExportSettingsCard();

  @override
  ConsumerState<_ExportSettingsCard> createState() => _ExportSettingsCardState();
}

class _ExportSettingsCardState extends ConsumerState<_ExportSettingsCard> {
  bool _restoring = false;

  Future<void> _restoreFromVault() async {
    setState(() => _restoring = true);
    try {
      final result = await VaultImportService.importActivities();
      ref.read(activityListProvider.notifier).refresh();
      if (!mounted) return;
      final message = result.total == 0
          ? 'Aucune fiche de course trouvée dans le vault.'
          : '${result.imported} course${result.imported > 1 ? 's' : ''} restaurée${result.imported > 1 ? 's' : ''}'
              '${result.skipped > 0 ? ' (${result.skipped} déjà présente${result.skipped > 1 ? 's' : ''})' : ''}'
              '${result.failed > 0 ? ' — ${result.failed} fiche${result.failed > 1 ? 's' : ''} illisible${result.failed > 1 ? 's' : ''}' : ''}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _chooseLocalFolder() async {
    if (await Permission.manageExternalStorage.request().isGranted ||
        await Permission.storage.request().isGranted) {
      final selectedDir = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choisir le dossier d\'export',
      );
      if (selectedDir != null) {
        await ExportService.saveExportDirectory(selectedDir);
        if (mounted) {
          setState(() {}); // rafraîchit l'affichage du dossier actuel
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Dossier d\'export mis à jour : $selectedDir')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFolder = ExportService.getSavedExportDirectory();
    return AppPanel(
      accent: kNeonCyan,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PanelTitle('DONNÉES & EXPORT', color: kNeonCyan),
          const SizedBox(height: 10),
          const Text(
            'Tes courses et données santé sont sauvegardées automatiquement '
            'vers ton vault Windroid dès que le réseau est disponible.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 10),
          const Text(
            'Si des courses ont disparu de l\'app (ex. après une réinstallation), '
            'elles peuvent être reconstruites depuis les fiches déjà exportées vers le vault.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          GlowButton(
            label: 'RESTAURER LES COURSES DEPUIS LE VAULT',
            icon: Icons.restore_rounded,
            color: kNeonViolet,
            busy: _restoring,
            onPressed: _restoreFromVault,
          ),
          const SizedBox(height: 4),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              collapsedIconColor: AppColors.textSecondary,
              iconColor: AppColors.textSecondary,
              title: const Text(
                'OPTIONS AVANCÉES',
                style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Si Windroid est injoignable (pas de réseau/Tailscale), '
                        'les exports peuvent être enregistrés dans un dossier '
                        'local à la place — secours seulement, rarement '
                        'nécessaire.',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                      ),
                      if (currentFolder != null) ...[
                        const SizedBox(height: 8),
                        Text('Dossier actuel : $currentFolder',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 11.5)),
                      ],
                      const SizedBox(height: 10),
                      GlowButton(
                        label: 'CHOISIR LE DOSSIER D\'EXPORT (SECOURS)',
                        icon: Icons.folder_open_rounded,
                        color: kNeonCyan,
                        onPressed: _chooseLocalFolder,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                if (HealthProfileStore.sex != null)
                  _ProfileStat(
                      label: 'SEXE',
                      value: HealthProfileStore.sex == 'F' ? 'F' : 'H',
                      unit: '',
                      color: kNeonCyan),
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
    String? sex = HealthProfileStore.sex;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
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
              const SizedBox(height: 12),
              // Optionnel — sert uniquement à affiner des références par
              // sexe (ex. catégorie de VO2 max), jamais supposé.
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const Text('Sexe', style: TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(width: 16),
                  ChoiceChip(
                    label: const Text('Homme'),
                    selected: sex == 'M',
                    onSelected: (v) => setDialogState(() => sex = v ? 'M' : null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Femme'),
                    selected: sex == 'F',
                    onSelected: (v) => setDialogState(() => sex = v ? 'F' : null),
                  ),
                ],
              ),
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
      ),
    );

    if (saved == true) {
      final wv = double.tryParse(wCtrl.text.replaceAll(',', '.'));
      final hv = double.tryParse(hCtrl.text.replaceAll(',', '.'));
      final av = int.tryParse(aCtrl.text);
      // setManualWeightToday (pas juste setWeight) : garde aussi la carte
      // "Poids" du dashboard Santé synchronisée avec cette saisie, sans
      // attendre une resynchro Health Connect.
      if (wv != null && wv > 0) await HealthStore.setManualWeightToday(wv);
      if (hv != null && hv > 0) await HealthProfileStore.setHeight(hv);
      if (av != null && av > 0) await HealthProfileStore.setAge(av);
      if (sex != null) await HealthProfileStore.setSex(sex!);
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
