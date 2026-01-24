#!/bin/bash

# SimPic iOS Setup Script
# This script automates the setup process for building SimPic on macOS.

# Set colors for better output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

set -e # Exit on error

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}       SimPic iOS Setup Script          ${NC}"
echo -e "${GREEN}==========================================${NC}"

# 1. Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌ Error: This script must be run on a Mac.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Running on macOS.${NC}"

# 2. Check for Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Error: Flutter is not installed or not in your PATH.${NC}"
    echo -e "   Please install Flutter: https://docs.flutter.dev/get-started/install/macos"
    exit 1
fi
echo -e "${GREEN}✅ Flutter found:${NC} $(flutter --version | head -n 1)"

# 3. Check for Xcode
if ! xcode-select -p &> /dev/null; then
    echo -e "${RED}❌ Error: Xcode command line tools not found.${NC}"
    echo -e "   Please install Xcode from the App Store or run: xcode-select --install"
    exit 1
fi
echo -e "${GREEN}✅ Xcode tools found.${NC}"

# 4. Check for CocoaPods
if ! command -v pod &> /dev/null; then
    echo -e "${YELLOW}⚠️ CocoaPods not found. Attempting to install...${NC}"
    if command -v brew &> /dev/null; then
        echo -e "   Installing CocoaPods via Homebrew..."
        brew install cocoapods
    else
        echo -e "   Homebrew not found. Trying 'sudo gem install cocoapods'..."
        echo -e "   (You may be prompted for your password)"
        sudo gem install cocoapods
    fi
    
    if ! command -v pod &> /dev/null; then
        echo -e "${RED}❌ Error: Could not install CocoaPods automatically.${NC}"
        echo -e "   Please install it manually: https://guides.cocoapods.org/using/getting-started.html"
        exit 1
    fi
fi
echo -e "${GREEN}✅ CocoaPods found:${NC} $(pod --version)"

# 5. Get Flutter dependencies
echo -e "\n${GREEN}------------------------------------------${NC}"
echo -e "📦 Getting Flutter dependencies..."

# Ensure we are in the project root
cd "$(dirname "$0")"

flutter pub get

# 6. Install Pods
echo -e "\n${GREEN}------------------------------------------${NC}"
echo -e "🍎 Installing CocoaPods (this may take a while)..."

if [ ! -d "ios" ]; then
    echo -e "${YELLOW}⚠️ ios directory not found. Running 'flutter create . --platforms ios'...${NC}"
    flutter create . --platforms ios
fi

cd ios

# Handle M1/M2 Mac specific CocoaPods issues if necessary
# But generally, modern Flutter handles this better now.
if ! pod install; then
    echo -e "${YELLOW}⚠️ pod install failed. Trying repo update...${NC}"
    pod install --repo-update || {
        echo -e "${RED}❌ Error: pod install failed even after repo update.${NC}"
        echo -e "   If you are on an Apple Silicon Mac (M1/M2/M3), try:"
        echo -e "   sudo arch -x86_64 gem install ffi"
        echo -e "   arch -x86_64 pod install"
        exit 1
    }
fi
cd ..

echo -e "\n${GREEN}------------------------------------------${NC}"
echo -e "${GREEN}✅ iOS Setup Complete!${NC}"
echo -e "${GREEN}------------------------------------------${NC}"
echo -e "Next Steps:"
echo -e "1. ${YELLOW}Opening Runner.xcworkspace in Xcode...${NC}"
open ios/Runner.xcworkspace
echo -e "2. In Xcode: Select 'Runner' project -> 'Runner' target -> 'Signing & Capabilities'."
echo -e "3. Select your development ${YELLOW}Team${NC}."
echo -e "4. Connect your iPhone and click the ${GREEN}Run${NC} button (Play icon)."
echo -e ""
echo -e "Happy coaching! 📸"
