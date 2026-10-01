"""Generate synthetic test recordings with known ground truth.

These are NOT a substitute for real recordings - they only check that the
pipeline behaves sensibly (detects rhythmic scrubbing and motor hum,
ignores steady water and fan noise).

    python make_synthetic.py --out synthetic/
"""

from __future__ import annotations

import argparse
import os

import numpy as np
import soundfile as sf
from scipy import signal

from brushdetect import SR


def _noise(n, rng, band=(100, 7500)):
    sos = signal.butter(4, band, "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, rng.standard_normal(n))


def _db(x_db):
    return 10 ** (x_db / 20)


def brushing_manual(dur, rng, rate_hz=4.0):
    """Scrubbing noise whose loudness pulses with each stroke (jittery rate)."""
    n = int(dur * SR)
    t = np.arange(n) / SR
    inst_rate = rate_hz * (1 + 0.15 * np.sin(2 * np.pi * 0.2 * t + rng.uniform(0, 6)))
    phase = 2 * np.pi * np.cumsum(inst_rate) / SR
    mod = (0.5 * (1 - np.cos(phase))) ** 2
    return _noise(n, rng, (1500, 7500)) * (0.1 + mod)


def brushing_electric(dur, rng, f0=260.0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = sum(np.sin(2 * np.pi * k * f0 * t) / k for k in range(1, 6))
    return 0.6 * tone + 0.3 * brushing_manual(dur, rng)


def water(dur, rng):
    return 0.8 * _noise(int(dur * SR), rng, (300, 7000))


def fan(dur, rng):
    n = int(dur * SR)
    return 0.05 * _noise(n, rng, (100, 1500))


def place(buf, clip, at_s, gain_db=0.0):
    i = int(at_s * SR)
    j = min(len(buf), i + len(clip))
    buf[i:j] += clip[: j - i] * _db(gain_db)


def scenario(name, rng):
    """Return (audio, true brushing seconds)."""
    if name == "manual_close":
        dur = 150
        x = fan(dur, rng)
        place(x, water(2, rng), 5)
        place(x, brushing_manual(55, rng), 10)
        # 2 s pause (spit) then the rest
        place(x, brushing_manual(65, rng), 67)
        place(x, water(4, rng), 135)
        return x, 120.0
    if name == "manual_far":
        x, truth = scenario("manual_close", rng)
        return 0.25 * x + fan(len(x) / SR, rng), truth  # ~12 dB quieter, same fan
    if name == "electric":
        dur = 140
        x = fan(dur, rng)
        place(x, brushing_electric(120, rng), 10, gain_db=-6)
        return x, 120.0
    if name == "water_only":
        dur = 60
        x = fan(dur, rng)
        place(x, water(40, rng), 10)
        return x, 0.0
    if name == "silence_fan":
        return fan(60, rng), 0.0
    raise ValueError(name)


SCENARIOS = ["manual_close", "manual_far", "electric", "water_only", "silence_fan"]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="synthetic")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    rng = np.random.default_rng(args.seed)
    for name in SCENARIOS:
        x, truth = scenario(name, rng)
        x = 0.5 * x / (np.abs(x).max() + 1e-9)
        path = os.path.join(args.out, f"{name}__truth{int(truth)}s.wav")
        sf.write(path, x.astype(np.float32), SR)
        print(path)


if __name__ == "__main__":
    main()
