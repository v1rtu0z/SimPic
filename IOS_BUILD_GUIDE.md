# iOS Build Guide for SimPic

This guide will help you build and distribute the SimPic app for iOS testing.

## Prerequisites

1. **macOS computer** (required for iOS builds)
2. **Xcode** (latest version recommended, available from Mac App Store)
3. **Apple Developer Account** (free account works for device testing, paid account needed for App Store/TestFlight)
4. **iOS device** for testing (iPhone/iPad)

## Quick Setup (Recommended)

If you are on a Mac, you can use the automated setup script to install dependencies and configure the project:

```bash
chmod +x setup_ios.sh
./setup_ios.sh
```

This script will:
1. Verify you are on macOS.
2. Check for Flutter, Xcode, and CocoaPods.
3. Install missing dependencies (if possible).
4. Run `flutter pub get`.
5. Run `pod install`.
6. Open the Xcode workspace for you.

---

## Manual Setup Steps

### 1. Install Dependencies

```bash
flutter pub get
cd ios
pod install
cd ..
```

### 2. Open Xcode Project

```bash
open ios/Runner.xcworkspace
```

### 3. Configure Signing & Capabilities

In Xcode:

1. Select the **Runner** project in the left sidebar
2. Select the **Runner** target
3. Go to **Signing & Capabilities** tab
4. Check **"Automatically manage signing"**
5. Select your **Team** (your Apple Developer account)
6. Xcode will automatically generate a Bundle Identifier (or you can set a custom one)

### 4. Configure Bundle Identifier

1. In the **General** tab, set a unique **Bundle Identifier** (e.g., `com.yourname.simpic`)
2. Make sure it matches your Apple Developer account

### 5. Connect Your iOS Device

1. Connect your iPhone/iPad via USB
2. Trust the computer on your device if prompted
3. In Xcode, select your device from the device dropdown (top toolbar)

### 6. Summary of Configured Settings

The following settings have already been configured in `ios/Runner/Info.plist`:

*   **Permissions**:
    *   `NSCameraUsageDescription`: Required for real-time coaching.
    *   `NSPhotoLibraryUsageDescription`: Required to save and view photos.
    *   `NSPhotoLibraryAddUsageDescription`: Required to save photos.
    *   `NSMicrophoneUsageDescription`: Included for compatibility with camera plugins.
*   **Orientations**: Locked to Portrait for a consistent coaching experience.
*   **App Name**: Set to "SimPic".
*   **Deep Links**: Added `photos-redirect` and `photos` schemes for opening the Photos app.

### 7. Building for Testing

### Option 1: Build and Run Directly (Quick Testing)

```bash
flutter run -d <device-id>
```

To see available devices:
```bash
flutter devices
```

### Option 2: Build IPA for Distribution

#### For Ad-Hoc Distribution (Send to Friend)

1. In Xcode, select **Product → Archive**
2. Wait for the archive to complete
3. In the Organizer window:
   - Click **Distribute App**
   - Select **Ad Hoc**
   - Select your team
   - Choose your archive
   - Click **Next**
   - Select **Automatically manage signing**
   - Click **Next**
   - Review and click **Export**
   - Choose a location to save the `.ipa` file

4. **Add your friend's device UDID**:
   - Your friend needs to send you their device UDID
   - In Xcode: **Window → Devices and Simulators**
   - Select the device and copy the **Identifier** (UDID)
   - Add it to your Apple Developer account under **Certificates, Identifiers & Profiles → Devices**
   - Re-archive and export

5. Send the `.ipa` file to your friend
6. They can install it using:
   - **Xcode** (drag .ipa to Devices window)
   - **Apple Configurator 2**
   - **3uTools** or similar tools

#### For TestFlight Distribution (Easier for Multiple Testers)

1. You need a **paid Apple Developer account** ($99/year)
2. In Xcode Organizer:
   - Click **Distribute App**
   - Select **App Store Connect**
   - Follow the prompts to upload
3. Go to [App Store Connect](https://appstoreconnect.apple.com)
4. Create a new app (if not already created)
5. Wait for processing (can take 10-30 minutes)
6. Go to **TestFlight** tab
7. Add internal/external testers
8. Send them the TestFlight invitation link

## Building from Command Line

### Build IPA directly:

```bash
flutter build ipa --release
```

The IPA will be at: `build/ios/ipa/simpic.ipa`

### Build for specific device:

```bash
flutter build ios --release --no-codesign
```

Then open in Xcode and archive manually.

## Troubleshooting

### "No such module 'Flutter'"

```bash
cd ios
pod install
cd ..
flutter clean
flutter pub get
```

### "Signing for Runner requires a development team"

- Make sure you're signed in to Xcode with your Apple ID
- Go to **Xcode → Settings → Accounts**
- Add your Apple ID if not present
- Select your team in the project settings

### "Could not find module 'google_mlkit_face_detection'"

```bash
cd ios
pod install
cd ..
```

### Camera permissions not working

Make sure `Info.plist` has:
- `NSCameraUsageDescription`
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`

These are already configured in the project.

### Face detection not working on iOS

The code has been updated to handle iOS camera formats. If you encounter issues:
1. Check the console logs for format errors
2. The app uses `YUV420` format on iOS (vs `NV21` on Android)
3. ML Kit should handle this automatically

## Sending to Friend - Quick Method

**Easiest way** (if you have a paid Apple Developer account):
1. Upload to TestFlight
2. Add your friend as a tester
3. They install TestFlight app and your app

**Alternative** (free account):
1. Get your friend's device UDID
2. Add it to your Apple Developer account
3. Build ad-hoc IPA
4. Send them the IPA file
5. They install via Xcode or Apple Configurator

## Notes

- The app requires iOS 15.1 or later
- Camera and photo library permissions are required
- Face detection uses Google ML Kit (works offline)
- The app is configured for portrait orientation only
