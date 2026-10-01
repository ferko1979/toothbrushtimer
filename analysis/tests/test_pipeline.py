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
