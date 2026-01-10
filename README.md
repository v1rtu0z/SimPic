# SimPic - AI Photo Coach (Flutter)

SimPic is an AI-powered camera app that provides real-time coaching to help you take better portraits and improve your photography skills.

## 🎯 Current Status & Tech Stack

*   **Framework**: Flutter (Native mobile development)
*   **Camera Engine**: [camera](https://pub.dev/packages/camera) package
*   **Target Platforms**: Android (primary), iOS (secondary)
*   **Dev Workflow**: Hot Reload with Flutter

## 🛠 Setup & Development Workflow

### 1. Prerequisites

Ensure you have the following installed:
*   **Flutter SDK**: Install from [flutter.dev](https://flutter.dev/docs/get-started/install)
*   **Android Studio**: For Android development
*   **Xcode** (macOS only): For iOS development
*   **Java 21**: `export JAVA_HOME=/usr/lib/jvm/java-1.21.0-openjdk-amd64`
*   **Android SDK**: `export ANDROID_HOME=$HOME/Android/Sdk`

### 2. Installation

```bash
cd flutter
flutter pub get
```

### 3. Running the App

#### Android
1. **Connect your phone** via USB and ensure USB Debugging is on.
2. **Run the app**:
   ```bash
   flutter run
   ```
   Or use Android Studio to run/debug.

#### iOS (macOS only)
1. **Open iOS Simulator** or connect physical device
2. **Run the app**:
   ```bash
   flutter run
   ```

### 4. Building Release APK (Android)

```bash
flutter build apk --release
```

The APK will be located at: `build/app/outputs/flutter-apk/app-release.apk`

## 📱 Features

### Current Implementation
- ✅ Full-screen camera preview
- ✅ Camera permission handling
- ✅ App lifecycle management (pause/resume camera)
- ✅ Portrait orientation lock

### Planned Features
- [ ] Face detection using ML Kit or Google ML Kit
- [ ] Real-time face detection overlays
- [ ] Distance coaching
- [ ] Composition guidance
- [ ] Lighting analysis

## 🗂 Project Structure

```
flutter/
├── lib/
│   ├── main.dart              # App entry point
│   └── screens/
│       └── camera_screen.dart # Camera implementation
├── android/                   # Android-specific configuration
├── ios/                       # iOS-specific configuration
└── pubspec.yaml              # Dependencies and assets
```

## 📝 Developer Notes

*   **Camera Package**: Uses Flutter's official `camera` package for native camera access
*   **Permissions**: Camera permissions are handled automatically by the `permission_handler` package
*   **Face Detection**: Will be implemented later using Google ML Kit or similar Flutter packages
*   **Performance**: Flutter provides native performance with hot reload for fast development

## 🔧 Troubleshooting

### Android Build Issues
- Ensure `JAVA_HOME` and `ANDROID_HOME` are set correctly
- Run `flutter doctor` to check for configuration issues
- Clean build: `flutter clean && flutter pub get`

### Camera Permission Issues
- Check `AndroidManifest.xml` for camera permissions
- On Android 6+, permissions are requested at runtime
- Check device settings if permission is denied

## 📄 License

Private project - All rights reserved
