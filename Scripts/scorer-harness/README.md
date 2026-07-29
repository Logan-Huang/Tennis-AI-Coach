# ShotScorer verification harness

Runs the pure scoring engine on macOS against a saved `AnalysisResult` JSON
(e.g. the repo-root `IMG_7145_analysis.json`). Engine files are UI-free, so
they compile straight into a CLI:

```bash
E="Tennis AI Coach/Engine"
swiftc -o /tmp/scorer_test \
  "$E/NanStats.swift" "$E/Models/AnalysisModels.swift" "$E/Models/ScoreModels.swift" \
  "$E/ShotScorer.swift" "$E/Narrative.swift" "$E/CoachingEngine.swift" \
  Scripts/scorer-harness/main.swift
/tmp/scorer_test IMG_7145_analysis.json
```

Checks: per-stroke scoring in 0–100, weight renormalization under NaN
injection, tracking-gate ungrading on joint-stripped poses, single-stroke
speed-component drop, session rollup sanity, and no px/s/mph in narrative.
