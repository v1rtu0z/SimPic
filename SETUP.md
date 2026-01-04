# Testing SimPic on Android Phone

## Quick Start (Expo Go - No Face Detection)

If you just want to test the camera UI quickly:

```bash
# 1. Install dependencies
npm install

# 2. Install Expo Go on your Android phone from Play Store

# 3. Start the server
npm start

# 4. Scan QR code with Expo Go app
```

**Note:** Face detection won't work in Expo Go due to custom native code requirements.

---

## Full Setup (With Face Detection) ⭐

### Prerequisites

1. **Node.js** installed on your computer (you likely have this)
2. **Android phone** connected to same WiFi as your computer
3. **Expo account** (free - create at expo.dev)

### Step-by-Step Instructions

#### 1. Install Dependencies

```bash
cd /Users/nikola.mandic/SimPic
npm install
```

#### 2. Install EAS CLI (Expo Application Services)

```bash
npm install -g eas-cli
```

#### 3. Login to Expo

```bash
eas login
```

If you don't have an account, create one at [expo.dev](https://expo.dev)

#### 4. Configure EAS Build

```bash
eas build:configure
```

This will create an `eas.json` file.

#### 5. Build Development APK

```bash
eas build --profile development --platform android
```

This will:
- Upload your code to Expo's servers
- Build a custom development APK with all native modules
- Take about 10-20 minutes first time
- Give you a download link when done

#### 6. Install on Your Phone

When the build completes:
1. Click the download link (or find it in your Expo dashboard)
2. Download the APK to your phone
3. Install it (enable "Install from unknown sources" if prompted)

#### 7. Run the Development Server

```bash
npm start --dev-client
```

Or:

```bash
npx expo start --dev-client
```

#### 8. Connect Your Phone

1. Open the development build app on your phone
2. Scan the QR code from your terminal
3. The app will load with **full face detection**! 🎉

---

## Troubleshooting

### "Unable to connect"
- Make sure phone and computer are on the same WiFi
- Try using tunnel mode: `npm start --tunnel`

### "Face detection not working"
- You must use a development build, not Expo Go
- Rebuild with: `eas build --profile development --platform android`

### Build fails
- Make sure you're logged in: `eas whoami`
- Check your app.json is valid
- Review build logs in Expo dashboard

### Permission issues
- Grant camera and storage permissions when prompted
- Check Settings > Apps > SimPic > Permissions

---

## Development Workflow

Once set up, your workflow is:

1. **Edit code** in your IDE
2. **Save** - app will hot reload automatically
3. **Shake phone** to open dev menu if needed
4. **Rebuild only when changing native dependencies**

---

## Alternative: USB Connection (No WiFi needed)

If you have issues with WiFi:

1. Enable USB debugging on your phone
2. Connect via USB
3. Run: `adb reverse tcp:8081 tcp:8081`
4. Then: `npm start --dev-client`

---

## Production Build (For Distribution)

When you're ready to share with others:

```bash
# Create production APK
eas build --profile production --platform android

# Or create an AAB for Play Store
eas build --profile production --platform android --local
```

---

## Next Steps After Testing

Once you confirm the foundation works:
1. Test face detection with different faces
2. Verify photos save to gallery
3. Check performance (should be ~30fps camera, 5fps face detection)
4. Ready to build Phase 2 features! 🚀

