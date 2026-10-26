"""Python must still reproduce the golden vectors used by the native ports."""
import json
import os
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.dirname(__file__))
sys.path.insert(0, HERE)

from brushdetect import load_audio  # noqa: E402
from brushdetect.learned import load_heads, log_mel, window_features  # noqa: E402
from brushdetect.pipeline import score_recording  # noqa: E402
from brushdetect.session import run_sessions  # noqa: E402

GOLDEN = os.path.join(HERE, "golden")


@pytest.fixture(scope="module")
def golden():
    with open(os.path.join(GOLDEN, "golden_expected.json")) as f:
        exp = json.load(f)
    x = load_audio(os.path.join(GOLDEN, exp["audio"]))
    heads = load_heads(os.path.join(GOLDEN, exp["model"]))
    return exp, x, heads


def test_golden_features_and_scores(golden):
    exp, x, heads = golden
    tol = exp["tolerance"]
    mel = log_mel(x)
    assert list(mel.shape) == exp["log_mel"]["shape"]
    assert np.allclose(mel[:20], exp["log_mel"]["first_frames"], atol=tol["log_mel"])
    _, fb = window_features(x)
    assert np.allclose(fb, exp["brush_windows"]["features"], atol=tol["features"])
    sc = score_recording(x, heads)
    assert np.allclose(sc.brush, exp["scores"]["brush"], atol=tol["probabilities"])
    assert np.allclose(sc.water, exp["scores"]["water"], atol=tol["probabilities"])
    assert np.allclose(sc.sonic, exp["scores"]["sonic"], atol=tol["sonic_score"])
    sessions, events = run_sessions(sc.t, sc.water, sc.brush, sc.sonic, sc.hop_s)
    assert [(round(s.start, 3), round(s.end, 3)) for s in sessions] == \
        [(s["start"], s["end"]) for s in exp["sessions"]]
    assert [e for _, e in events] == [e for _, e in exp["events"]]
