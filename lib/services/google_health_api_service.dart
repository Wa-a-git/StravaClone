// lib/services/google_health_api_service.dart
// Client Google Health API (cloud, ex-Fitbit Web API) via OAuth 2.0 PKCE.
// Client Android public : aucun secret. Jalon 1 = connexion + gestion des tokens.
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class GoogleHealthApiService {
  // Client OAuth Android cree dans Google Cloud Console (perso, mode Testing).
  static const String _clientId =
      '899312472150-aiulhp0a3sr3ltp4vbm9o3abb0ea6l6j.apps.googleusercontent.com';
  // Redirection = Client ID inverse (schema declare dans build.gradle.kts).
  static const String _redirectUrl =
      'com.googleusercontent.apps.899312472150-aiulhp0a3sr3ltp4vbm9o3abb0ea6l6j:/oauth2redirect';

  static const List<String> _scopes = [
    'openid',
    'email',
    'https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly',
    'https://www.googleapis.com/auth/googlehealth.sleep.readonly',
    'https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly',
    'https://www.googleapis.com/auth/googlehealth.profile.readonly',
  ];

  static const AuthorizationServiceConfiguration _serviceConfig =
      AuthorizationServiceConfiguration(
    authorizationEndpoint: 'https://accounts.google.com/o/oauth2/v2/auth',
    tokenEndpoint: 'https://oauth2.googleapis.com/token',
  );

  final FlutterAppAuth _appAuth = FlutterAppAuth();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const _kAccess = 'gh_access_token';
  static const _kRefresh = 'gh_refresh_token';
  static const _kExpiry = 'gh_expiry';

  Future<bool> isConnected() async =>
      (await _storage.read(key: _kRefresh)) != null;

  /// Lance le flux OAuth (navigateur systeme) et stocke les tokens.
  /// Retourne true si un access token a bien ete obtenu.
  Future<bool> connect() async {
    final result = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        _clientId,
        _redirectUrl,
        serviceConfiguration: _serviceConfig,
        scopes: _scopes,
        // access_type=offline + prompt=consent => refresh token delivre.
        promptValues: const ['consent'],
        additionalParameters: const {'access_type': 'offline'},
      ),
    );
    await _persist(result.accessToken, result.refreshToken,
        result.accessTokenExpirationDateTime);
    return result.accessToken != null;
  }

  Future<void> disconnect() async {
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
    await _storage.delete(key: _kExpiry);
  }

  /// Retourne un access token valide, en le rafraichissant si expire.
  /// Null si non connecte / refresh impossible (ex: token 7j expire en Testing).
  Future<String?> validAccessToken() async {
    final access = await _storage.read(key: _kAccess);
    final expiryStr = await _storage.read(key: _kExpiry);
    if (access != null && expiryStr != null) {
      final expiry = DateTime.tryParse(expiryStr);
      if (expiry != null &&
          expiry.isAfter(DateTime.now().add(const Duration(seconds: 60)))) {
        return access;
      }
    }
    final refresh = await _storage.read(key: _kRefresh);
    if (refresh == null) return null;
    try {
      final result = await _appAuth.token(TokenRequest(
        _clientId,
        _redirectUrl,
        serviceConfiguration: _serviceConfig,
        refreshToken: refresh,
        grantType: 'refresh_token',
      ));
      await _persist(result.accessToken, result.refreshToken ?? refresh,
          result.accessTokenExpirationDateTime);
      return result.accessToken;
    } catch (_) {
      // Refresh expire (mode Testing = 7 jours) : il faudra se reconnecter.
      return null;
    }
  }

  Future<void> _persist(
      String? access, String? refresh, DateTime? expiry) async {
    if (access != null) await _storage.write(key: _kAccess, value: access);
    if (refresh != null) await _storage.write(key: _kRefresh, value: refresh);
    if (expiry != null) {
      await _storage.write(key: _kExpiry, value: expiry.toIso8601String());
    }
  }
}
