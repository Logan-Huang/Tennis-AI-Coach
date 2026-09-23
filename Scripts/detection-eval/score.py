#!/usr/bin/env python3
"""Score detected strokes against hand-labelled contacts: by TIME and ARM, never
by count (a count-only check once passed while every stroke was on the wrong
wrist). usage: score.py <dir of AnalysisResult JSONs written by main.swift>"""
import json, os, statistics, sys

TOL = 0.15  # s. At 0.25 a wrong-arm answer passes 3/3 on IMG_7145.
labels = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "labels.json")))
out_dir = sys.argv[1]
tp = fn = fp = arm_ok = clips = 0
errors = []
for clip, truth in labels.items():
    path = os.path.join(out_dir, clip + ".json")
    if not os.path.exists(path):
        continue
    result = json.load(open(path))
    clips += 1
    found = [s["peakTime"] for s in result["strokes"]]
    kinds = [s.get("kind", "?") for s in result["strokes"]]
    used, lines = set(), []
    for label in truth["swings"]:
        kind, t = label[0], label[1]
        flag = label[2] if len(label) > 2 else ""
        best = None
        for j, d in enumerate(found):
            if j not in used and abs(d - t) <= TOL and (best is None or abs(d - t) < abs(found[best] - t)):
                best = j
        if best is None:
            if flag:  # "edge" (clip starts mid-stroke) or "unsure": not counted either way
                lines.append((t, "  (%-2s %6.2f %s: not found, not counted)" % (kind, t, flag)))
            else:
                fn += 1
                lines.append((t, "  MISS %-2s %6.2f" % (kind, t)))
        else:
            used.add(best)
            tp += 1
            errors.append(found[best] - t)
            lines.append((t, "  ok   %-2s %6.2f -> %6.2f (%+.2f) %s" % (kind, t, found[best], found[best] - t, kinds[best])))
    for j, d in enumerate(found):
        if j not in used:
            fp += 1
            lines.append((d, "  FALSE      %6.2f %s" % (d, kinds[j])))
    arm = result["hittingArm"]
    arm_ok += arm == truth["arm"]
    print("%s  arm=%s%s" % (clip, arm, "" if arm == truth["arm"] else " (WRONG)"))
    for _, line in sorted(lines):
        print(line)
print("\nfound %d of %d labelled contacts, %d false, arm right on %d of %d clips"
      % (tp, tp + fn, fp, arm_ok, clips))
if errors:
    print("timing error: median %+.3f s, worst %.3f s" % (statistics.median(errors), max(map(abs, errors))))
