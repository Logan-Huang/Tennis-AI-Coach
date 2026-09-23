# Tennis AI Coach

On‑device tennis stroke analysis for iOS. Record or import a clip, and the app
finds the player, estimates their body pose frame‑by‑frame with **Apple
Vision**, detects each stroke from their wrists and the sound of the ball,
tells serves, forehands and backhands apart, and gives stroke‑specific
coaching — plus an annotated playback with the skeleton overlaid. Several
players can share one device, each with their own sessions and trend.
Everything runs locally; no network, no accounts, no third‑party ML
dependencies.

> Ported from a Colab notebook prototype (MediaPipe + rule‑based coaching) to a
> native SwiftUI app backed by Apple Vision. It detects no ball, court or
> racquet in the picture and uses no trained classifier: strokes come from
> body pose plus the click of ball on strings in the soundtrack.

---

## Features

- **Record** a session with the camera, or **import** a clip from Photos / Files.
- **Player profiles**: name + racquet hand per player; sessions, scores, trend,
  comparisons and storage are all per player. Switch from Home.
- **Player tracking**: Vision's person detector picks the player the clip is
  about; pose then runs on a region around them every frame, so a player filmed
  from across the court is tracked, and a hitting partner in view is ignored.
- **Pose analysis** with `VNDetectHumanBodyPoseRequest` (12 joints), decoded
  frame‑by‑frame via `AVAssetReader`, ~30 samples a second.
- **Form metrics** per frame: knee angles, elbow angles, torso lean, stance‑width
  ratio, and left/right wrist speed relative to the body. Knee and elbow angles
  are only measured while that limb faces the camera side‑on.
- **Stroke detection** from body‑relative wrist speed, timed from the sound of
  the ball where the clip has one; each stroke classified as serve, forehand or
  backhand from where the hands are at contact.
- **Stroke‑specific coaching**: serves scored on leg load, reach and arm
  extension; groundstrokes on base, balance, elbow and finish. Speed is only
  compared between strokes of the same kind.
- **Results** in five tabs — Overview, Video (skeleton overlay), Charts,
  Strokes, and Coaching.
- **Annotated MP4 export**: re‑renders the clip with the skeleton and a metric
  HUD burned in.
- **Local library**: analyzed sessions are saved on device and reopened instantly.

---

## How it works

```
 Import / Record
        │
        ▼
 VideoSource.load ─ AVURLAsset: fps, naturalSize, preferredTransform → orientation
 AudioOnsets.detect ─ soundtrack → sharp transients (candidate ball contacts)
        │
        ▼
 AnalysisPipeline.run  (off the main actor; every Nth frame, ~30 samples/s)
        │  pass 1  SubjectLocator ─ person detector ~10×/s → tracks → the player
        │  pass 2  SubjectTracker ─ pose on a square around the player, every frame
        │            PoseEstimator → VNDetectHumanBodyPoseRequest (regionOfInterest)
        │            CoordinateSpace → normalized/bottom‑left → pixel/top‑left
        ▼
 WristTrackingGate ─ drop wrist positions Vision invented
 WristMotion ─ wrist speed relative to the hips, in torso lengths/s
 MetricsComputer ─ one FrameMetrics row per frame (foreshortened limbs → NaN)
        ▼
 StrokeDetector ─ heard contacts confirmed by a fast wrist + wrist‑only strokes
 StrokeAnatomy ─ serve / forehand / backhand, reach, finish, serve knee load
        ▼
 CoachingEngine / ShotScorer / Narrative ── scores + stroke‑aware coaching
        ▼
 AnalysisResult → Results UI  (+ AnnotatedVideoExporter for MP4)
```

The notebook's analytical math ports verbatim after **one** coordinate
conversion: Vision returns normalized points in the *oriented* frame
(origin bottom‑left, y‑up); the metrics assume pixel space (origin top‑left,
y‑down). `CoordinateSpace` converts once, against the orientation derived from
the track's `preferredTransform` (the reader does **not** bake in the transform).

### Metrics glossary

