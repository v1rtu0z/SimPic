#!/bin/bash

# Setup Android SDK for local APK builds
# Run this script after installing Java

set -e

echo "🔧 Setting up Android SDK..."

# Set Android SDK path
export ANDROID_HOME=$HOME/Android/Sdk
mkdir -p $ANDROID_HOME

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Check if Java is installed
if ! command -v java &> /dev/null; then
    echo -e "${RED}❌ Java not found!${NC}"
    echo "Please install Java first:"
    echo "  brew install --cask temurin"
    exit 1
fi

echo -e "${GREEN}✅ Java found: $(java -version 2>&1 | head -n 1)${NC}"

# Install SDK components
echo -e "${BLUE}📦 Installing Android SDK components...${NC}"
sdkmanager --sdk_root=$ANDROID_HOME "platform-tools" "platforms;android-35" "build-tools;35.0.0"

# Accept licenses
echo -e "${BLUE}📜 Accepting Android SDK licenses...${NC}"
yes | sdkmanager --sdk_root=$ANDROID_HOME --licenses

# Add to shell profile
SHELL_RC="$HOME/.bashrc"
if [ -f "$HOME/.zshrc" ]; then SHELL_RC="$HOME/.zshrc"; fi

if ! grep -q "ANDROID_HOME" "$SHELL_RC" 2>/dev/null; then
    echo -e "${BLUE}📝 Adding Android SDK to $SHELL_RC...${NC}"
    echo "" >> "$SHELL_RC"
    echo "# Android SDK" >> "$SHELL_RC"
    echo "export ANDROID_HOME=\$HOME/Android/Sdk" >> "$SHELL_RC"
    echo "export PATH=\$PATH:\$ANDROID_HOME/tools:\$ANDROID_HOME/platform-tools" >> "$SHELL_RC"
fi

echo -e "${GREEN}✅ Android SDK setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Restart your terminal or run: source ~/.zshrc"
echo "2. Build your APK: npm run build:apk"

