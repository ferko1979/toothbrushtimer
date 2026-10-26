"""Write golden test vectors for the Swift / Kotlin ports.

    python export_golden.py --out golden/

Creates a deterministic synthetic clip (water -> electric brushing -> rinse),
a model trained only on synthetic audio (no personal recordings), and every
intermediate result of the app pipeline. The native unit tests decode the
same WAV, run their implementation and compare against golden_expected.json
within the stated tolerances. tests/test_golden.py checks that Python still
reproduces the file.
"""

from __future__ import annotations

import argparse
import json
import os

import numpy as np
import soundfile as sf

from brushdetect import load_audio
from brushdetect.coach import Goals
from brushdetect.cues import cue_schedule
from brushdetect.features import SR
from brushdetect.learned import fit, log_mel, save_heads, water_features, window_features
from brushdetect.pipeline import score_recording
from brushdetect.session import run_sessions
from brushdetect.water_report import HU, water_report
from make_synthetic import brushing_electric, brushing_manual, fan, place, water

AUDIO = "golden_audio.wav"
MODEL = "golden_model.json"
EXPECTED = "golden_expected.json"


def clip(rng, brush="electric", dur=24.0, water_at=(1.0, 3.0), brush_at=(3.5, 17.5), rinse_at=(18.0, 21.0)):
    x = fan(dur, rng)
    place(x, water(water_at[1] - water_at[0], rng), water_at[0])
    b = brushing_electric if brush == "electric" else brushing_manual
    place(x, b(brush_at[1] - brush_at[0], rng), brush_at[0], gain_db=-6)
    place(x, water(rinse_at[1] - rinse_at[0], rng), rinse_at[0])
    x = (0.5 * x / (np.abs(x).max() + 1e-9)).astype(np.float32)
    labels = {"water": [water_at, rinse_at], "brush": [brush_at]}
    return x, labels


def label(t, intervals):
    y = np.zeros(len(t))
    for a, b in intervals:
        y[(t > a) & (t < b)] = 1
    return y


def train_synthetic_model(seed=7):
    rng = np.random.default_rng(seed)
    data = {"brush": ([], []), "water": ([], [])}
    for i in range(6):
        x, lab = clip(rng, brush="electric" if i % 2 else "manual", dur=30.0,
                      water_at=(1.0, 3.0 + i % 3), brush_at=(5.0 + i % 3, 22.0), rinse_at=(23.0, 26.0))
        for k, fn in (("brush", window_features), ("water", water_features)):
            t, f = fn(x)
            data[k][0].append(f)
            data[k][1].append(label(t, lab[k]))
    return {k: fit(np.vstack(f), np.concatenate(y), meta={"trained_on": "synthetic only"})
            for k, (f, y) in data.items()}


def r(a, nd=6):
    return np.round(np.asarray(a, dtype=float), nd).tolist()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default="golden")
    args = ap.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)

    heads = train_synthetic_model()
    save_heads(os.path.join(args.out, MODEL), heads)

    x, lab = clip(np.random.default_rng(2026))
    sf.write(os.path.join(args.out, AUDIO), x, SR, subtype="PCM_16")
    # The native tests decode the WAV, so the reference is computed from the file as read back.
    x = load_audio(os.path.join(args.out, AUDIO))

    mel = log_mel(x)
    tb, fb = window_features(x)
    tw, fw = water_features(x)
    sc = score_recording(x, heads)
    sessions, events = run_sessions(sc.t, sc.water, sc.brush, sc.sonic, sc.hop_s)
    wr = water_report(60, HU)

    expected = {
        "description": "Golden vectors for porting brushdetect to Swift/Kotlin. See docs/PORTING.md.",
        "audio": AUDIO, "model": MODEL, "sample_rate": SR,
        "audio_decode": "int16 PCM -> float32 = sample / 32768",
        "labels": lab,
        "tolerance": {"log_mel": 1e-3, "features": 1e-3, "probabilities": 1e-3, "sonic_score": 1e-2,
                      "sonic_f0_hz": 0.5, "session_s": 0.51},
        "log_mel": {"shape": list(mel.shape), "first_frames": r(mel[:20], 5), "frame_400": r(mel[400], 5)},
        "brush_windows": {"t": r(tb, 3), "features": r(fb, 5)},
        "water_windows": {"t": r(tw, 3), "features": r(fw, 5)},
        "scores": {"t": r(sc.t, 3), "brush": r(sc.brush), "water": r(sc.water),
                   "sonic": r(sc.sonic), "sonic_f0": r(sc.sonic_f0, 3)},
        "sessions": [{"start": round(s.start, 3), "end": round(s.end, 3), "cue": s.cue,
                      "water_running_s": round(s.water_running_s, 3)} for s in sessions],
        "events": [[round(t, 3), e] for t, e in events],
        "cue_schedule_120": [[c.at_s, c.kind, c.quadrant, c.haptic] for c in cue_schedule(Goals().target_s)],
        "water_report_60s_hu": {"litres": round(wr.litres, 6), "cost": round(wr.cost, 6),
                                "glasses": round(wr.glasses, 6), "litres_per_year": round(wr.litres_per_year, 6)},
    }
    with open(os.path.join(args.out, EXPECTED), "w") as f:
        json.dump(expected, f)
    print(f"{args.out}/: {AUDIO}, {MODEL}, {EXPECTED}")
    for s in expected["sessions"]:
        print(f"  session {s['start']}–{s['end']} s (cue {s['cue']}, water {s['water_running_s']} s)")


if __name__ == "__main__":
    main()
