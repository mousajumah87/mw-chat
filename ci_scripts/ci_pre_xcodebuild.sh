#!/bin/bash
set -euo pipefail
echo "🔥 XCODE CLOUD: ci_pre_xcodebuild.sh START"
pwd
ls -la ios/Flutter || true
ls -la ios/Pods || true
echo "🔥 XCODE CLOUD: ci_pre_xcodebuild.sh END"

