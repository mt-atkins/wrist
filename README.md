# Wrist

**An AI pin that's already on your wrist.** A Distyll Apple Watch app with an iPhone companion: capture a thought, keep the original, extract suggested actions, and ask about your captures. No additional hardware, account, subscription, or third-party AI backend.

Bundle IDs: `com.distyll.wrist` and `com.distyll.wrist.watchkitapp`.

## MVP

- **Watch capture:** tap the reactive orb to record; tap again to finish. A separate text button supports system dictation/scribble.
- **iPhone capture:** voice recording plus a typed-note sheet (also usable with keyboard dictation).
- **Capture inbox:** search original transcripts, summaries and tags; play original audio; check suggested actions; delete; share Markdown to Notes and other apps.
- **On-device processing:** Speech transcription, then Apple Foundation Models for summaries/actions when Apple Intelligence is available. Local extraction and keyword search are explicitly labelled when the model is unavailable or fails.
- **Ask:** retrieves relevant captures across the inbox, including older ones. Treat generated answers and to-dos as suggestions and check the original.
- **Reminders export:** initiated by your button tap; stable action identifiers prevent duplicate exports when tapped again.
- **Durable Watch delivery:** audio and text remain in the local outbox until the iPhone acknowledges saving them. Retries are deduplicated; deleted captures cannot be resurrected by a late retry.
- **Shortcuts:** the Watch capture intent opens the app. Keep Wrist in the foreground while recording.

## Run locally — no App Store registration needed

Requirements: a Mac, **Xcode 26+**, iOS 26+ simulator/device, watchOS 10+ companion, and XcodeGen. Prefer a stable Xcode rather than a beta selected globally.

```sh
brew install xcodegen  # if needed; Fastlane is NOT required for local testing
git clone https://github.com/mt-atkins/wrist.git
cd wrist
git switch hermes/finish-wrist-mvp
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
make open
```

In Xcode:

1. Choose **Wrist** → an iPhone simulator → Run.
2. Tap the **new-note icon at top left**. Try: `Remember to buy coffee tomorrow. I need to book the dentist.` Save, inspect the summary/actions, then search for coffee.
3. Quit and relaunch: the capture should remain. Open its detail to share or delete.
4. For Watch, create a paired iPhone/Apple Watch simulator in Xcode's Devices and Simulators, then run **WristWatch** on that Watch.
5. The empty inbox also has an explicitly labelled **sample capture** for exploring the UI.

For **your real iPhone and Watch**, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`, set your Developer Team, choose the connected iPhone and Run. Automatic signing must be available in Xcode. Run the Watch scheme on the paired Watch if it is not installed automatically. The team config is git-ignored; do not commit it.

**Best first test is a short thought, not a long meeting.** Speech model availability and microphone behavior vary by device/language. Simulator text flows work without microphone or Apple Intelligence. Test actual voice recognition, Bluetooth/background transfer and Apple Intelligence on real devices before trusting them for important recordings.

## Verification

```sh
make verify TEST_DESTINATION='platform=iOS Simulator,name=YOUR SIMULATOR NAME'
# Or: platform=iOS Simulator,id=YOUR-SIMULATOR-UUID
```

This generates the Xcode project, builds both simulator apps, and runs unit tests plus an end-to-end UI test. It does **not** sign, upload or submit anything. Logs/results are in `build/`. CI repeats this on pull requests and manual dispatch.

Coverage includes corruption preservation, failed writes/deletes, legacy archive migration, outbox identity, duplicate delivery/deletion tombstones, retrieval of older relevant notes, conservative action extraction, pending recording recovery, provenance, and UI create → relaunch → search → delete.

## Brand

Wrist uses the Distyll house style shared with Baseline, Notch and Loyal. The tokens and components live in `Shared/Theme.swift`.

- **Colour:** graphite surfaces (`#111316` → `#24282E`) with one-pixel `#343941` lines. **Distyll orange `#FF5A1F`** is the only signal colour and marks the current action, such as the orb, the primary buttons and open to-dos. Blue, green, amber and red are only used to show status.
- **Type:** SF Pro for words and SF Mono for measurements (times, durations, counts, section labels). The wordmark is **Wrist.** with an orange full stop, like **Notch.**.
- **Shape:** flat panels with a 14 pt radius, controls with 10 pt and tags with 4 pt. Depth comes from tone, not shadows. The only glow is on the orange orb.
- **Icon:** a graphite gradient with faint scan lines, white rounded waveform bars and one glowing orange bar.

