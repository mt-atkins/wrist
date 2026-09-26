#!/bin/sh
# Xcode Cloud: runs after the repo is cloned, before the build.
# Wrist.xcodeproj is generated from project.yml and not committed, so create it here.
set -eu

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Every TestFlight upload needs a unique, increasing build number.
if [ -n "${CI_BUILD_NUMBER:-}" ]; then
    sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$CI_BUILD_NUMBER\"/" project.yml
fi

# Signing team: set WRIST_TEAM_ID as an environment variable on the workflow.
if [ -n "${WRIST_TEAM_ID:-}" ]; then
    echo "DEVELOPMENT_TEAM = $WRIST_TEAM_ID" > Config/Local.xcconfig
fi

brew install xcodegen
xcodegen generate
