#!/bin/bash
set -euo pipefail

echo "🔥🔥🔥 XCODE CLOUD: ci_post_clone.sh START 🔥🔥🔥"

# Xcode Cloud checks out repo here
REPO_DIR="${CI_PRIMARY_REPOSITORY_PATH:-/Volumes/workspace/repository}"

echo "Repo dir: $REPO_DIR"
cd "$REPO_DIR"
pwd
ls -la

# Install Flutter if missing
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing (stable)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
else
  echo "Flutter already installed."
fi

export PATH="$HOME/flutter/bin:$PATH"
flutter --version

echo "Running flutter pub get..."
flutter pub get

echo "Generating iOS config (config-only)..."
flutter build ios --release --config-only

echo "✅ Checking Generated.xcconfig..."
if [[ ! -f "$REPO_DIR/ios/Flutter/Generated.xcconfig" ]]; then
  echo "❌ ERROR: $REPO_DIR/ios/Flutter/Generated.xcconfig was not created."
  echo "Listing $REPO_DIR/ios:"
  ls -la "$REPO_DIR/ios" || true
  echo "Listing $REPO_DIR/ios/Flutter:"
  ls -la "$REPO_DIR/ios/Flutter" || true
  exit 1
fi

echo "Running pod install..."
cd "$REPO_DIR/ios"

# Make sure pods are installed for Runner
pod repo update
pod install

echo "✅ Pods installed. Listing Target Support Files:"
ls -la "Pods/Target Support Files/Pods-Runner" || true

echo "🔥🔥🔥 XCODE CLOUD: ci_post_clone.sh END 🔥🔥🔥"

