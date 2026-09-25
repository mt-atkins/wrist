# Wrist

**An AI pin that's already on your wrist.** Wrist is an Apple Watch app with an iPhone companion. No extra hardware — you tap the orb on your watch, talk, and your phone turns it into a title, summary, to-dos and tags using Apple's on-device model. Then you can ask questions about everything you've captured, from your wrist.

A Distyll app · bundle ID `com.distyll.wrist`

## What's in the MVP

| | Apple Watch | iPhone |
|---|---|---|
| **Capture** | One-tap orb that reacts to your voice, with haptics | Same orb in a floating bar, so you can test without a watch |
| **Quick note** | Dictate or scribble a text note (💬 top-left) | — |
| **Inbox** | Summaries and to-dos synced back; tick to-dos off on the watch | Search, detail view, audio playback, full transcript |
| **AI** | — | On-device transcription (Speech) → title, summary, to-dos, tags (Foundation Models) |
| **Ask** | Dictate a question; the phone answers from your captures | Chat with all your captures |
| **Export** | — | To-dos → **Reminders**; share as Markdown → Notes/Obsidian/Notion |
| **Shortcuts** | "Capture with Wrist": works from Siri, Shortcuts, or the Action button on Ultra | — |

Without Apple Intelligence (simulator, older phones), a keyword-based fallback still pulls out titles, to-dos and tags, so everything works end to end.

## How it works

```
Watch: tap orb → AVAudioRecorder (16 kHz AAC) → WCSession.transferFile ─┐
Watch: dictated note ───────────────────────────── transferUserInfo ────┤
                                                                         ▼
iPhone: MemoStore → Transcriber (SFSpeech, on-device) → Summarizer (FoundationModels @Generable)
          │
          └─ updateApplicationContext (latest 20 digests) ──► Watch inbox
Watch "Ask" ── sendMessage ──► iPhone answers with LanguageModelSession ──► reply
```

```
Shared/        Model, audio recorder, orb UI, WatchConnectivity keys, fallback heuristics
Wrist/         iPhone app (store, pipeline, UI)
WristWatch/    watchOS app (capture, inbox, ask, App Intent)
WristTests/    Unit tests
project.yml    XcodeGen spec (the .xcodeproj is generated and not committed)
fastlane/      App Store Connect registration + TestFlight
```

## Brand

Wrist uses the Distyll house style shared with Baseline, Notch and Loyal. The tokens and components live in `Shared/Theme.swift`.

- **Colour:** graphite surfaces (`#111316` → `#24282E`) with one-pixel `#343941` lines. **Distyll orange `#FF5A1F`** is the only signal colour and marks the current action, such as the orb, the primary buttons and open to-dos. Blue, green, amber and red are only used to show status.
- **Type:** SF Pro for words and SF Mono for measurements (times, durations, counts, section labels). The wordmark is **Wrist.** with an orange full stop, like **Notch.**.
- **Shape:** flat panels with a 14 pt radius, controls with 10 pt and tags with 4 pt. Depth comes from tone, not shadows. The only glow is on the orange orb.
- **Icon:** a graphite gradient with faint scan lines, white rounded waveform bars and one glowing orange bar.

## Run it locally

You'll need a Mac with Xcode 26+ and Homebrew.

```bash
make bootstrap        # installs XcodeGen + fastlane, creates Config/Local.xcconfig
# put your Team ID in Config/Local.xcconfig  (DEVELOPMENT_TEAM = ABCDE12345)
make open             # generates Wrist.xcodeproj and opens it
```

**Simulator (fastest):** Choose the `Wrist` scheme and an iPhone 17 simulator, then Run. Tap **Try a sample capture** to see the AI pipeline, or tap the orb to record. To try the watch, run the `WristWatch` scheme on the Apple Watch simulator that's paired with that iPhone. Watch↔phone transfer does work between paired simulators, but it can be flaky, so test on real devices before you trust it.

**On your devices:** Plug in your iPhone, choose the `Wrist` scheme, and Run. Xcode installs the watch app too. If it doesn't, open the Watch app on your iPhone → Wrist → Install. Apple Intelligence has to be turned on for the full AI summaries (iPhone 15 Pro or newer).

**Tests:** `make test`

## App Store Connect

```bash
cp fastlane/.env.example fastlane/.env   # fill in Apple ID + team IDs
make register                            # creates bundle IDs + the App Store Connect app record
make beta                                # archive + upload to TestFlight
```

The public app name has to be unique across the App Store. `Wrist` is almost certainly taken, so the default is **Wrist by Distyll**. You can change it with `WRIST_APP_NAME`.

## Next ideas

- Complication or Smart Stack widget to start a capture in one tap
- Long-form transcription with `SpeechAnalyzer` + live captions on the watch
- Daily "what you said today" digest notification
- iCloud sync (SwiftData + CloudKit) and Mac app
- Speaker labels for meetings; calendar-aware titles
