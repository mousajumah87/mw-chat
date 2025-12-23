#!/bin/bash
set -euo pipefail

echo "=== Xcode Cloud: ci_pre_xcodebuild.sh ==="
cd "$(git rev-parse --show-toplevel)"

# Make sure Flutter generated configs exist
if [ ! -f "ios/Flutter/Generated.xcconfig" ]; then
  echo "Generated.xcconfig missing -> flutter pub get"
  flutter pub get
fi

# Make sure Pods exist (xcfilelists)
if [ ! -d "ios/Pods" ]; then
  echo "Pods missing -> pod install"
  cd ios
  pod install --repo-update
  cd ..
fi

echo "=== Done: ci_pre_xcodebuild.sh ==="
