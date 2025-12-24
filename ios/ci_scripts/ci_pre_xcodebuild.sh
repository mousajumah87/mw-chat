#!/bin/bash
set -euo pipefail

echo "⚙️ XCODE CLOUD: ci_pre_xcodebuild.sh START"

# Ensure flutter is still on PATH if needed
if [ -d "$HOME/flutter/bin" ]; then
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version || true

# Sanity checks (fail early with clear output)
echo "Checking Generated.xcconfig..."
ls -la ios/Flutter/Generated.xcconfig || (echo "❌ Missing ios/Flutter/Generated.xcconfig" && exit 1)

echo "Checking Pods support files..."
ls -la "ios/Pods/Target Support Files/Pods-Runner" || (echo "❌ Missing Pods-Runner support files" && exit 1)

echo "⚙️ XCODE CLOUD: ci_pre_xcodebuild.sh DONE"
