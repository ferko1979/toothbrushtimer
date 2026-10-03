"""Train the learned detectors (brushing + running water) from labelled recordings.

    python train.py --labels recordings/labels.csv --out model.json

labels.csv columns: file,kind,brush_type,start_s,end_s
  * kind: "brush" or "water"; one row per interval (a file may have several rows)
  * a row with empty start_s/end_s marks a file without such intervals (negative example)
  * brushing starts when the wetting water stops and ends when the rinse water starts
  * file paths are relative to the CSV's folder

Before fitting the final models it runs leave-one-recording-out validation:
each recording is scored by models trained on all the others and run
through the full session logic (water cue -> brushing -> rinse), which is
the honest estimate of how it works on a recording it has never seen.
"""

from __future__ import annotations

import argparse
import csv
import os
from collections import defaultdict

import numpy as np

from brushdetect import load_audio
from brushdetect.learned import fit, save_heads, water_features, window_features
from brushdetect.pipeline import score_recording
from brushdetect.session import run_sessions

KINDS = ("brush", "water")


def read_labels(path: str) -> dict[str, dict]:
    base = os.path.dirname(os.path.abspath(path))
    out: dict[str, dict] = defaultdict(lambda: {"type": "", "brush": [], "water": []})
    with open(path) as f:
        for row in csv.DictReader(f):
            p = os.path.join(base, row["file"].strip())
            kind = (row.get("kind") or "brush").strip()
            if kind not in KINDS:
                raise ValueError(f"{path}: unknown kind {kind!r}")
            out[p]["type"] = (row.get("brush_type") or "").strip() or out[p]["type"]
            if row["start_s"].strip():
                out[p][kind].append((float(row["start_s"]), float(row["end_s"])))
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
    ap.add_argument("--verbose", action="store_true", help="print session events")
    ap.add_argument("--c", type=float, default=0.1, help="inverse regularisation strength")
    args = ap.parse_args(argv)

    from sklearn.metrics import roc_auc_score

    labels = read_labels(args.labels)
    audio, data = {}, {}
    for path, info in labels.items():
        audio[path] = x = load_audio(path)
        data[path] = {}
        for k, featfn in (("brush", window_features), ("water", water_features)):
            t, feats = featfn(x)
            data[path][k] = (t, feats, label_windows(t, info[k]))
        print(f"{os.path.basename(path):<50} fogmosás {int(data[path]['brush'][2].sum()):4d} / "
              f"{len(data[path]['brush'][0])} ablak, víz {int(data[path]['water'][2].sum()):4d} / "
              f"{len(data[path]['water'][0])} ablak")

    def fit_heads(paths, meta=None):
        heads = {}
        for k in KINDS:
            ys = np.concatenate([data[p][k][2] for p in paths])
            if ys.min() == ys.max():
                return None
            heads[k] = fit(np.vstack([data[p][k][1] for p in paths]), ys, args.c, meta)
        return heads

    if len(data) > 1:
        print("\nKihagyásos validáció (a modell az adott felvételt nem látta):")
        for held in data:
            heads = fit_heads([p for p in data if p != held])
            if heads is None:
                print(f"  {os.path.basename(held)}: kihagyva (a többiben nincs mindkét osztály)")
                continue
            sc = score_recording(audio[held], heads)
            prob = {"brush": sc.brush, "water": sc.water}
            y = {k: label_windows(sc.t, labels[held][k]) for k in KINDS}
            aucs = " ".join(
                f"{k}-AUC={roc_auc_score(y[k], prob[k]):.3f}" if 0 < y[k].sum() < len(y[k]) else f"{k}-AUC=  -  "
                for k in KINDS)
            sessions, events = run_sessions(sc.t, sc.water, sc.brush, sc.sonic, sc.hop_s)
            truth = labels[held]["brush"]
            truth_txt = ", ".join(f"{a:.1f}–{b:.1f}" for a, b in truth) or "—"
            found = ", ".join(f"{s.start:.1f}–{s.end:.1f} ({s.duration_s:.0f} s, víz {s.water_running_s:.0f} s)"
                              for s in sessions) or "—"
            print(f"  {os.path.basename(held):<50} {aucs}\n      címke: {truth_txt}   észlelt: {found}")
            if args.verbose:
                print("      események: " + ", ".join(f"{a:.1f} {e}" for a, e in events))

    heads = fit_heads(list(data), meta={"trained_on": [os.path.basename(p) for p in data]})
    if heads is None:
        raise SystemExit("A címkékben mindkét osztályra (van / nincs) kell példa, fogmosásra és vízre is.")
    save_heads(args.out, heads)
    print(f"\nModell mentve: {args.out}")


if __name__ == "__main__":
    main()
