#!/bin/bash

# Build APK script for SimPic
# This script builds a debug APK without needing Expo account

set -e

echo "🏗️  Building SimPic APK..."

# Set Java to version 21 (required for Gradle)
if [ -d "/usr/lib/jvm/java-1.21.0-openjdk-amd64" ]; then
    export JAVA_HOME="/usr/lib/jvm/java-1.21.0-openjdk-amd64"
elif [ -d "/opt/homebrew/opt/openjdk@21" ]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk@21"
elif [ -d "/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home" ]; then
    export JAVA_HOME="/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home"
fi

# Set Android SDK environment
if [ -d "$HOME/Android/Sdk" ]; then
    export ANDROID_HOME="$HOME/Android/Sdk"
elif [ -d "/usr/lib/android-sdk" ]; then
    export ANDROID_HOME="/usr/lib/android-sdk"
else
    export ANDROID_HOME=$HOME/Library/Android/sdk
fi
export PATH=$JAVA_HOME/bin:$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools:$(ls -d $ANDROID_HOME/cmdline-tools/latest/bin 2>/dev/null || ls -d $ANDROID_HOME/cmdline-tools/*/bin 2>/dev/null | head -1)

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if Android SDK is installed
if [ ! -d "$ANDROID_HOME" ]; then
    echo -e "${RED}❌ Android SDK not found at $ANDROID_HOME${NC}"
    echo "Please run: npm run setup:android"
    exit 1
fi

# Check if android directory exists, if not run prebuild
if [ ! -d "android" ]; then
    echo -e "${BLUE}📦 Running expo prebuild to generate Android project...${NC}"
    npx expo prebuild --platform android --clean
fi

# Navigate to android directory and build release APK (skip lint to avoid memory issues)
echo -e "${BLUE}🔨 Building release APK...${NC}"
cd android
./gradlew assembleRelease -x lintVitalAnalyzeRelease -x lintVitalReportRelease -x lintVitalRelease

# Check if build was successful
if [ -f "app/build/outputs/apk/release/app-release.apk" ]; then
    echo -e "${GREEN}✅ APK built successfully!${NC}"
    echo -e "${GREEN}📍 Location: android/app/build/outputs/apk/release/app-release.apk${NC}"
    
    # Get file size
    SIZE=$(du -h app/build/outputs/apk/release/app-release.apk | cut -f1)
    echo -e "${GREEN}📦 Size: $SIZE${NC}"
    
    # Copy to project root for easier access
    cp app/build/outputs/apk/release/app-release.apk ../simpic.apk
    echo -e "${GREEN}📋 Copied to: simpic.apk${NC}"
else
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

