---
name: verify
description: Build, run, and drive the Lumi Flutter app on the iOS simulator to verify changes at the UI surface.
---

# Verifying the Lumi Flutter app

## Build + launch (iOS simulator)
```bash
xcrun simctl list devices available            # "x1 17PM" (iPhone 17 Pro Max, iOS 26.3) is the E2E sim
xcrun simctl boot <UDID> && open -a Simulator
flutter run -d <UDID> --dart-define-from-file=.dart_define.json --debug
```
Run `flutter run` in the background and wait for "Flutter run key commands" in the log. Debug build connects to PROD (lumi-ninc-au) — avoid destructive writes outside the demo school.

## Logins (seeded, no MFA — App Store review accounts, demo school)
- Teacher: `review.teacher@lumi-reading.com` / `LumiReview2026!`
- Parent: `review.parent@lumi-reading.com` / `LumiReview2026!`
(Source of truth: docs/app-store/app-review-notes.md)

## Screenshots
```bash
xcrun simctl io <UDID> screenshot out.png      # device pixels; iPhone 17 PM = 1320x2868 (3x of 440x956 pt)
```

## Driving the UI
Preferred: ask the user to drive and confirm (they've requested this; automation keystrokes can land in the wrong field).
If automating anyway: a CGEvent click helper mapping device points → Simulator window lives at scratchpad `simclick.swift` pattern (window found via CGWindowList, scale = windowWidth/440); type via `osascript -e 'tell application "System Events" to keystroke "..."'` after `tell application "Simulator" to activate`. Click a field FIRST and verify focus with a screenshot before typing — keystrokes went to the wrong field once.

## Gotchas
- ~38 pre-existing `flutter test` failures need the Firebase emulator — not regressions.
- Widget configuration (WidgetConfigurationIntent) silently broken on simulator — needs a real device.
- MFA login can't be tested in debug builds (appVerificationDisabledForTesting masks the phone hint).
