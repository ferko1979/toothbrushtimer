"""Train the learned brushing detector from labelled recordings.

    python train.py --labels recordings/labels.csv --out model.json

labels.csv columns: file,brush_type,start_s,end_s
  * one row per brushing interval (a file may have several rows)
  * a row with empty start_s/end_s marks a file with no brushing (negative example)
  * file paths are relative to the CSV's folder

Before fitting the final model it runs leave-one-recording-out validation:
each recording is scored by a model trained on all the others, which is
the honest estimate of how well it works on a recording it has never seen.
"""

from __future__ import annotations

import argparse
import csv
import os
from collections import defaultdict

import numpy as np

from brushdetect import TimerConfig, load_audio, run_timer
from brushdetect.learned import HOP, FRAME_HOP, causal_smooth, fit, window_features
from brushdetect.features import SR


def read_labels(path: str) -> dict[str, dict]:
    base = os.path.dirname(os.path.abspath(path))
    out: dict[str, dict] = defaultdict(lambda: {"type": "", "intervals": []})
    with open(path) as f:
        for row in csv.DictReader(f):
            p = os.path.join(base, row["file"].strip())
            out[p]["type"] = row.get("brush_type", "").strip()
            if row["start_s"].strip():
                out[p]["intervals"].append((float(row["start_s"]), float(row["end_s"])))
    return dict(out)


def label_windows(times: np.ndarray, intervals) -> np.ndarray:
    y = np.zeros(len(times))
    for a, b in intervals:
        y[(times > a) & (times < b)] = 1.0
    return y


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--labels", default="recordings/labels.csv")
    ap.add_argument("--out", default="model.json")
    ap.add_argument("--c", type=float, default=0.1, help="inverse regularisation strength")
    args = ap.parse_args(argv)

    from sklearn.metrics import roc_auc_score

    labels = read_labels(args.labels)
    data = {}
    for path, info in labels.items():
        t, feats = window_features(load_audio(path))
        data[path] = (t, feats, label_windows(t, info["intervals"]))
        print(f"{os.path.basename(path):<50} {len(t):4d} ablak, ebből fogmosás {int(data[path][2].sum()):4d}")

    dt = HOP * FRAME_HOP / SR
    if len(data) > 1:
        print("\nKihagyásos validáció (a modell az adott felvételt nem látta):")
        for held in data:
            rest = [p for p in data if p != held]
            ys = np.concatenate([data[p][2] for p in rest])
            if ys.min() == ys.max():
                print(f"  {os.path.basename(held)}: kihagyva (a többiben nincs mindkét osztály)")
                continue
            model = fit(np.vstack([data[p][1] for p in rest]), ys, args.c)
            t, feats, y = data[held]
            p = causal_smooth(model.predict(feats))
            sessions = run_timer(t, p, dt, TimerConfig())
            est = sum(s.active_s for s in sessions)
            truth = sum(b - a for a, b in labels[held]["intervals"])
            auc = f"AUC={roc_auc_score(y, p):.3f}" if 0 < y.sum() < len(y) else "AUC=  -  "
            spans = ", ".join(f"{s.start:.1f}–{s.end:.1f}" for s in sessions) or "—"
            print(f"  {os.path.basename(held):<50} {auc}  becsült {est:5.1f} s / címke {truth:5.1f} s  [{spans}]")

    model = fit(np.vstack([d[1] for d in data.values()]),
                np.concatenate([d[2] for d in data.values()]), args.c,
                meta={"trained_on": [os.path.basename(p) for p in data]})
    model.save(args.out)
    print(f"\nModell mentve: {args.out}")


if __name__ == "__main__":
    main()
