"""Run all detectors on a recording and align them on one time grid."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .learned import LinearModel, causal_smooth, water_features, window_features
from .sonic import detect_sonic


@dataclass
class Scores:
    t: np.ndarray  # common grid: water windows (1 s, 0.5 s hop)
    brush: np.ndarray
    water: np.ndarray
    sonic: np.ndarray
    sonic_f0: np.ndarray
    hop_s: float = 0.5


def score_recording(x: np.ndarray, heads: dict[str, LinearModel]) -> Scores:
    tb, fb = window_features(x)
    tw, fw = water_features(x)
    brush = causal_smooth(heads["brush"].predict(fb))
    water = heads["water"].predict(fw)
    son = detect_sonic(x)
    return Scores(
        t=tw,
        brush=np.interp(tw, tb, brush, left=0.0),
        water=water,
        sonic=np.interp(tw, son.t, son.score, left=0.0),
        sonic_f0=np.interp(tw, son.t, son.f0_hz, left=0.0),
    )
