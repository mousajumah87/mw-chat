#!/bin/bash
set -euo pipefail

echo "🔥🔥 XCODE CLOUD: ci_post_clone.sh START"

REPO_DIR="${CI_PRIMARY_REPOSITORY_PATH:-${CI_WORKSPACE:-$PWD}}"
cd "$REPO_DIR"

echo "Repo dir: $PWD"
ls -la

# Install Flutter if missing
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing Flutter..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version
flutter doctor -v || true

# Generate ios/Flutter/Generated.xcconfig
flutter pub get

# Install pods
cd ios
pod --version
pod repo update
pod install

echo "✅ After pod install:"
ls -la Pods || true
ls -la Flutter || true

echo "🔥🔥 XCODE CLOUD: ci_post_clone.sh END"

