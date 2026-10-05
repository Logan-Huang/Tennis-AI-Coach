# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Tennis Strokedex (Xcode target and product name still "Tennis AI Coach" / "TennisAI: Swing Coach") is a SwiftUI iOS 26 app. It analyzes tennis video on the device: it finds the player, runs Apple Vision body pose on every frame, detects strokes from wrist speed and the sound of the ball, labels each stroke as a serve, forehand or backhand, and scores it against fixed standards. There's no ball, court or racquet detection, and no trained classifier: everything comes from pose and audio, using hand-tuned rules. `README.md` has the user-facing description and the metrics glossary.

## Commands

`xcodebuild`/`xcrun` need `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` on this Mac, because the active developer dir is the Command Line Tools.

```bash
# Build (device SDK)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project "Tennis AI Coach.xcodeproj" -scheme "Tennis AI Coach" \
  -destination 'generic/platform=iOS' -configuration Debug

# Build for a simulator: -destination 'id=<sim udid>', then xcrun simctl install/launch
# (bundle id LoganHuang.Tennis-AI-Coach)
```

There is **no XCTest target**. Adding one was deliberately avoided, because it means hand-editing the target setup in `project.pbxproj`. The engine is verified with three macOS command-line harnesses in `Scripts/`, each built by compiling `main.swift` together with the engine sources. Each README has the exact `swiftc` line:

