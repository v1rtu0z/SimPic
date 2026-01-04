# APK Build Guide

## One-Time Setup

### Step 1: Install Java
```bash
brew install --cask temurin
```

### Step 2: Setup Android SDK
```bash
npm run setup:android
```

This will:
- Install Android SDK components
- Accept licenses
- Configure environment variables

### Step 3: Restart Terminal
```bash
source ~/.zshrc
```

## Building APK

### Build Debug APK (No Expo account needed!)
```bash
npm run build:apk
```

This will:
1. Generate Android native code (if needed)
2. Build the APK
3. Output: `simpic-debug.apk` in project root

**Build time:** ~3-5 minutes for first build, ~1-2 minutes for subsequent builds

## Installing on Device

### Option 1: Manual Transfer
1. Copy `simpic-debug.apk` to your device
2. Install the APK

### Option 2: ADB Install (if device is connected via USB)
```bash
npm run install:apk
```

## Development Workflow

### After Installing APK on Device:

1. **Start dev server:**
   ```bash
   npm run start:dev
   ```

2. **Open app on your device** - it will connect to your dev server

3. **Make changes** - app will hot reload automatically!

### When to Rebuild APK:
- ❌ **JS/React changes** - No rebuild needed, hot reloading works!
- ✅ **Adding new native dependencies** - Rebuild required
- ✅ **Changing app.json config** - Rebuild required

## Troubleshooting

### "ANDROID_HOME not set"
Run: `source ~/.zshrc` or restart terminal

### "Java not found"
Install Java: `brew install --cask temurin`

### Build errors
Try clean build:
```bash
npm run prebuild
npm run build:apk
```

## File Locations

- APK: `simpic-debug.apk` (project root)
- Full APK path: `android/app/build/outputs/apk/debug/app-debug.apk`

