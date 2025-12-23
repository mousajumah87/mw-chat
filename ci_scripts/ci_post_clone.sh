#!/bin/bash
echo "🔥🔥🔥 CI POST CLONE SCRIPT IS RUNNING 🔥🔥🔥"

set -euo pipefail

echo "=== Xcode Cloud: ci_post_clone.sh ==="
cd "$(git rev-parse --show-toplevel)"

# Ensure flutter exists in CI
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

# Ensure CocoaPods exists in CI
if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods not found. Installing..."
  sudo gem install cocoapods -N
fi

flutter --version
flutter pub get

cd ios
pod --version
pod install --repo-update

echo "=== Done: ci_post_clone.sh ==="
echo "CI COMMIT: $(git rev-parse HEAD)"
