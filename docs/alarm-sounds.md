# Bundled alarm sounds

All five offline assets are in `Supershot/AlarmSounds`, copied into the app's main bundle by Xcode's synchronized app group. They are mono, 44.1 kHz, 16-bit linear PCM CAF files, each under four seconds. Both AlarmKit and macOS UserNotifications use their filenames; previews play the same files with AVAudioPlayer. The choice is stored under the `alarmSound` app-storage key, defaulting to Buzzer. Goal sounds use their existing independent preference.

## Sources and rights

- **Buzzer:** “Incorrect buzzer sound” by **u_ayf470ljcu**, supplied by Jacob on 9 November 2026 as `u_ayf470ljcu-incorrect-buzzer-sound-147336.mp3`. Source: https://pixabay.com/sound-effects/film-special-effects-incorrect-buzzer-sound-147336/ (published 24 April 2023). The source page identifies the Pixabay Content License. https://pixabay.com/service/license-summary/ and https://pixabay.com/service/terms/ were checked on 9 November 2026. The licence permits free commercial use, modification and incorporation into creative works without required attribution; it prohibits standalone redistribution. This clip is incorporated as functional alarm audio in Supershot, not offered as a sample download. Credit is retained here voluntarily. Converted to mono PCM CAF using `ffmpeg -i input.mp3 -ac 1 -ar 44100 -c:a pcm_s16le alarm-buzzer.caf`. The supplied original is not redistributed separately.
- **Whistle, Air horn, Soft chime, Electronic pulse:** original procedural compositions created for Supershot on 9 November 2026. No third-party recordings, samples, or synthesis libraries. Source and reproducible generation: `scripts/audio/generate-alarm-tones.py` (Python standard library, macOS `afconvert`). These original project assets may be redistributed with Supershot; no external attribution is required.

## Playback requirements

- AlarmKit uses ActivityKit's named alert sound, resolved from the app's main bundle: https://developer.apple.com/videos/play/wwdc2025/230/
- UserNotifications custom sounds support linear PCM in CAF and must be shorter than 30 seconds: https://developer.apple.com/documentation/usernotifications/unnotificationsound
- File names are stable and unique, prefixed `alarm-`. No network or asset copying is required at playback time.
- Settings previews are available to all users. Scheduled alarm use continues through the existing permission and Supershot Pro capability policy.

## Repeatable UI validation

Launch a Debug build with `--launch-scenario settings-alarm-sounds`. It starts on the Settings tab with Free access, an isolated temporary database, a dedicated `Supershot.SettingsAlarmSoundsScenario` defaults suite, and no system alarm or purchase side effects. It retains the live preview player and app-bundled audio. Open Alarm sound, tap each of the five rows, switch rapidly, navigate back, and relaunch with the same arguments to check the current value. The fixed scenario suite intentionally persists this choice across launches and never changes the personal defaults suite.

### Captured on 9 November 2026

Confirmed on the dedicated **Supershot L168 Alarm Sounds** simulator (iPhone 18 Pro, iOS 27.3; `FFF97644-BE08-482B-AAD7-6C0067C1E8BC`) after the final iOS build succeeded. The app launched directly into Free Settings. The captured screen shows **Alarm sound — Buzzer**, separately from Goal sounds, with the shared quarter/break explanation and existing Pro requirement. The new row and explanatory text are legible and aligned.

Confirmed install, launch and capture recipe (use the output path from the corresponding Debug build):

```sh
xcrun simctl boot FFF97644-BE08-482B-AAD7-6C0067C1E8BC
xcrun simctl install FFF97644-BE08-482B-AAD7-6C0067C1E8BC '/private/tmp/supershot-l168-derived/Build/Products/Debug-iphonesimulator/Supershot Netball.app'
xcrun simctl launch FFF97644-BE08-482B-AAD7-6C0067C1E8BC nz.lapworth.Supershot.dev --launch-scenario settings-alarm-sounds
xcrun simctl io FFF97644-BE08-482B-AAD7-6C0067C1E8BC screenshot '/Users/jacoblapworth/.codex/visualizations/2026/11/09/01a1c112-f492-7cd2-9ace-bdfc502faa79/l168-alarm-settings.png'
```

Screenshot: `/Users/jacoblapworth/.codex/visualizations/2026/11/09/01a1c112-f492-7cd2-9ace-bdfc502faa79/l168-alarm-settings.png` (inspected). Skip `boot` if the device is already running. DeviceInteraction tools were unavailable, no idb/axe fallback was installed, and CUA accessibility/screenshot requests timed out. Therefore opening the picker, tapping all five sounds, audible preview replacement, navigation back, and selection persistence across a real relaunch remain unverified through UI interaction; the Settings screenshot does not establish those behaviors.

## Hardware playback checks

With normal app entry, Supershot Pro and alarm permission enabled, choose each sound and run a short quarter and automatic break. Check both alarms while backgrounded and while the phone is locked. Change sound midway through a running timer and verify the original deadline, one alarm at each expected boundary, and the most recent selected sound. Repeat macOS notification delivery with permission enabled. Previews and unit tests do not establish actual system audio delivery; record hardware results separately before release.

## Automated validation on 9 November 2026

- iOS 27.3 / iPhone 18 Pro: 100 focused tests passed (151 runs including parameters), zero failures. Targets: SettingsFeatureTests, AppFeatureTests, GameServicesTests and SupershotTests/AlarmSoundTests. This covers all five packaged/decodable sound files, selection/reselection, persisted shared state, unchanged game timing, and ordered in-flight iOS replacements.
- Final iOS app build passed after hiding the decorative checkmark from accessibility; selected rows expose the selected trait.
- macOS 27.3 / arm64: eight MacNotificationSchedulerTests passed (nine runs including parameters), zero failures. This includes sound replacement preserving both deadlines and request IDs, capability rechecks and cancellation races. The Mac app and test bundles compiled successfully.
- Changed Swift files pass SwiftFormat; all five assets pass the PCM/duration checks above.
- These checks do not replace the UI interaction and hardware playback checks listed above.
