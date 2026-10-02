# Scoring evaluation

Scores saved analysis results with the app's own `ShotScorer` on macOS, and
prints every component of every shot: what it measured and what it scored.
Use it whenever `FormBands` or the scorer change, to see the effect on real
swings before shipping.

Analysis results come from `Scripts/detection-eval` (which runs the full
engine on a clip and writes its `AnalysisResult` JSON), or from a session's
saved JSON in the app's container.

```bash
E="Tennis AI Coach/Engine"
files=()
for f in "$E"/*.swift "$E"/Models/*.swift; do
  case "$f" in *AnnotatedVideoExporter*|*AnalysisService*) continue;; esac
  files+=("$f")
done
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun -sdk macosx \
  swiftc -O -o /tmp/score Scripts/scoring-eval/main.swift "${files[@]}"

/tmp/score /tmp/detect-out/*.json
```

## What to expect

On `IMG_7145` (a competent player's rally forehands, filmed side-on) the
three forehands score 75, 91 and 77: shoulder turns of 106-134° and real
knee load, with the two gentler rally balls held back by hand speed.

The standard a first-timer has to fall short of: the same forehand with the
body frozen upright and unturned, so only the arm swings, scores about 36.
The fast arm can't carry it, because a shot can't score more than
`ShotScorer.powerMargin` above its power components (swing speed, shoulder
turn, legs).
