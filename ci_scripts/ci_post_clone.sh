#!/bin/bash
set -euo pipefail

echo "🔥🔥🔥 CI POST CLONE SCRIPT IS RUNNING 🔥🔥🔥"
echo "PWD: $(pwd)"
echo "CI COMMIT: ${CI_COMMIT:-unknown}"

# -------- Flutter setup --------
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
else
  echo "Flutter found: $(which flutter)"
fi

flutter --version
flutter precache --ios || true

# -------- Get Dart deps --------
flutter pub get

# -------- Generate iOS Flutter config (creates ios/Flutter/Generated.xcconfig) --------
# Prefer config-only (fast). If not supported, fallback to a no-codesign build.
set +e
flutter build ios --config-only
CONFIG_ONLY_RC=$?
set -e

if [ $CONFIG_ONLY_RC -ne 0 ]; then
  echo "flutter build ios --config-only not supported or failed; falling back..."
  flutter build ios --release --no-codesign
fi

# Confirm Generated.xcconfig exists
if [ ! -f "ios/Flutter/Generated.xcconfig" ]; then
  echo "ERROR: ios/Flutter/Generated.xcconfig still missing"
  ls -la ios/Flutter || true
  exit 1
fi

echo "Generated.xcconfig OK ✅"

# -------- CocoaPods --------
cd ios

# Xcode Cloud usually has Ruby + CocoaPods already, but keep it safe:
if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods not found. Installing..."
  sudo gem install cocoapods -N
fi

pod --version
pod repo update || true
pod install --verbose

# Confirm Pods xcfilelists exist (your exact failure)
if [ ! -f "Pods/Target Support Files/Pods-Runner/Pods-Runner-frameworks-Release-input-files.xcfilelist" ]; then
  echo "ERROR: Pods xcfilelist still missing after pod install"
  find Pods/Target\ Support\ Files/Pods-Runner -maxdepth 1 -type f -name "*.xcfilelist" -print || true
  exit 1
fi

echo "Pods OK ✅"
