// lib/services/google_health_api_service.dart
// Client Google Health API (cloud, ex-Fitbit Web API).
// Connexion via google_sign_in : feuille native Google (pas de navigateur, pas
// de redirection custom), qui s'appuie sur le client OAuth Android (SHA-1 +
// package) cree dans la console. Zero secret, zero backend.
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleHealthApiService {
  static const List<String> scopes = [
    'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
    'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
    'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
    'https://www.googleapis.com/auth/googlehealth.profile.readonly',
  ];

  // Instance unique (le plugin gere l'etat de session).
  static final GoogleSignIn _google = GoogleSignIn(scopes: scopes);

  /// Restaure une session existante sans UI. True si connecte.
  Future<bool> isConnected() async {
    if (_google.currentUser != null) return true;
    final account = await _google.signInSilently();
    return account != null;
  }

  /// Ouvre la feuille de connexion native Google et demande les scopes santé.
  Future<bool> connect() async {
    final account = await _google.signIn();
    if (account == null) return false; // annule par l'utilisateur
    // S'assure que tous les scopes santé sont bien accordes.
    final granted = await _google.requestScopes(scopes);
    return granted;
  }

  Future<void> disconnect() async {
    await _google.disconnect();
  }

  /// Access token valide pour appeler health.googleapis.com (refresh silencieux
  /// gere par Google Play Services). Null si non connecte.
  Future<String?> accessToken() async {
    final account = _google.currentUser ?? await _google.signInSilently();
    if (account == null) return null;
    final auth = await account.authentication;
    return auth.accessToken;
  }

  // ── Appels REST Google Health API ───────────────────────────────────────────
  static const String _base = 'https://health.googleapis.com/v4/users/me';

  /// GET brut sur un chemin de l'API. Log de diagnostic inclus.
  Future<Map<String, dynamic>?> _get(String path) async {
    final token = await accessToken();
    if (token == null) {
      print('GH_API: pas de token (non connecte)');
      return null;
    }
    try {
      final resp = await http.get(
        Uri.parse('$_base$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      print('GH_API GET $path -> ${resp.statusCode}');
      print('GH_API body: ${resp.body}');
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      print('GH_API erreur $path: $e');
      return null;
    }
  }

  /// Identite de l'utilisateur (prouve que l'API repond). Retourne le JSON brut.
  Future<Map<String, dynamic>?> getIdentity() => _get('/identity');

  /// Liste brute des dataPoints d'un type (kebab-case, ex: 'daily-vo2-max').
  Future<List<dynamic>> getDataPoints(String dataType) async {
    final data = await _get('/dataTypes/$dataType/dataPoints?page_size=30');
    if (data == null) return const [];
    return (data['dataPoints'] as List?) ?? const [];
  }

  /// Dernier VO2 max quotidien disponible (null si en calibrage / absent).
  /// Le parsing exact sera affine apres inspection du JSON reel (log).
  Future<double?> getLatestVo2Max() async {
    final points = await getDataPoints('daily-vo2-max');
    if (points.isEmpty) return null;
    final last = points.last;
    if (last is Map) {
      final block = last['dailyVo2Max'] ?? last['vo2Max'] ?? last['daily_vo2_max'];
      final v = _extractNumber(block);
      if (v != null) return v;
    }
    return null;
  }

  /// Écart de température cutanée du jour vs baseline personnelle (°C) —
  /// essai best-effort : le nom exact du dataType Google Health API v4 pour
  /// la température cutanée n'est pas confirmé (pas de doc publique testée),
  /// à ajuster après inspection des logs GH_API si l'appel ne renvoie jamais
  /// rien. Null si indisponible/scope refusé — ne doit jamais bloquer le
  /// reste de la synchro santé (voir `HealthInsightsService.physioAnomalyInsight`,
  /// qui traite ce signal comme optionnel).
  Future<double?> getLatestSkinTemperatureDeltaC() async {
    final points = await getDataPoints('daily-skin-temperature');
    if (points.isEmpty) return null;
    final last = points.last;
    if (last is Map) {
      final block = last['dailySkinTemperature'] ??
          last['skinTemperature'] ??
          last['daily_skin_temperature'];
      return _extractNumber(block);
    }
    return null;
  }

  double? _extractNumber(dynamic node) {
    if (node is num) return node.toDouble();
    if (node is String) return double.tryParse(node);
    if (node is Map) {
      for (final key in ['value', 'vo2MaxMlKgMin', 'ml_kg_min', 'mlKgMin']) {
        if (node[key] != null) {
          final v = _extractNumber(node[key]);
          if (v != null) return v;
        }
      }
    }
    return null;
  }
}
