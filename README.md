# Strava — Flutter Activity Tracker

A clean, minimalist GPS run-tracking app for Android and iOS, inspired by Strava. Built with Flutter and designed with an iOS-style UI.


---

## Features

- **GPS Run Tracking** — Real-time route recording using device GPS
- **Live Stats** — Time, distance, and pace updated every second while running
- **Pause & Resume** — Pause a run mid-activity and continue where you left off
- **Route Map** — Live route polyline drawn on OpenStreetMap via `flutter_map`
- **Activity History** — Browse all past runs sorted newest-first
- **Activity Detail** — Full map replay, stats breakdown, and start/finish coordinates
- **Offline Storage** — All activities saved locally using Hive (no account required)
- **iOS-style UI** — Large titles, bottom tab navigation, bottom sheet dialogs, haptic feedback

---

## Tech Stack

| Layer | Package |
|---|---|
| Framework | Flutter 3.x |
| State Management | `flutter_riverpod` |
| Local Database | `hive` + `hive_flutter` |
| Maps | `flutter_map` + OpenStreetMap tiles |
| GPS | `geolocator` |
| Permissions | `permission_handler` |
| Coordinates | `latlong2` |

---

## Project Structure

```
lib/
├── main.dart                  # App entry point, theme setup
├── models/
│   ├── activity.dart          # Hive model — stores run data
│   └── activity.g.dart        # Generated Hive adapter
├── providers/
│   ├── activity_provider.dart # Activity list state (Riverpod)
│   └── tracking_provider.dart # Live tracking state (Riverpod)
├── screens/
│   ├── shell_screen.dart      # Bottom tab navigator root
│   ├── home_screen.dart       # Dashboard — stats + latest activity
│   ├── tracking_screen.dart   # Live GPS recording screen
│   ├── history_screen.dart    # All past activities list
│   └── detail_screen.dart     # Individual activity detail + map
└── services/
    ├── hive_service.dart      # Hive read/write helpers
    ├── location_service.dart  # GPS permission + stream helpers
    └── tracking_service.dart  # Legacy tracking service (reference)
```

---

## Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0`
- Dart SDK `>=3.0.0`
- Android SDK or Xcode (for iOS builds)

### Installation

```bash
# 1. Clone the repository
git clone https://github.com/YOUR_USERNAME/strava-flutter.git
cd strava-flutter

# 2. Install dependencies
flutter pub get

# 3. Generate Hive adapters
flutter pub run build_runner build --delete-conflicting-outputs

# 4. Run the app
flutter run
```

---

## Permissions

### Android

Add to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.INTERNET" />
```

### iOS

Add to `ios/Runner/Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Strava needs your location to track your run.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Strava needs your location to track your run in the background.</string>
```

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.x.x
  hive: ^2.x.x
  hive_flutter: ^1.x.x
  flutter_map: ^6.x.x
  latlong2: ^0.9.x
  geolocator: ^11.x.x
  permission_handler: ^11.x.x

dev_dependencies:
  hive_generator: ^2.x.x
  build_runner: ^2.x.x
```

> Check `pubspec.yaml` for exact pinned versions.
