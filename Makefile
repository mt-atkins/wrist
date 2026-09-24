.PHONY: bootstrap project open test register beta clean

bootstrap:            ## Install XcodeGen + fastlane
	brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
	bundle install
	@test -f Config/Local.xcconfig || cp Config/Local.xcconfig.example Config/Local.xcconfig
	@echo "→ Put your Team ID in Config/Local.xcconfig"

project:              ## Generate Wrist.xcodeproj from project.yml
	xcodegen generate

open: project         ## Generate and open in Xcode
	open Wrist.xcodeproj

test: project         ## Run unit tests on the iPhone simulator
	xcodebuild test -project Wrist.xcodeproj -scheme Wrist \
		-destination 'platform=iOS Simulator,name=iPhone 17'

register:             ## Create bundle IDs + App Store Connect record (needs fastlane/.env)
	bundle exec fastlane register

beta:                 ## Ship a TestFlight build
	bundle exec fastlane beta

clean:
	rm -rf Wrist.xcodeproj DerivedData build
