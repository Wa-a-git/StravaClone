// lib/services/live_pace.dart
// Calcule une vitesse / allure GPS lissée sur une fenêtre glissante,
// + la distance totale parcourue (filtrée du bruit GPS).
import 'package:geolocator/geolocator.dart';

class _Sample {
  final DateTime time;
  final double lat;
  final double lng;
  _Sample(this.time, this.lat, this.lng);
}

class LivePace {
  final Duration window;
  final List<_Sample> _samples = [];
  double totalDistance = 0; // mètres

  LivePace({this.window = const Duration(seconds: 6)});

  /// Ajoute une position GPS et renvoie la vitesse lissée (km/h).
  double addPosition(Position p) {
    final now = DateTime.now();
    if (_samples.isNotEmpty) {
      final last = _samples.last;
      final d = Geolocator.distanceBetween(
          last.lat, last.lng, p.latitude, p.longitude);
      // Filtre le bruit : on ignore les micro-sauts et les points imprécis
      if (d > 0.4 && p.accuracy <= 25) {
        totalDistance += d;
      }
    }
    _samples.add(_Sample(now, p.latitude, p.longitude));
    _samples.removeWhere((s) => now.difference(s.time) > window);
    return currentSpeedKmh;
  }

  double get currentSpeedKmh {
    if (_samples.length < 2) return 0;
    double dist = 0;
    for (int i = 1; i < _samples.length; i++) {
      dist += Geolocator.distanceBetween(
        _samples[i - 1].lat,
        _samples[i - 1].lng,
        _samples[i].lat,
        _samples[i].lng,
      );
    }
    final dt =
        _samples.last.time.difference(_samples.first.time).inMilliseconds /
            1000.0;
    if (dt <= 0) return 0;
    return (dist / dt) * 3.6;
  }

  /// Allure en secondes/km (null si à l'arrêt).
  int? get paceSecPerKm {
    final s = currentSpeedKmh;
    if (s < 0.5) return null;
    return (3600 / s).round();
  }

  /// Réinitialise la mémoire de vitesse (sans toucher la distance totale).
  void resetWindow() => _samples.clear();
}

/// Formate une allure (sec/km) en "m:ss".
String formatPace(int? secPerKm) {
  if (secPerKm == null || secPerKm <= 0 || secPerKm > 3600) return '--:--';
  final m = secPerKm ~/ 60;
  final s = secPerKm % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
