.PHONY: bootstrap project open test verify register beta clean

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR
TEST_DESTINATION ?= platform=iOS Simulator,name=iPhone 17

bootstrap:            ## Install XcodeGen + fastlane
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
	bundle install

project:              ## Generate Wrist.xcodeproj from project.yml
	xcodegen generate

open: project         ## Generate and open in Xcode
	open Wrist.xcodeproj

test: project         ## Run unit tests on the iPhone simulator
	xcodebuild test -project Wrist.xcodeproj -scheme Wrist \
		-destination '$(TEST_DESTINATION)' CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO

verify:               ## Build both apps and exercise unit/UI tests (no upload)
	WRIST_TEST_DESTINATION='$(TEST_DESTINATION)' bash scripts/verify-mac.sh

register:             ## Create bundle IDs + App Store Connect record (needs fastlane/.env)
	bundle exec fastlane register

beta:                 ## Ship a TestFlight build
	bundle exec fastlane beta

clean:
	rm -rf Wrist.xcodeproj DerivedData build
