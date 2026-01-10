# Quick Commands Reference

## Add Flutter to PATH (Current Session Only)

```bash
export PATH="$PATH:$HOME/flutter/bin"
```

Or use the helper script:
```bash
source use_flutter.sh
```

## Add Flutter to PATH Permanently

Add to your `~/.bashrc`:
```bash
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc
```

## Common Flutter Commands

```bash
# Get dependencies
flutter pub get

# Run the app (with hot reload enabled)
flutter run

# Build Android APK
flutter build apk --release

# Check Flutter setup
flutter doctor

# List connected devices
flutter devices
```

## Hot Reload (Fast Development)

When you run `flutter run`, the app stays running and you can make changes:

**Hot Reload (preserves state):**
- Press `r` in the terminal while app is running
- Updates code changes instantly (~1 second)
- Preserves app state (variables, navigation, etc.)
- Works for: UI changes, logic changes, most Dart code

**Hot Restart (resets state):**
- Press `R` (capital R) in the terminal
- Restarts the app but keeps it running
- Resets app state
- Faster than full rebuild

**Full Rebuild (when needed):**
- Press `q` to quit, then run `flutter run` again
- Needed for: Adding dependencies, changing native code, AndroidManifest changes

### What Triggers Full Rebuild:
- Adding/removing dependencies (`pubspec.yaml`)
- Changing Android/iOS native code
- Modifying `AndroidManifest.xml` or `Info.plist`
- Changing app icons/assets structure

### What Works with Hot Reload:
- ✅ UI changes (colors, layouts, widgets)
- ✅ Logic changes (functions, calculations)
- ✅ State management changes
- ✅ Most Dart code changes

## Quick Start in This Project

```bash
cd /home/nikola/Downloads/simpic/SimPic/flutter
export PATH="$PATH:$HOME/flutter/bin"
flutter pub get
flutter run
```
