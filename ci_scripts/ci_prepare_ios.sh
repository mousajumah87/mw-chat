#!/bin/bash
set -euo pipefail

echo "🚀 XCODE CLOUD IOS PREPARE STARTED"
cd "$CI_WORKSPACE/ios"

# Install Flutter if missing
if ! command -v flutter >/dev/null 2>&1; then
  echo "📦 Installing Flutter"
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version

echo "📦 Flutter pub get"
cd "$CI_WORKSPACE"
flutter pub get

echo "📦 iOS pod install"
cd ios

rm -rf Pods Podfile.lock
flutter precache --ios
pod repo update
pod install --verbose

echo "🛠 Generate Generated.xcconfig"
flutter build ios --release --no-codesign

echo "✅ XCODE CLOUD IOS PREPARE DONE"

