#!/bin/bash
# Quick script to add Flutter to PATH for current session
# Usage: source use_flutter.sh

export PATH="$PATH:$HOME/flutter/bin"
echo "Flutter added to PATH for this session"
echo "Flutter version:"
flutter --version | head -1
