import os
import sys

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect import BrushTimer, TimerConfig, compute_features, run_timer  # noqa: E402
from make_synthetic import scenario  # noqa: E402


@pytest.mark.parametrize("name", ["manual_close", "manual_far", "electric", "water_only", "silence_fan"])
def test_synthetic_scenarios(name):
    x, truth = scenario(name, np.random.default_rng(1))
    feats = compute_features(x.astype(np.float32))
    sessions = run_timer(feats.t, feats.score, feats.hop_s)
    total = sum(s.active_s for s in sessions)
    assert abs(total - truth) <= max(8.0, 0.1 * truth), (name, total, truth)


def test_short_pause_counted_long_pause_not():
    cfg = TimerConfig(pause_tolerance_s=3.0, session_end_s=20.0, min_on_s=1.0)
    dt = 0.5
    # 10 s on, 2 s off, 10 s on, 8 s off, 10 s on
    pattern = [1] * 20 + [0] * 4 + [1] * 20 + [0] * 16 + [1] * 20
    timer = BrushTimer(cfg)
    for i, s in enumerate(pattern):
        timer.update((i + 1) * dt, s, dt)
    sessions = timer.finish()
    assert len(sessions) == 1
    assert sessions[0].active_s == pytest.approx(10 + 2 + 10 + 10)
    assert len(sessions[0].intervals) == 2


def test_long_silence_splits_sessions():
    cfg = TimerConfig(session_end_s=20.0)
    dt = 0.5
    pattern = [1] * 20 + [0] * 60 + [1] * 20
    timer = BrushTimer(cfg)
    for i, s in enumerate(pattern):
        timer.update((i + 1) * dt, s, dt)
    assert len(timer.finish()) == 2


def test_learned_model_roundtrip(tmp_path):
    from brushdetect.learned import LinearModel, causal_smooth, fit, window_features

    rng = np.random.default_rng(2)
    feats, labels = [], []
    for name in ["manual_close", "water_only", "silence_fan"]:
        x, truth = scenario(name, rng)
        t, f = window_features(x.astype(np.float32))
        y = ((t > 12) & (t < 130)).astype(float) if truth else np.zeros(len(t))
        feats.append(f)
        labels.append(y)
    model = fit(np.vstack(feats), np.concatenate(labels))
    path = tmp_path / "m.json"
    model.save(str(path))
    loaded = LinearModel.load(str(path))

    # Unseen realisation of the same conditions. (Generalising to other
    # distances needs training data recorded at those distances.)
    x, _ = scenario("manual_close", np.random.default_rng(99))
    t, f = window_features(x.astype(np.float32))
    p = causal_smooth(loaded.predict(f))
    assert np.allclose(p, causal_smooth(model.predict(f)))
    assert p[(t > 30) & (t < 120)].mean() > 0.8
    assert p[t < 5].mean() < 0.2
