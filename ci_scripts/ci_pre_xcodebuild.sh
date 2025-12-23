#!/bin/bash
set -euo pipefail

echo "=== Xcode Cloud: PRE-XCODEBUILD (Flutter) ==="
echo "PWD: $(pwd)"
ls -la

# Install Flutter (stable)
if [ ! -d "$HOME/flutter" ]; then
  echo "Cloning Flutter..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi
export PATH="$HOME/flutter/bin:$PATH"

flutter --version

# Flutter deps
flutter pub get

# Generate Generated.xcconfig
flutter build ios --no-codesign

echo "Check Generated.xcconfig..."
ls -la ios/Flutter || true
test -f ios/Flutter/Generated.xcconfig

# Pods
cd ios
pod repo update
pod install
cd ..

echo "=== PRE-XCODEBUILD done ==="