| Metric | Definition |
|---|---|
| **Knee angle (L/R)** | Interior angle at the knee (hip–knee–ankle), degrees. "More‑bent" = the smaller of the two. |
| **Elbow angle (L/R)** | Interior angle at the elbow (shoulder–elbow–wrist), degrees. |
| **Torso lean** | Signed angle from vertical of the shoulder‑center → hip‑center vector. `|abs|` is its magnitude. |
| **Stance ratio** | Ankle‑to‑ankle distance ÷ hip‑to‑hip distance. Values > 3.0 are rejected as anatomically implausible (→ missing). |
| **Wrist speed** | Wrist position relative to the hip centre, divided by the torso length, median‑filtered and smoothed, differenced across two frames: **torso lengths per second**. Cancels camera pans and running; the same at any distance. (Sessions from before September 2026 stored pixels/second.) |
| **Hitting arm** | The player profile's racquet hand; guessed from the clip (98th‑percentile image wrist speed) only when it isn't set. |
| **Reach** | Serves: the higher hand's height above the shoulders at contact, in torso lengths. |
| **Finish** | Groundstrokes: the higher hand's highest point in the 0.5 s after contact, relative to the shoulders. |

Knee and elbow angles are only measured in frames where both segments of the
limb show at least 80% of their full length (the limb is side‑on to the
camera), and a leg whose ankle is clearly off the ground is left out of knee
bend. A 2D angle of a limb pointing at the lens is not the real angle.

Missing values are `NaN` throughout (mirroring the notebook's `None`/`nan`
handling) and are excluded from medians; persistence uses a NaN‑safe JSON coder.

### Stroke detection

Two sources of evidence, neither enough alone. A sharp onset in the soundtrack
is a stroke when a wrist reaches 6 torso lengths/s within 0.25 s of it and the
hand is moving at least 3.5 at the sound itself (which rules out the ball
bouncing while the player waits or recovers); louder sounds are considered
first, and its time is the contact time. A wrist peak of at least 7 torso
lengths/s that no heard hit explains is also a stroke, timed at the hitting
wrist's own peak. One player can't hit twice within a second. See the header
of `StrokeDetector.swift` for the reasoning behind each constant.

Validation lives in `Scripts/detection-eval/`: hand‑labelled contact times for
seven clips (two players; serves, forehands, one‑ and two‑handed backhands; far
and near camera), scored **by time and arm, never by count**. With the racquet
hand set, the current engine finds 32 of the 33 labelled contacts within
0.15 s, reports none that didn't happen, and follows the right arm in all 7
clips (the engine before it: 5 found, 15 false, 3 of 7 arms).

---

## Project structure

```
Tennis AI Coach/
├─ App/            AppShell.swift        navigation router, routes, engine env
├─ ContentView.swift                     NavigationStack: Home → Processing → Results
├─ DesignSystem/   Theme.swift, Components.swift
├─ Engine/         (pure compute — no UIKit/SwiftUI except the exporter)
│  ├─ AnalysisService.swift              AnalysisEngine protocol; Vision + Mock engines
│  ├─ AnalysisPipeline.swift             decode → pose → metrics → strokes → coaching
│  ├─ VideoFrameReader.swift             VideoSource: metadata + AVAssetReader
│  ├─ PlayerTracker.swift                who the clip is about; pose on a region around them
│  ├─ PoseEstimator.swift                VNDetectHumanBodyPoseRequest wrapper
│  ├─ AudioOnsets.swift                  soundtrack → ball‑contact candidates
│  ├─ CoordinateSpace.swift              orientation + normalize→pixel conversion
│  ├─ TennisMetrics.swift                per‑frame metrics, limb foreshortening, wrist gate
│  ├─ WristMotion.swift                  body‑relative wrist speed
│  ├─ Geometry.swift, NanStats.swift     angle math, NaN‑aware statistics
│  ├─ StrokeDetector.swift               heard + wrist strokes
│  ├─ StrokeAnatomy.swift                serve / forehand / backhand, reach, finish
│  ├─ CoachingEngine.swift               medians → strengths/focus
│  ├─ AnnotatedVideoExporter.swift       skeleton + HUD → H.264 MP4 (UIKit)
│  └─ Models/                            AnalysisModels.swift, AnalysisError.swift
├─ Library/        HomeView, ImportSheet, LibraryStore, PlayerProfile, SessionCard
├─ Profiles/       ProfileAvatar, ProfileSwitcherSheet, ProfileEditorView
├─ Processing/     ProcessingView.swift  progress ring, cancel, retry
├─ Record/         CameraController, CameraPreview, RecordView (AVCaptureSession)
├─ Results/        Overview, Video overlay, Charts, Strokes, Coaching, Export
└─ Tennis_AI_CoachApp.swift              @main; injects VisionAnalysisEngine
```