| Harness | Use it when | Input |
|---|---|---|
| `Scripts/detection-eval/` | Any change to tracking, pose, audio, wrist motion or stroke detection | Video clips → writes `AnalysisResult` JSON; `score.py <outdir>` scores it against `labels.json` |
| `Scripts/scoring-eval/` | Any change to `FormBands`, `ShotScorer`, or `SwingKinematics` | `AnalysisResult` JSONs (from detection-eval or a session saved in the app) |
| `Scripts/scorer-harness/` | Sanity checks on scorer invariants (0–100 range, NaN renormalization, no px/s or mph in text) | `IMG_7145_analysis.json` at the repo root (committed on purpose; don't gitignore it) |

The full-engine harnesses compile every file in `Engine/*.swift` and `Engine/Models/*.swift` **except** `AnnotatedVideoExporter.swift` (it imports UIKit) and `AnalysisService.swift` (it references the exporter). Detection-eval environment flags: `ARM=right|left` stands in for the profile's racquet hand; `NOAUDIO=1` tests the pose-only fallback.

**Vision body pose does not run in the iOS Simulator.** `VNDetectHumanBodyPoseRequest` fails at setup (Vision error 9), so every clip ends in the "Couldn't track a player" empty state. That's expected, not a bug. Real analysis needs a physical iPhone, or the macOS harnesses above, where Vision works.

Debug launch arguments for checking UI in the Simulator, where taps and swipes can't be injected: `-activeProfile <name>`, `-autoOpenSession <uuid|newest>`, `-autoOpenShotDetail`, `-autoOpenExport`, `-autoCompareLatest`, `-reportScrollBottom`, `-autoOpenPlayers`, `-onboardingPage <n>`. They're read in `ContentView`, `HomeView`, `ResultsView` and `OnboardingView`.

### Releasing

- Bump `CURRENT_PROJECT_VERSION` for every upload. App Store Connect refuses a build number it has already seen for that version.
- Pushes to `main` usually trigger Xcode Cloud, which archives and uploads with its own build numbers. It has silently skipped pushes before, so check that a run actually started.
- Manual upload: `xcodebuild archive -configuration Release -destination generic/platform=iOS -allowProvisioningUpdates`, then `-exportArchive` with ExportOptions `method=app-store-connect`, `destination=upload`, `signingStyle=automatic`, `manageAppVersionAndBuildNumber=false`.
- An upload that "succeeds" can still be rejected during Apple's processing (Invalid Binary). Get the ITMS code from App Store Connect or Apple's email before changing anything. Two traps already hit in 1.3:
  - **ITMS-91064**: a privacy manifest that sets `NSPrivacyTracking` to true needs a non-empty `NSPrivacyTrackingDomains`. The app's `PrivacyInfo.xcprivacy` mirrors AppsFlyer's `att.*` domains; keep them in sync when updating the SDK.
  - AppsFlyer must come from the **`AppsFlyerFramework-Dynamic`** package (product `AppsFlyerLib-Dynamic`, module `AppsFlyerLib`). The default `AppsFlyerFramework` package is static-only, and Xcode then embeds a stub framework with `MinimumOSVersion 100.0`.
- The AppsFlyer dev key lives in the git-ignored `Tennis AI Coach/AppsFlyerKeys.plist`. Xcode Cloud writes it from the `APPSFLYER_DEV_KEY` secret (`ci_scripts/ci_post_clone.sh`). Builds without it skip the SDK.

## Architecture

### Project setup that affects every edit

- **Synchronized folder group**: any `.swift` file under `Tennis AI Coach/` compiles automatically; don't edit `project.pbxproj` to add files.
- **Info.plist** is generated. Permission strings and the display name are `INFOPLIST_KEY_*` build settings. Keys that build settings can't express (SKAdNetwork/AdAttributionKit postback endpoints) live in `Tennis AI Coach-Info.plist` at the repo root, outside the synchronized folder so it isn't copied in as a resource.
- **Default actor isolation is `MainActor`** (`SWIFT_DEFAULT_ACTOR_ISOLATION`, Swift 5 mode, approachable concurrency). Everything in `Engine/` is pure computation and marked `nonisolated`. New engine types, statics and extensions need `nonisolated` too, or they become main-actor-bound and warn. Analysis runs off the main actor.
- SourceKit shows phantom "Cannot find type in scope" errors on cross-file references; trust only the `xcodebuild` result.

### Analysis pipeline (`Engine/`)

The UI talks to the `AnalysisEngine` protocol, injected through `\.analysisEngine` (`VisionAnalysisEngine` in the app, `MockEngine` in previews). `AnalysisPipeline.run` runs these stages in order:

1. `VideoSource` (AVAssetReader, ~30 samples/s via `AnalysisConfig.stride`) and `AudioOnsets` (soundtrack transients = candidate ball contacts).
2. `PlayerTracker`, in two passes:
   - `SubjectLocator` runs the person detector ~10 times a second and keeps the track with the most body in frame.
   - `SubjectTracker` runs pose on a square region around that player every frame. Region results come back normalized to the region and are converted back.
3. `CoordinateSpace` converts **once**, from Vision's normalized, bottom-left-origin points in the *oriented* frame to pixel, top-left-origin coordinates. The reader does not apply `preferredTransform`; orientation is derived from it. Every metric downstream assumes pixel space with a top-left origin.
4. `WristTrackingGate` drops wrist positions Vision invented. `WristMotion` gives wrist speed relative to the hips in **torso lengths per second**. `LimbReference` sets knee and elbow angles to NaN when a limb is foreshortened (< 80% of full length). `MetricsComputer` produces one `FrameMetrics` row per frame.
5. `StrokeDetector`: a heard onset counts as a stroke when a wrist reaches ≥ 6 T/s within ±0.25 s *and* the hand is moving ≥ 3.5 T/s at the sound. A wrist-only peak ≥ 7 T/s also counts. Strokes are at least 1 s apart. The file header explains every constant.
6. `StrokeAnatomy`: decides the stroke kind from hand positions at contact (overhead → serve, wrists together → two-handed backhand, side of the hips → forehand or backhand, else `.groundstroke`). Also measures reach, finish and serve knee load.

### Scoring and coaching are computed at display time

`SwingKinematics` (shoulder-turn path, hip drop and leg drive, trunk share, serve shoulder tilt, hand speed), `ShotScorer`, `Narrative`, `ProgressEngine` and `CompareEngine` all run when a screen shows them; their output is **never persisted**. Changing them re-grades every saved session, so no migration is needed. Key properties:

- **Standards**: every standard is in `FormBands` (`CoachingEngine.swift`), with its research source in the comments. Fixed standards, never relative to the session.
- **Components**: weights are per stroke kind and renormalize over the components that could be measured.
- **Power cap**: a shot can't score more than `ShotScorer.powerMargin` (12) above its power components (speed, turn, knee, tilt), or 70 if none were measurable.
- **Tracking gate**: a shot with < 0.5 joint coverage or < 3 surviving components is ungraded (NaN), not given a guessed number.

What *is* persisted is `AnalysisResult`: frames, poses, strokes, summary and coaching, saved as NaN-safe JSON (`AnalysisCoders`). `engineVersion` marks what produced it: `nil` is the pre-September-2026 engine (pixel speeds, no stroke kinds); `2` is current. New stored fields must be Optional so old sessions still decode. Bump `AnalysisResult.currentEngineVersion` when the meaning of stored data changes.

### App layer

- **Navigation**: `AppRouter` (`App/AppShell.swift`) holds the `NavigationStack` path, with routes for processing, results and compare. `ContentView` hosts it. The flow is Home dashboard → Processing → Session Report (`ResultsView`, one scrolling page) → `ShotDetailView`.
- **Storage**: `LibraryStore` is the single source of truth. It keeps sessions in `Application Support/TennisAICoach/sessions/*.json` and video copies in `videos/`, plus `profiles.json`. `sessions` returns only the active player's sessions (`session(id:)` searches all players). Records written before profiles existed get attached to the first profile and rewritten on load. The profile's racquet hand becomes `AnalysisConfig.hittingArm`.
- **Rendering**: `DesignSystem/PoseDrawing.swift` is the one skeleton renderer, shared by the live overlay, the MP4 exporter (`AnnotatedVideoExporter`, the only engine file using UIKit) and share cards.
- **Theme**: `Theme.surface` must stay `secondarySystemGroupedBackground`; the plain system background is invisible against the grouped page background. Liquid Glass is used for chrome only.
- **AppsFlyer**: `App/Attribution.swift`. The tracking prompt is shown only after onboarding, on `didBecomeActive` after a 0.7 s settle. The SDK starts once the prompt has been answered. It sends two milestone events with no tennis data.

### Rules for user-facing text (`scorer-harness` checks only the px/s and mph rule)

- Scores are integers.
- No px/s or mph anywhere in the UI.
- Say "at contact" only when the contact was heard; otherwise say "around your fastest wrist moment".
- With fewer than 4 graded swings, the session score is labelled Provisional.

## Validation rules

- **Never judge stroke detection by stroke count.** `score.py` matches by time (±0.15 s) **and** checks the hitting arm. A count-only check once passed while every stroke was on the wrong wrist.
- **Current baseline** (README table): 32 of 33 labelled contacts found, 0 false, arm right in 7/7 clips with the hand set. Without audio: 24/32 found, 6 false.
  - Only `IMG_7145.MOV` is in the repo (and git-ignored as a video). The six `IMG_2xxx` rally clips were shared separately.
- **Scoring calibration**: `IMG_7145` forehands score 75 / 91 / 77, and the same swing with the body frozen (arm only) scores about 36. Recheck both with `scoring-eval` after any `FormBands` or scorer change.
  - `IMG_7145` is the developer's own swing. Never put synthetic or altered sessions into a device or simulator library under the real video without clearly labelling them.
- **Thresholds**: constants were picked from the middle of the range where results hold, not its edge. With 7 clips it's easy to overfit, so when you move a threshold, report the whole range where the result holds.
- When a user reports a false stroke, check it on **full frames** (where is the ball?), not crops around the player. Ball bounces about 0.45 s either side of a real hit are the known trap.

## Improving the analysis model

The engine is rules over 2D pose and audio, tuned against a small labelled set. In rough priority order:

1. **Grow the labelled data before tuning anything.** `labels.json` covers 7 clips from 2 right-handed players.
   - Add left-handers, more serves and one-handed backhands, indoor and outdoor sound, and clips filmed from behind and side-on.
   - `labels.json` already records a kind for each swing (`S`/`FH`/`BH`/`X`), but `score.py` only prints the detected kinds. Have it report **kind accuracy** too, so `StrokeAnatomy` changes are measured the way detection changes are.
2. **Calibrate scoring against skill levels.** `FormBands` were set from biomechanics literature plus one competent player's forehands and a synthetic arm-only swing. Serves and backhands have never been checked against labelled skill levels.
   - Collect clips rated beginner, intermediate or advanced (ideally by a coach), and add them to `scoring-eval` as expected score ranges. Then fit the weights and band edges to them instead of hand-picking.
3. **Make the no-audio path stronger.** Without sound the detector falls to 24/32 with 6 false strokes, and muted clips or music are common.
   - Candidate extra evidence for wrist-only strokes: shoulder-turn timing from `SwingKinematics`, both wrists together for two-handed backhands, a minimum swing duration.
   - On the audio side, onsets are judged only by sharpness and loudness. Spectral features could tell strings from a bounce without the hand-speed workaround.
4. **Move from 2D toward 3D pose.** Every angle is 2D, so the code throws away foreshortened limbs, and 2D hand speed reads about 0.6 of the true speed. Swings toward or away from the lens read slow.
   - Vision's 3D body pose (`VNDetectHumanBodyPose3DRequest`) is the obvious next step to evaluate. Re-run both harnesses, since every band in `FormBands` assumes today's 2D measurements.
5. **Racquet-arm identification for far players.** Vision mixes up a distant player's left and right wrists, so guessing the hitting arm gets only 6 of 7 clips right. That's why profiles store the racquet hand.
   - Smoothing left/right identity over time in the tracker would help both the arm guess and `StrokeAnatomy`'s side test.
6. **Stroke classes the rules don't cover.** Smashes are labelled as serves. Volleys, slices and drop shots aren't modelled. Ambiguous groundstrokes stay `.groundstroke`.
   - Once the labelled set is a few hundred strokes, a small on-device classifier over pose windows (e.g. a Create ML action classifier) could replace or back up the `StrokeAnatomy` thresholds. Keep the rules as a fallback, and compare the two in detection-eval.
7. **Ball and racquet detection.** This is the biggest missing input: true contact point, shot direction, depth and spin all need the ball. It would have to be an on-device Core ML model to keep the app's "analysis never leaves the phone" promise (`docs/index.html` is the published privacy policy).
8. **Known inconsistency to fix**: `CompareEngine` still leaves speed out, citing "pixel speeds". Since engine version 2, speeds are body-relative and comparable across sessions (`ProgressEngine` already uses them), so compare could include speed for sessions with `hasBodyRelativeSpeeds`.

For any of these, the process is the same:
- Measure the change with the harnesses and compare against the README tables.
- Update the README's tables and limitations section, and the constant's doc comment, with the new numbers and the range where they hold.
- Bump `currentEngineVersion` only if what gets stored changes. Scorer-only changes re-grade old sessions automatically.
