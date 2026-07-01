// lib/services/google_health_api_service.dart
// Client Google Health API (cloud, ex-Fitbit Web API).
// Connexion via google_sign_in : feuille native Google (pas de navigateur, pas
// de redirection custom), qui s'appuie sur le client OAuth Android (SHA-1 +
// package) cree dans la console. Zero secret, zero backend.
import 'package:google_sign_in/google_sign_in.dart';

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
}
