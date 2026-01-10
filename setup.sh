#!/bin/bash
# Setup script for SimPic Flutter project

echo "Setting up SimPic Flutter project..."

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter is not installed."
    echo "Please install Flutter from https://flutter.dev/docs/get-started/install"
    exit 1
fi

# Check Flutter installation
echo "Checking Flutter installation..."
flutter doctor

# Get Flutter dependencies
echo "Installing Flutter dependencies..."
flutter pub get

# Check for Android setup
if [ -d "$HOME/Android/Sdk" ]; then
    echo "Android SDK found at $HOME/Android/Sdk"
else
    echo "Warning: Android SDK not found. Please set ANDROID_HOME if needed."
fi

# Check for Java
if [ -n "$JAVA_HOME" ]; then
    echo "JAVA_HOME is set to $JAVA_HOME"
else
    echo "Warning: JAVA_HOME is not set. You may need to set it for Android builds."
fi

echo ""
echo "Setup complete!"
echo ""
echo "To run the app:"
echo "  flutter run"
echo ""
echo "To build Android APK:"
echo "  flutter build apk --release"
echo ""
