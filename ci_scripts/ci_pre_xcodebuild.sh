#!/bin/bash
set -euo pipefail

echo "✅ pre-xcodebuild running"
ls -la ios/Flutter || true
ls -la ios/Pods/Target\ Support\ Files/Pods-Runner || true
