// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationService {
  /// Request location-when-in-use permission.
  /// Returns true if granted.
  static Future<bool> requestPermission() async {
    final status = await Permission.locationWhenInUse.request();
    return !status.isDenied && !status.isPermanentlyDenied;
  }

  /// Whether the device's location service is switched on.
  static Future<bool> isLocationEnabled() =>
      Geolocator.isLocationServiceEnabled();

  /// One-shot current position (returns null on failure).
  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  /// Continuous position stream — updates every ≥5 m moved.
  static Stream<Position> getPositionStream() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// Haversine distance in metres between two coordinates.
  static double distanceBetween(
      double startLat,
      double startLng,
      double endLat,
      double endLng,
      ) =>
      Geolocator.distanceBetween(startLat, startLng, endLat, endLng);

  /// Human-readable permission status string.
  static Future<String> checkPermissionStatus() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location services are disabled.';
    }
    switch (await Geolocator.checkPermission()) {
      case LocationPermission.denied:
        return 'Location permission denied.';
      case LocationPermission.deniedForever:
        return 'Location permission permanently denied. Enable in Settings.';
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        return 'granted';
      default:
        return 'Unknown permission state.';
    }
  }
}