**Engine design:** the `Engine/` layer is pure compute. The project sets
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so engine types are explicitly
marked `nonisolated` and the analysis loop runs off the main actor. Only
`AnnotatedVideoExporter` imports UIKit; the rest of the engine is portable.

---

## Requirements

- **Xcode 26** (iOS 26.5 SDK)
- A device or simulator on **iOS 26.5+** — but see the note below: pose
  estimation requires a **physical device**.
- Swift 5 language mode.

## Build & run

In Xcode: open `Tennis AI Coach.xcodeproj`, select the **Tennis AI Coach**
scheme, and run.

From the command line:

```bash
xcodebuild build \
  -project "Tennis AI Coach.xcodeproj" \
  -scheme "Tennis AI Coach" \
  -destination 'generic/platform=iOS' \
  -configuration Debug
```

> If `xcodebuild`/`xcrun` complain that they "require Xcode," your active
> developer directory is the Command Line Tools. Prefix commands with
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer …` (or run
> `sudo xcode-select --switch /Applications/Xcode.app`).

Sources live in a synchronized file‑system group, so new `.swift` files under
`Tennis AI Coach/` compile automatically — no project‑file edits. Permission
strings are `INFOPLIST_KEY_*` build settings (`GENERATE_INFOPLIST_FILE = YES`),
not a checked‑in `Info.plist`.

### ⚠️ Pose estimation needs a real device

`VNDetectHumanBodyPoseRequest` **cannot initialize in the iOS Simulator** — it
fails at setup (`Vision error code 9, "Unable to setup request"`). The app
handles this gracefully: every frame returns no joints, so Results shows
**"Couldn't track a player."** The rest of the app (import, navigation,
processing, library, UI) runs fine in the Simulator; only the Vision step needs
a **physical iPhone**. The same request works on the macOS Vision runtime, which
is handy for validating the pure engine off‑device.

---

## Data & privacy

- **100% on‑device.** No network calls, accounts, or analytics. Your video and
  results never leave the phone.
- Analyzed sessions are saved under
  `Application Support/TennisAICoach/` — results as NaN‑safe JSON in `sessions/`,
  and a copy of each clip in `videos/`. Deleting a session removes both.

### Permissions

| Permission | Why |
|---|---|
| Camera | Record a session for analysis. |
| Microphone | Capture sound with the video (playback), and listen on‑device for the ball on the strings to time each stroke. |
| Photo Library (add) | Save an annotated video back to Photos. |

Importing from Photos uses `PhotosPicker`, which needs **no** library‑read
permission.

---

## Tips for good results

Film **side‑on** to the baseline, with your **full body in frame** and good
lighting, and keep the video's **sound on** — it's what times each stroke.
Rally footage from behind or across the court works too: the player is found
and tracked wherever they are, but knee and elbow angles are only graded when
the limb faces the camera side‑on, so a side view grades more of your form.
Set each player's racquet hand on their profile.

## Known limitations

- No ball, court or racquet detection in the picture; stroke kind comes from
  hand positions, and a groundstroke whose side can't be read stays unlabelled.
- One player per clip: the person the camera follows. Film the other player
  separately and file it under their profile.
- Wrist speed is relative to the body, but still a 2D, camera‑dependent
  estimate, so it is only compared within one session (never in the trend).
- A serve with the hitting arm lost at contact can go unlabelled; smashes are
  labelled as serves.
- Without sound (muted clip, loud music), strokes are timed from the wrist
  alone and are less reliable: 24 of 32 labelled contacts found with 6 false,
  against 32 of 33 with none with sound.

---

## Credits

Built by Logan Huang. Derived from the
`Another_copy_of_042626_Tennis_Video_AI…` Colab notebook, re‑implemented on
Apple Vision + AVFoundation.
