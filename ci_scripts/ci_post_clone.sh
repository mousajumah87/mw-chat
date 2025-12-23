#!/bin/bash
set -euo pipefail

echo "🔥🔥🔥 CI POST CLONE SCRIPT IS RUNNING 🔥🔥🔥"
echo "CI COMMIT: $(git rev-parse HEAD)"
pwd
ls -la

# ---- Ensure Flutter exists ----
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version

# ---- Flutter deps ----
flutter pub get
flutter precache --ios

# ---- Generate iOS Flutter build settings (creates ios/Flutter/Generated.xcconfig) ----
# This is critical for Xcode Cloud builds.
flutter build ios --release --no-codesign

# ---- CocoaPods ----
cd ios

# Make sure Podfile exists here
ls -la
if [ ! -f Podfile ]; then
  echo "ERROR: ios/Podfile not found. Are you in the right workspace?"
  exit 1
fi

# Pod install
pod --version || true
pod repo update
pod install --repo-update

echo "✅ Done: post-clone"
