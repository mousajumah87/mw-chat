#!/bin/bash
set -euo pipefail

echo "=== Xcode Cloud: Post-clone (Flutter) ==="
echo "PWD: $(pwd)"

# ---- Install Flutter (stable) into HOME if not present ----
if [ ! -d "$HOME/flutter" ]; then
  echo "Cloning Flutter..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
fi

export PATH="$HOME/flutter/bin:$PATH"

flutter --version

# ---- Flutter deps ----
flutter pub get

# ---- Generate iOS Flutter configs (creates ios/Flutter/Generated.xcconfig) ----
flutter build ios --no-codesign

# ---- CocoaPods ----
cd ios
pod repo update
pod install
cd ..

echo "=== Post-clone done ==="

