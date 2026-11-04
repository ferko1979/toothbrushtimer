"""Retrain the app's detector heads from the real test recordings, blending in the previous model.

    python retrain.py --labels recordings/labels.csv --previous brush_model_v1_previous.json --out model.json

Brushing head: trained on the labelled recordings only (strong regularisation, C=0.01).
Water head: 70 % new + 30 % previous model, blended in logit space and folded into one linear model
(the apps need no change). The blend keeps what the previous model learnt from the original
recordings (lost since) while fixing the oscillating brush and manual scrubbing, which it heard as water.

Before saving, it prints leave-one-recording-out AUCs for the previous model and the new one, so
the numbers are honest: each recording is scored by a model that never saw it.
"""

from __future__ import annotations

import argparse
import os

import numpy as np

from brushdetect import load_audio
from brushdetect.learned import LinearModel, causal_smooth, fit, load_heads, save_heads, water_features, window_features
from train import label_windows, read_labels

BRUSH_C = 0.01
WATER_C = 1.0
WATER_NEW_WEIGHT = 0.7


def combine(a: LinearModel, b: LinearModel, wa: float) -> LinearModel:
    """Logit blend wa*a + (1-wa)*b as one linear model (mean 0, scale 1)."""
    ca = np.asarray(a.coef) / np.asarray(a.scale)
    cb = np.asarray(b.coef) / np.asarray(b.scale)
    ia = a.intercept - float(np.sum(ca * np.asarray(a.mean)))
    ib = b.intercept - float(np.sum(cb * np.asarray(b.mean)))
    n = len(ca)
    return LinearModel(np.zeros(n), np.ones(n), wa * ca + (1 - wa) * cb, wa * ia + (1 - wa) * ib, None)


def main(argv=None):
    from sklearn.metrics import roc_auc_score

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--labels", default="recordings/labels.csv")
    ap.add_argument("--previous", default="brush_model_v1_previous.json")
    ap.add_argument("--out", default="model.json")
    args = ap.parse_args(argv)

    labels = read_labels(args.labels)
    prev = load_heads(args.previous)
    data = {}
    for p, info in labels.items():
        x = load_audio(p)
        tb, fb = window_features(x)
        tw, fw = water_features(x)
        data[p] = dict(fb=fb, fw=fw, yb=label_windows(tb, info["brush"]), yw=label_windows(tw, info["water"]))

    def heads_for(paths):
        b = fit(np.vstack([data[p]["fb"] for p in paths]), np.concatenate([data[p]["yb"] for p in paths]), BRUSH_C)
        w = fit(np.vstack([data[p]["fw"] for p in paths]), np.concatenate([data[p]["yw"] for p in paths]), WATER_C)
        return b, combine(w, prev["water"], WATER_NEW_WEIGHT)

    print(f"{'felvétel':<32} {'előző modell':>22} {'új (kihagyásos)':>24}")
    for held, d in data.items():
        b, w = heads_for([p for p in data if p != held])
        row = []
        for hb, hw in ((prev["brush"], prev["water"]), (b, w)):
            ab = roc_auc_score(d["yb"], causal_smooth(hb.predict(d["fb"])))
            aw = roc_auc_score(d["yw"], hw.predict(d["fw"]))
            row.append(f"brush {ab:.2f} water {aw:.2f}")
        print(f"{os.path.basename(held):<32} {row[0]:>22} {row[1]:>24}")

    b, w = heads_for(list(data))
    names = [os.path.basename(p) for p in data]
    b.meta = {"trained_on": names, "C": BRUSH_C}
    w.meta = {"trained_on": names, "C": WATER_C, "blend": f"{WATER_NEW_WEIGHT} new + {1 - WATER_NEW_WEIGHT:.1f} previous (logits)"}
    save_heads(args.out, {"brush": b, "water": w})
    print(f"\nModell mentve: {args.out}")


if __name__ == "__main__":
    main()
