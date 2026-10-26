"""Opt-in data donation: anonymous feature vectors, never audio.

Only the per-window feature vectors the detector already computes (mel-band
shape, variability, level, rhythm comb - 66 numbers per 3 s window), rounded,
with the labels the user confirmed ("yes, that was brushing"). From these the
sound cannot be reconstructed. No names, no timestamps, no device ids.
"""

from __future__ import annotations

import json
import uuid

import numpy as np

from .learned import FEATURE_VERSION


def donation_payload(enabled: bool, features: np.ndarray, labels: np.ndarray, brush_type: str,
                     app_version: str) -> str:
    if not enabled:
        raise PermissionError("Adatfelajánlás nincs bekapcsolva a beállításokban.")
    features = np.asarray(features, dtype=float)
    labels = np.asarray(labels, dtype=float)
    if features.ndim != 2 or len(features) != len(labels):
        raise ValueError("features must be (windows, dims) with one label per window")
    return json.dumps({
        "id": uuid.uuid4().hex,  # random per donation, not linkable to the user
        "feature_version": FEATURE_VERSION,
        "app_version": app_version,
        "brush_type": brush_type if brush_type in ("manual", "electric") else "unknown",
        "features": np.round(features, 3).tolist(),
        "labels": labels.astype(int).tolist(),
    })
