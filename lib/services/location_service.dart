// lib/services/location_service.dart
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Request location permission using geolocator (consistent with main.dart).
  /// Returns true if granted (whileInUse or always).
  static Future<bool> requestPermission() async {
    // Check if location services are enabled on device
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    // If denied, request permission
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // If permanently denied, cannot request — return false
    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    // ✅ Grant if whileInUse or always
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
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