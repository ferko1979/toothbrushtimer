"""Learned brushing detector: log-mel + stroke-rhythm features -> logistic regression.

Hand-written rules (features.py) turned out too weak on real recordings:
the scrubbing rhythm is there, but so are lots of other sounds. A tiny
linear model over level-independent features separates them much better
and stays trivially portable: inference is one dot product per window.

Features per 3 s window (0.5 s hop), all computed causally:
  * spectral shape: 32 log-mel band means minus their average (level-independent)
  * spectral variability: per-band std over the window
  * level above an adaptive floor (dB-like, log units)
  * stroke rhythm "comb": modulation peak at f0 in 3-6.5 Hz times its 2*f0 harmonic
"""

from __future__ import annotations

import json

import numpy as np
from scipy import signal

from .features import SR

N_MELS = 32
NFFT = 1024
FRAME_HOP = 160  # 10 ms
WIN = 300  # frames = 3 s
HOP = 50  # frames = 0.5 s
FEATURE_VERSION = 1


def _mel_filterbank(n_mels=N_MELS, nfft=NFFT, fmin=80.0, fmax=7900.0) -> np.ndarray:
    mel = lambda f: 2595 * np.log10(1 + f / 700)  # noqa: E731
    imel = lambda m: 700 * (10 ** (m / 2595) - 1)  # noqa: E731
    pts = imel(np.linspace(mel(fmin), mel(fmax), n_mels + 2))
    f = np.fft.rfftfreq(nfft, 1 / SR)
    fb = np.zeros((n_mels, len(f)))
    for i in range(n_mels):
        lo, c, hi = pts[i : i + 3]
        fb[i] = np.clip(np.minimum((f - lo) / (c - lo), (hi - f) / (hi - c)), 0, None)
    return fb


_FB = _mel_filterbank()


def log_mel(x: np.ndarray) -> np.ndarray:
    """(frames, N_MELS) natural-log mel energies, 64 ms frames, 10 ms hop."""
    _, _, z = signal.stft(x, SR, nperseg=NFFT, noverlap=NFFT - FRAME_HOP,
                          boundary=None, padded=False)
    return np.log(_FB @ (np.abs(z) ** 2) + 1e-10).T


def window_features(x: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Return (window centre times, feature matrix)."""
    m = log_mel(x)
    fm = np.fft.rfftfreq(1024, FRAME_HOP / SR)
    hann = np.hanning(WIN)
    band = (fm >= 3.0) & (fm <= 6.5)
    ref = (fm >= 1.5) & (fm <= 15.0)
    tol = int(round(0.4 / fm[1]))

    rows, times = [], []
    floor = None
    for s in range(0, len(m) - WIN + 1, HOP):
        w = m[s : s + WIN]
        mu = w.mean(axis=0)
        # Adaptive floor per band: follows quieter levels, rises slowly.
        floor = mu.copy() if floor is None else np.minimum(floor + 0.01, mu)

        e = np.log(np.exp(w).sum(axis=1))
        p = np.abs(np.fft.rfft((e - e.mean()) * hann, 1024)) ** 2
        p /= np.median(p[ref]) + 1e-12
        c = int(np.argmax(np.where(band, p, 0)))
        c2 = 2 * c
        comb = np.log10(p[c] + 1e-12) + np.log10(p[c2 - tol : c2 + tol + 1].max() + 1e-12)

        rows.append(np.r_[mu - mu.mean(), w.std(axis=0), (mu - floor).mean(), comb])
        times.append((s + WIN / 2) * FRAME_HOP / SR)
    return np.array(times), np.array(rows)


class LinearModel:
    def __init__(self, mean, scale, coef, intercept, meta=None):
        self.mean = np.asarray(mean)
        self.scale = np.asarray(scale)
        self.coef = np.asarray(coef)
        self.intercept = float(intercept)
        self.meta = meta or {}

    def predict(self, feats: np.ndarray) -> np.ndarray:
        z = ((feats - self.mean) / self.scale) @ self.coef + self.intercept
        return 1.0 / (1.0 + np.exp(-z))

    def save(self, path: str) -> None:
        with open(path, "w") as f:
            json.dump({
                "feature_version": FEATURE_VERSION,
                "mean": self.mean.tolist(), "scale": self.scale.tolist(),
                "coef": self.coef.tolist(), "intercept": self.intercept,
                "meta": self.meta,
            }, f, indent=1)

    @classmethod
    def load(cls, path: str) -> "LinearModel":
        with open(path) as f:
            d = json.load(f)
        if d.get("feature_version") != FEATURE_VERSION:
            raise ValueError(f"{path}: feature version {d.get('feature_version')} != {FEATURE_VERSION}")
        return cls(d["mean"], d["scale"], d["coef"], d["intercept"], d.get("meta"))


def fit(feats: np.ndarray, labels: np.ndarray, c: float = 0.1, meta=None) -> LinearModel:
    from sklearn.linear_model import LogisticRegression
    from sklearn.preprocessing import StandardScaler

    sc = StandardScaler().fit(feats)
    clf = LogisticRegression(C=c, max_iter=5000).fit(sc.transform(feats), labels)
    return LinearModel(sc.mean_, sc.scale_, clf.coef_[0], clf.intercept_[0], meta)


def causal_smooth(p: np.ndarray, n: int = 5) -> np.ndarray:
    """Mean of the last `n` windows (what the app can compute live)."""
    c = np.cumsum(np.r_[0.0, p])
    idx = np.arange(1, len(p) + 1)
    return (c[idx] - c[np.maximum(idx - n, 0)]) / np.minimum(idx, n)
