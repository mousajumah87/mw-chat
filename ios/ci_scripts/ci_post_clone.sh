#!/bin/bash
set -euo pipefail

echo "🔥🔥🔥 XCODE CLOUD: ci_post_clone.sh START 🔥🔥🔥"
echo "PWD: $(pwd)"
echo "CI: ${CI:-}"
echo "XCODE_VERSION: ${XCODE_VERSION:-}"
echo "DEVELOPER_DIR: ${DEVELOPER_DIR:-}"

# ----------------------------
# 1) Ensure Flutter is available
# ----------------------------
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter not found. Installing (stable)..."
  git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
  export PATH="$HOME/flutter/bin:$PATH"
fi

flutter --version

# Precache iOS artifacts (helps on clean CI machines)
flutter precache --ios

# ----------------------------
# 2) Flutter deps + generate iOS config
# ----------------------------
echo "Running flutter pub get..."
flutter pub get

# Ensure ios/Flutter/Generated.xcconfig exists (this is the file your build is missing)
# --config-only is fast and specifically meant for CI/Xcode integration
echo "Generating iOS config (flutter build ios --config-only)..."
flutter build ios --config-only

# Validate the file exists
if [ ! -f "ios/Flutter/Generated.xcconfig" ]; then
  echo "❌ ERROR: ios/Flutter/Generated.xcconfig was not created."
  echo "Listing ios/Flutter:"
  ls -la ios/Flutter || true
  exit 1
fi

echo "✅ Found ios/Flutter/Generated.xcconfig"

# ----------------------------
# 3) Ensure CocoaPods is available (NO sudo on Xcode Cloud)
# ----------------------------
if ! command -v pod >/dev/null 2>&1; then
  echo "CocoaPods not found. Installing with --user-install (no sudo)..."
  gem install cocoapods -N --user-install
  # Add Ruby user gem bin to PATH
  export PATH="$HOME/.gem/ruby/$(ruby -e 'print RUBY_VERSION')/bin:$PATH"
fi

pod --version

# ----------------------------
# 4) Install pods (this generates Pods-Runner xcconfigs + xcfilelists)
# ----------------------------
echo "Running pod install..."
cd ios

# Clean stale pods state (safe + often fixes CI pod weirdness)
rm -rf Pods
rm -f Podfile.lock

pod repo update
pod install --repo-update

# Validate pod-generated files that your error mentions
if [ ! -d "Pods/Target Support Files/Pods-Runner" ]; then
  echo "❌ ERROR: Pods-Runner support files not created."
  ls -la "Pods/Target Support Files" || true
  exit 1
fi

echo "✅ CocoaPods installed and Pods support files generated."

cd ..

echo "🔥🔥🔥 XCODE CLOUD: ci_post_clone.sh DONE 🔥🔥🔥"
