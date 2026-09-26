# MVP verification

## Executed on the Mac build machine

Toolchain: explicitly selected stable **Xcode 26.6 (17F113)**, not the globally selected beta. iOS/watchOS 26.5 paired simulators.

| Gate | Result |
|---|---|
| iPhone simulator build | `BUILD SUCCEEDED` |
| Watch simulator build | `BUILD SUCCEEDED` |
| Unit/regression suite | 24 tests, 0 failures |
| UI create → relaunch → search → detail → delete → relaunch | 1 test, 0 failures |
| Actual WatchConnectivity text delivery | PASS: a synthetic, labelled test note persisted once on iPhone; application-level ACK cleared the Watch outbox |
| Visual inspection | Both launched; iPhone empty state and Watch capture view inspected. Fixed low-contrast Watch text-note icon. |
| Git diff whitespace check | Passed |
| Credential-pattern scan of changed/untracked files | No private-key/token patterns found; local signing file ignored |
| Apple Developer registration | Both app identifiers read back successfully |
| App Store Connect app record | **Not created:** public API does not allow app CREATE; authenticated UI/Apple ID session required |
| TestFlight / App Review | Not attempted |

The transport smoke test inserts an explicitly synthetic fixture into the **simulator** Watch outbox, then exercises the real running apps and WatchConnectivity. It is not evidence of microphone recording or physical-device radio/background performance.

Reproduce build/tests with `make verify TEST_DESTINATION='platform=iOS Simulator,name=YOUR SIMULATOR'`.

After installing both built apps on booted paired simulators, reproduce delivery with:

```sh
python3 scripts/watch-transport-smoke.py --phone IPHONE_SIMULATOR_UUID --watch WATCH_SIMULATOR_UUID
```

Logs and XCTest result bundles stay in `build/`; test runs don't need signing or Apple credentials. Apple's metadata tool prints an expected "No AppIntents.framework dependency found" warning for targets without App Intents; this did not fail compilation/testing.

## Before trusting real recordings

- [ ] On actual iPhone/Watch, grant microphone and Speech access; capture a short thought and compare transcript with original audio.
- [ ] Deny/revoke permissions; verify an actionable error, no silent upload, and original audio retained.
- [ ] Capture with iPhone unavailable, reconnect, check one copy and delivered acknowledgement.
- [ ] Lower wrist/background app mid-capture; verify partial recording saves/queues. This MVP is foreground recording, not continuous listening.
- [ ] Enable Apple Intelligence on a supported iPhone and inspect summary/actions plus answer faithfulness.
- [ ] Check unsupported locale/model-unavailable behavior; fallback must be explicitly labelled.
- [ ] Export the same action to Reminders twice; verify only one reminder and sensible permission-denied/no-list errors.
- [ ] Test Siri/Shortcuts capture entry on hardware; OS foreground timing may require opening Wrist before recording.

Unfinished active recording recovery after a force kill, iCloud sync, long-meeting transcription, and App Store release readiness are outside the verified MVP.
