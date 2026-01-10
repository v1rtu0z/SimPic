# Quick Start Guide

## Prerequisites

1. Install Flutter: https://flutter.dev/docs/get-started/install
2. Set up Android SDK (for Android development)
3. Set environment variables:
   ```bash
   export JAVA_HOME=/usr/lib/jvm/java-1.21.0-openjdk-amd64
   export ANDROID_HOME=$HOME/Android/Sdk
   ```

## Setup

```bash
cd flutter
./setup.sh
# OR manually:
flutter pub get
```

## Run the App

### Android (Physical Device)
1. Connect device via USB
2. Enable USB debugging
3. Run: `flutter run`

### Android (Emulator)
1. Start Android emulator
2. Run: `flutter run`

### iOS (macOS only)
1. Open iOS Simulator or connect device
2. Run: `flutter run`

## Build Release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

## Troubleshooting

### Flutter not found
- Install Flutter SDK
- Add Flutter to PATH: `export PATH="$PATH:$HOME/flutter/bin"`

### Android build errors
- Run `flutter doctor` to check configuration
- Ensure `JAVA_HOME` and `ANDROID_HOME` are set correctly
- Clean build: `flutter clean && flutter pub get`

### Camera permission issues
- Check `android/app/src/main/AndroidManifest.xml` for permissions
- On Android 6+, permissions are requested at runtime
- Check device settings if permission is denied

## Next Steps

- Implement face detection using ML Kit
- Add real-time coaching features
- See `README.md` for full documentation
