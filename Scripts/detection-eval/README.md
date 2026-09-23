# Stroke detection evaluation

Runs the real analysis engine (tracker, pose, audio, stroke detection) on macOS
against video clips, and scores the strokes it finds against hand-labelled
contact times. Vision's body-pose request can't run in the iOS Simulator; it
runs fine on macOS, so this is how the engine is validated off-device.

## Labels

`labels.json` holds, per clip, the player's racquet hand and every swing:
`[kind, contact time in seconds, optional flag]`. Kinds are `S` serve, `FH`,
`BH`, or `X` (a stroke whose side wasn't labelled). Contact is the frame where
the ball meets the strings, read from the video (±0.05 s), cross-checked
against the sound of the hit. Flags: `edge` — the clip starts mid-stroke;
`unsure` — a swing whose contact isn't visible. Flagged swings don't count
either way.

`IMG_7145` is the repo-root clip. The six `IMG_2xxx` clips (two players, rally
footage filmed from across the court, one portrait) were shared separately and
are not in the repo.

## Run

```bash
E="Tennis AI Coach/Engine"
files=()
for f in "$E"/*.swift "$E"/Models/*.swift; do
  case "$f" in *AnnotatedVideoExporter*|*AnalysisService*) continue;; esac
  files+=("$f")
done
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun -sdk macosx \
  swiftc -O -o /tmp/detect Scripts/detection-eval/main.swift "${files[@]}"

mkdir -p /tmp/detect-out
ARM=right /tmp/detect /tmp/detect-out IMG_7145.MOV path/to/IMG_2*.MOV
Scripts/detection-eval/score.py /tmp/detect-out
```

`ARM=right` stands in for a profile's racquet hand (both labelled players are
right-handed); leave it out to test the guess. `NOAUDIO=1` tests the pose-only
fallback.

## Results (September 2026)

| Engine | Found | False | Arm right |
|---|---|---|---|
| Before: full-frame pose, pixel speeds | 5 / 32 | 15 | 3 / 7 |
| Player tracker only | 14 / 33 | 15 | 6 / 7 |
| Tracker + audio, loudest-first by onset sharpness | 30 / 33 | 2 | 7 / 7 |
| Current, no sound | 24 / 32 | 6 | 7 / 7 |
| Current | 32 / 33 | 0 | 7 / 7 |

(The denominator moves by one because the `edge` serve at the very start of
IMG_2097 only counts when it's found.)

Timing: median +0.02 s, worst 0.09 s. The one miss is a quiet stroke on the
portrait clip (IMG_2160 at 6.25 s) where the sound is faint and the wrist
barely registers.

The two false strokes in the third row were both bounces in IMG_2116: the
incoming ball landing during the player's backhand take-back (19.85 s, real
hit 20.32 s), and the player's own shot landing near the camera during their
recovery (23.38 s, real hit 22.92 s). Each was accepted because a swing was
under way within a quarter second, then blocked the real hit beside it. The
fix: rank sounds by loudness rather than onset sharpness, and require the hand
to be moving (3.5 torso lengths/s) at the sound itself.

Never judge a change by stroke count — score it here.
