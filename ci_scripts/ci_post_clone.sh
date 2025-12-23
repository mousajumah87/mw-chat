#!/bin/bash
set -euo pipefail

echo "=== Xcode Cloud: ci_post_clone.sh ==="
cd "$(git rev-parse --show-toplevel)"

flutter --version
flutter pub get

cd ios
if [ ! -f "Podfile" ]; then
  echo "ERROR: ios/Podfile not found"
  ls -la
  exit 1
fi

pod --version
pod install --repo-update

echo "=== Done: ci_post_clone.sh ==="
