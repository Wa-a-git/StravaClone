// lib/main.dart
import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/activity.dart';
import 'screens/detail_screen.dart';
import 'screens/health_history_screen.dart';
import 'services/health_store.dart';
import 'services/hive_service.dart';
import 'screens/shell_screen.dart';
import 'widgets/arcade_fx.dart';
import 'theme.dart';

/// Clé de navigation globale : les deep links (Marble → fiche précise)
/// arrivent en dehors de tout `BuildContext` d'écran, il faut donc pouvoir
/// pousser une route depuis l'extérieur de l'arbre de widgets.
final navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));

  await HiveService.init();
  runApp(const ProviderScope(child: ArcadeHealthApp()));
}

class ArcadeHealthApp extends StatefulWidget {
  const ArcadeHealthApp({super.key});

  @override
  State<ArcadeHealthApp> createState() => _ArcadeHealthAppState();
}

class _ArcadeHealthAppState extends State<ArcadeHealthApp> {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  /// Écoute les liens `arcadehealth://<classe>/<id>` envoyés par Marble
  /// (tap sur une fiche sport/santé dans l'aperçu du jour) — à froid
  /// ([getInitialLink]) et à chaud (app déjà lancée, [uriLinkStream]).
  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleDeepLink(initial);
    } catch (_) {
      // Pas de lien initial ou plateforme non supportée : rien à faire.
    }
    _linkSub = _appLinks.uriLinkStream.listen(_handleDeepLink, onError: (_) {});
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'arcadehealth') return;
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    if (id == null || id.isEmpty) return;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (uri.host) {
      case 'exercice':
        final epochMs = int.tryParse(id);
        if (epochMs == null) return;
        Activity? found;
        for (final a in HiveService.getAllActivities()) {
          if (a.date.millisecondsSinceEpoch == epochMs) {
            found = a;
            break;
          }
        }
        if (found != null) {
          nav.push(MaterialPageRoute(builder: (_) => DetailScreen(activity: found!)));
        }
        break;
      case 'sante':
        final date = DateTime.tryParse(id);
        if (date == null) return;
        final record = HealthStore.recordFor(date);
        if (record != null) {
          nav.push(MaterialPageRoute(builder: (_) => HealthDayDetailScreen(record: record)));
        }
        break;
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Arcade Health',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      // Overlay CRT (scanlines + léger vignettage) — discret, garde l'identité
      // arcade sans nuire à la lisibilité du texte courant.
      builder: (context, child) => ScanlineOverlay(
        opacity: 0.025,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const ShellScreen(),
    );
  }

  ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.arcadePink,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'SF Pro Display',
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      cardColor: AppColors.surface,
      dividerColor: AppColors.border,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.arcadePink,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: const TextStyle(color: AppColors.muted),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: kNeonCyan),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: AppColors.textPrimary),
        bodyMedium: TextStyle(color: AppColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.arcadePink,
        unselectedItemColor: AppColors.textSecondary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}