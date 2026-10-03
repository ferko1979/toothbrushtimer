"""Sonic (electric) toothbrush detector: a new, stable, narrow tone.

Sonic brushes (e.g. Philips Sonicare) drive the head at a fixed frequency
around 250-265 Hz - about 31,000 brush movements per minute, two movements
per cycle. That shows up as a sharp spectral line, usually with its 2x
harmonic. Speech also has harmonics, but its pitch keeps moving; mains hum
and fridges are steady but present all the time. So a window counts as
"sonic brush" when the strongest line in 150-400 Hz

  * stands out from its spectral neighbourhood (prominence),
  * stays at the same frequency in every 1 s sub-window (stability),
  * has a visible 2x harmonic,
  * is louder than that frequency's own long-term floor (novelty: it was
    not there before, so it is not a background hum).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy import signal
from scipy.ndimage import median_filter

from .features import SR

NPERSEG = 8192  # 1.95 Hz resolution


@dataclass
class SonicConfig:
    win_s: float = 3.0
    hop_s: float = 0.5
    band_hz: tuple[float, float] = (150.0, 400.0)
    neighbourhood_hz: float = 30.0
    stability_hz: float = 3.0
    prom_ramp_db: tuple[float, float] = (8.0, 16.0)
    novelty_ramp_db: tuple[float, float] = (3.0, 9.0)
    floor_rise_db_per_s: float = 0.1
    harmonic_min_db: float = 3.0


@dataclass
class SonicResult:
    t: np.ndarray
    score: np.ndarray
    f0_hz: np.ndarray
    prominence_db: np.ndarray
    novelty_db: np.ndarray


def _ramp(x, lo, hi):
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def detect_sonic(x: np.ndarray, cfg: SonicConfig | None = None) -> SonicResult:
    cfg = cfg or SonicConfig()
    win, hop, sub = int(cfg.win_s * SR), int(cfg.hop_s * SR), SR
    f = np.fft.rfftfreq(NPERSEG, 1 / SR)
    band = (f >= cfg.band_hz[0]) & (f <= cfg.band_hz[1])
    # analyse a slightly wider range so the neighbourhood median has support
    wide = (f >= cfg.band_hz[0] - cfg.neighbourhood_hz) & (f <= 2 * cfg.band_hz[1] + cfg.neighbourhood_hz)
    in_band = band[wide]
    nb = 2 * int(cfg.neighbourhood_hz / f[1]) + 1
    tol = int(np.ceil(cfg.stability_hz / f[1]))
    rise = cfg.floor_rise_db_per_s * cfg.hop_s

    rows = []
    floor = None
    for s in range(0, len(x) - win + 1, hop):
        subs = []
        for k in range(win // sub):
            _, p = signal.welch(x[s + k * sub : s + (k + 1) * sub], SR, nperseg=NPERSEG,
                                noverlap=NPERSEG // 2)
            subs.append(10 * np.log10(p[wide] + 1e-16))
        subs = np.array(subs)
        spec = 10 * np.log10(np.mean(10 ** (subs / 10), axis=0))
        floor = spec.copy() if floor is None else np.minimum(spec, floor + rise)

        prom = spec - median_filter(spec, size=nb, mode="nearest")
        k = int(np.argmax(np.where(in_band, prom, -np.inf)))
        sub_prom = subs - median_filter(subs, size=(1, nb), mode="nearest")
        # In every 1 s sub-window the local peak (searched in a wider range)
        # must sit within +-tol of k and stand out: no drifting pitch.
        lo = max(k - 3 * tol, 0)
        stable = True
        for sp in sub_prom:
            j = int(np.argmax(sp[lo : k + 3 * tol + 1])) + lo
            stable &= abs(j - k) <= tol and sp[j] >= 6.0
        k2 = int(np.argmin(np.abs(f[wide] - 2 * f[wide][k])))
        harmonic = prom[max(k2 - tol, 0) : k2 + tol + 1].max() >= cfg.harmonic_min_db
        novelty = spec[k] - floor[k]
        fk = f[wide][k]
        score = _ramp(prom[k], *cfg.prom_ramp_db) * _ramp(novelty, *cfg.novelty_ramp_db) * float(stable and harmonic)
        rows.append(((s + win / 2) / SR, score, fk, prom[k], novelty))

    a = np.array(rows) if rows else np.zeros((0, 5))
    return SonicResult(t=a[:, 0], score=a[:, 1], f0_hz=a[:, 2], prominence_db=a[:, 3], novelty_db=a[:, 4])


def describe_tone(f0_hz: float) -> str:
    """Human-readable description of a detected brush tone (Hungarian)."""
    moves = f0_hz * 120  # two brush movements per oscillation cycle
    kind = ("szónikus fogkefe (Sonicare-típusú)" if 220 <= f0_hz <= 300
            else "elektromos fogkefe")
    moves_txt = f"{moves:,.0f}".replace(",", " ")
    return f"{kind}: {f0_hz:.0f} Hz-es zúgás, kb. {moves_txt} mozdulat/perc"
