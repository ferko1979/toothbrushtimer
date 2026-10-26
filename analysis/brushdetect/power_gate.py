"""Battery saver: a cheap loudness gate in front of the detectors.

Every 0.5 s the app computes one RMS value (a few hundred multiply-adds).
Only while the gate is open does it run the mel features, the learned models
and the sonic detector. The gate opens when the level rises `open_db` above
the adaptive background floor and stays open `hold_s` after the last loud
moment, so pauses during brushing do not close it.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .features import SR


@dataclass(frozen=True)
class GateConfig:
    hop_s: float = 0.5
    open_db: float = 6.0
    hold_s: float = 15.0
    floor_rise_db_per_s: float = 0.05


class EnergyGate:
    def __init__(self, cfg: GateConfig | None = None):
        self.cfg = cfg or GateConfig()
        self.floor: float | None = None
        self._last_loud = -1e9

    def update(self, t: float, rms_db: float) -> bool:
        c = self.cfg
        if self.floor is None or rms_db < self.floor:
            self.floor = rms_db
        else:
            self.floor += c.floor_rise_db_per_s * c.hop_s
        if rms_db >= self.floor + c.open_db:
            self._last_loud = t
        return t - self._last_loud <= c.hold_s


def rms_db_per_hop(x: np.ndarray, hop_s: float = 0.5) -> tuple[np.ndarray, np.ndarray]:
    n = int(hop_s * SR)
    k = len(x) // n
    frames = x[: k * n].reshape(k, n)
    db = 10 * np.log10(np.mean(frames.astype(np.float64) ** 2, axis=1) + 1e-12)
    return (np.arange(k) + 0.5) * hop_s, db


def gate_mask(x: np.ndarray, cfg: GateConfig | None = None) -> tuple[np.ndarray, np.ndarray]:
    """(times, open?) for a whole recording - for offline evaluation."""
    cfg = cfg or GateConfig()
    t, db = rms_db_per_hop(x, cfg.hop_s)
    g = EnergyGate(cfg)
    return t, np.array([g.update(tt, d) for tt, d in zip(t, db)])
