# Tennis AI Coach

On‑device tennis stroke analysis for iOS. Record or import a clip, and the app
estimates your body pose frame‑by‑frame with **Apple Vision**, measures your
form (knee bend, torso lean, stance, elbow, wrist speed), detects your swings,
and gives you pose‑based coaching — plus an annotated playback with your
skeleton overlaid. Everything runs locally; no network, no accounts, no
third‑party ML dependencies.

> Ported from a Colab notebook prototype (MediaPipe + rule‑based coaching) to a
> native SwiftUI app backed by Apple Vision. It is a **pose‑only** coach: it does
> not detect the ball, court, or racket, and uses no trained classifier.

---

## Features

- **Record** a session with the camera, or **import** a clip from Photos / Files.
- **Pose analysis** with `VNDetectHumanBodyPoseRequest` (12 joints), decoded
  frame‑by‑frame via `AVAssetReader`.
- **Form metrics** per frame: knee angles, elbow angles, torso lean, stance‑width
  ratio, and left/right wrist speed.
- **Swing detection** from wrist‑speed peaks, with per‑swing breakdowns.
- **Rule‑based coaching**: strengths and focus areas derived from your medians.
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
        │
        ▼
 AnalysisPipeline.run  (off the main actor)
        │  for every Nth frame (sampleStride = 2):
        │    1. AVAssetReader → CVPixelBuffer (BGRA)
        │    2. PoseEstimator → VNDetectHumanBodyPoseRequest → joints
        │    3. CoordinateSpace → normalized/bottom‑left → pixel/top‑left
        │    4. MetricsComputer → one FrameMetrics row
        ▼
 StrokeDetector.detect ── wrist‑speed peaks → strokes
        ▼
 CoachingEngine.summarize / generate ── medians → strengths + focus
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
| **Wrist speed** | Pixels/second, measured only across genuinely adjacent tracked frames. |
| **Hitting arm** | The wrist with the higher 90th‑percentile speed. |

Missing values are `NaN` throughout (mirroring the notebook's `None`/`nan`
handling) and are excluded from medians; persistence uses a NaN‑safe JSON coder.

### Swing detection

A swing is a peak in the hitting‑arm wrist speed that is **large relative to your
fastest swing** — not relative to average motion. The gate is
`threshold = max(300, 0.45 × reference)`, where `reference` is the fastest
*sustained* wrist speed (the max of a width‑3 median‑filtered signal, so a
single‑frame tracking glitch can't set the bar). Peaks must be ≥ ~0.45 s apart.
This is scale‑invariant (works at any resolution / frame rate) and avoids
counting take‑back, follow‑through, and reset motion as extra swings.

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
│  ├─ PoseEstimator.swift                VNDetectHumanBodyPoseRequest wrapper
│  ├─ CoordinateSpace.swift              orientation + normalize→pixel conversion
│  ├─ TennisMetrics.swift                per‑frame metric computation
│  ├─ Geometry.swift, NanStats.swift     angle math, NaN‑aware statistics
│  ├─ StrokeDetector.swift               wrist‑speed peak detection
│  ├─ CoachingEngine.swift               medians → strengths/focus
│  ├─ AnnotatedVideoExporter.swift       skeleton + HUD → H.264 MP4 (UIKit)
│  └─ Models/                            AnalysisModels.swift, AnalysisError.swift
├─ Library/        HomeView, ImportSheet, LibraryStore, SessionCard
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
| Microphone | Capture audio so playback matches your session. |
| Photo Library (add) | Save an annotated video back to Photos. |

Importing from Photos uses `PhotosPicker`, which needs **no** library‑read
permission.

---

## Tips for good results

Film **side‑on** to the baseline, with your **full body in frame** and good
lighting. The analysis samples every other frame; faster phones process longer
clips comfortably.

## Known limitations

- Pose‑only: no ball/court/racket detection or shot classification.
- Single‑player: the highest‑confidence person per frame is tracked.
- Metrics are in **pixels** (e.g., wrist speed in px/s), so absolute speeds are
  not directly comparable across clips shot at different distances/resolutions.
- Swing detection is a heuristic tuned for typical groundstroke footage; the
  `0.45` threshold constant can be adjusted in `StrokeDetector.swift` if a clip
  mis‑counts.

---

## Credits

Built by Logan Huang. Derived from the
`Another_copy_of_042626_Tennis_Video_AI…` Colab notebook, re‑implemented on
Apple Vision + AVFoundation.
