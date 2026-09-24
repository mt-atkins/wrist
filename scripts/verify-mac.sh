#!/bin/bash
# Local simulator verification only. No signing, uploads or release actions.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
: "${WRIST_TEST_DESTINATION:=platform=iOS Simulator,name=iPhone 17}"
mkdir -p build
xcodebuild -version
xcodegen generate
xcodebuild -project Wrist.xcodeproj -scheme Wrist -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/ios-build.log
xcodebuild -project Wrist.xcodeproj -scheme WristWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build 2>&1 | tee build/watch-build.log
xcodebuild -project Wrist.xcodeproj -scheme Wrist -configuration Debug \
  -destination "$WRIST_TEST_DESTINATION" -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test 2>&1 | tee build/tests.log