## Privacy and honest boundaries

- Wrist has **no general read access to Apple Notes**. Export uses the system share sheet.
- Captures and audio are stored in the app's local sandbox. Watch delivery goes to its paired iPhone. No analytics or third-party inference service is included.
- The app's audio-file transcription **requires on-device recognition**. If unavailable it shows an error and retains the recording; it does not silently send it to a server. System keyboard/Watch dictation is Apple's separate service and follows your system settings.
- Recording stops on backgrounding or interruption; partial audio is handed to persistence/transfer. This is not always-on or covert recording. Obtain consent when recording other people.
- No iCloud sync or cross-device backup is implemented by Wrist. Uninstalling the app removes its sandbox; system backups depend on your settings. A force kill during an active recording is not guaranteed to recover that unfinished capture.
- Watch's mirrored inbox is the newest 20 captures, further reduced if needed to fit WatchConnectivity's size limit. Full originals remain on iPhone.
- "Ask" is a single-question retrieval flow, not a durable chat history or exhaustive semantic search. On a simulator the fallback returns labelled matching excerpts, not AI-generated answers. The Apple model can still make mistakes.
- Long audio, model-download failure, permission denial, actual device pairing and background delivery require hardware testing. A simulator build is not evidence those paths are certified.

## Apple registration and TestFlight

Both bundle identifiers have been registered and read back in the existing personal Apple Developer account. **The App Store Connect app record still needs creation through an authenticated App Store Connect session.** The public API rejected app creation (`/v1/apps` does not support CREATE); bundle registration is not the same as app-record creation.

In App Store Connect → My Apps → New App:

- Platform: iOS (the Watch app is embedded, not a second store listing)
- Name: **Wrist by Distyll** (subject to Apple's availability check)
- Primary language: English (U.K.)
- Bundle: `com.distyll.wrist`
- SKU: `distyll-wrist`

Fastlane's registration lane is supplied for an authenticated Apple ID session:

```sh
bundle install
cp fastlane/.env.example fastlane/.env  # local credentials only
make register
```

`make beta` is a **separate release action**, requiring app-record completion, signing/profiles and credentials. No TestFlight upload or App Review submission is implied by this MVP. Review privacy declarations, metadata and physical-device test results before release.

## Xcode Cloud

`ci_scripts/ci_post_clone.sh` installs XcodeGen and generates `Wrist.xcodeproj` on every Xcode Cloud build, because the project isn't committed. It also stamps `CI_BUILD_NUMBER` as the build number.

One-time setup (needs the App Store Connect app record above):

1. On a Mac, run `make open`, then choose **Product → Xcode Cloud → Create Workflow** and pick the **Wrist** product and scheme.
2. Grant Xcode Cloud access to `mt-atkins/wrist` on GitHub when asked.
3. In the workflow:
   - Start condition: branch changes on `main`.
   - Action: **Archive – iOS**, scheme `Wrist` (the Watch app is embedded).
   - Post-action: **TestFlight Internal Testing**.
   - Add the environment variable `WRIST_TEAM_ID` with your Team ID.
4. Push to `main` (or start a build manually), then submit the processed build for review from App Store Connect.

## Structure

```
Shared/        Models, persistence primitives, recorder, orb, local extraction
Wrist/         iPhone app, processing, Watch receiver and UI
WristWatch/    Watch app, durable outbox, inbox, ask and App Intent
WristTests/    Unit/regression tests
WristUITests/  End-to-end simulator test
project.yml    XcodeGen project definition
scripts/       Repeatable local verification
fastlane/      Explicit registration/release lanes
```
