import json
import os
import sys
from datetime import date, datetime, time

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect.calibration import BrushCalibration, tap_flow_from_measurement, water_locale_for  # noqa: E402
from brushdetect.donation import donation_payload  # noqa: E402
from brushdetect.extras import ExtraRecord, extras_status, streak  # noqa: E402
from brushdetect.listening import ListeningPolicy  # noqa: E402
from brushdetect.power_gate import gate_mask  # noqa: E402
from brushdetect.settings import FEATURES, Settings  # noqa: E402
from brushdetect.water_report import HU  # noqa: E402

FLAT = (0.0, 0.0, -1.0)
HAND = (0.3, -0.8, -0.5)


def feed(policy, t0, t1, g, step=0.1, jitter=0.0, rng=None):
    t = t0
    while t < t1:
        gx, gy, gz = g
        if jitter:
            gx, gy, gz = (v + rng.normal(0, jitter) for v in g)
        policy.motion(t, gx, gy, gz)
        t += step


# -- listening -------------------------------------------------------------
def test_listen_on_open_and_keep_when_already_flat():
    p = ListeningPolicy()
    p.app_opened(0.0)
    feed(p, 0, 3, FLAT)  # was already lying on the shelf
    assert p.listening and p.placed
    p.app_backgrounded(3.0)  # screen locks
    assert p.listening


def test_stops_when_backgrounded_in_hand_or_picked_up():
    p = ListeningPolicy()
    p.app_opened(0.0)
    feed(p, 0, 3, HAND, jitter=0.1, rng=np.random.default_rng(0))
    assert not p.placed
    p.app_backgrounded(3.0)
    assert not p.listening

    p = ListeningPolicy()
    p.app_opened(0.0)
    feed(p, 0, 3, FLAT)
    p.app_backgrounded(3.0)
    p.motion(5.0, *HAND)  # picked up
    assert not p.listening and "felvették" in p.stop_reason


def test_placed_after_opening_in_hand():
    p = ListeningPolicy()
    p.app_opened(0.0)
    feed(p, 0, 2, HAND, jitter=0.1, rng=np.random.default_rng(1))
    feed(p, 2, 5, FLAT)  # put down on the table
    assert p.placed
    p.app_backgrounded(5.0)
    assert p.listening


def test_timeouts_and_session_end():
    p = ListeningPolicy()
    p.app_opened(0.0)
    feed(p, 0, 3, FLAT)
    p.app_backgrounded(3.0)
    p.tick(200)
    assert p.listening
    p.activity(250)
    p.tick(500)
    assert p.listening
    p.tick(551)
    assert not p.listening

    p = ListeningPolicy()
    p.app_opened(0.0, from_notification=True)  # armed: waits longer, starts sooner
    assert p.armed and p.session_config().fallback_s < 6
    feed(p, 0, 3, FLAT)
    p.app_backgrounded(3.0)
    p.tick(400)
    assert p.listening
    p.session_finished(420)
    assert not p.armed
    p.tick(451)
    assert not p.listening and "véget ért" in p.stop_reason


# -- settings ----------------------------------------------------------------
def test_settings_toggle_screen_and_json_roundtrip():
    s = Settings()
    assert s.is_on("quadrant_cues") and not s.is_on("data_donation") and not s.is_on("floss_tracking")
    assert not s.is_on("watch_complication", platform="ios")
    s2 = s.toggle("floss_tracking", True).toggle("battery_saver", False)
    assert s2.is_on("floss_tracking") and not s2.is_on("battery_saver") and s.is_on("battery_saver")
    with pytest.raises(KeyError):
        s.toggle("nope", True)
    screen = s.screen("watchos")
    assert "Motiváció" in screen and all("live_activity" != f.key for g in screen.values() for f, _ in g)
    back = Settings.from_json(s2.to_json())
    assert back == s2
    # an older settings file without a new feature gets that feature's default
    d = json.loads(s2.to_json())
    del d["enabled"]["family_sync"]
    assert Settings.from_json(json.dumps(d)).is_on("family_sync") is False
    assert len({f.key for f in FEATURES}) == len(FEATURES)


# -- calibration -----------------------------------------------------------------
def test_brush_calibration_and_tap_flow():
    c = BrushCalibration()
    assert c.brush_f0 is None and c.remaining == 3
    for f in (255.9, None, 256.8, 255.0):
        c.add_session(f)
    assert c.brush_f0 == pytest.approx(255.9)
    lo, hi = c.sonic_config().band_hz
    assert lo == pytest.approx(245.9) and hi == pytest.approx(265.9)
    assert "256 Hz" in c.status_text()
    bad = BrushCalibration()
    for f in (120, 256, 300):
        bad.add_session(f)
    assert bad.brush_f0 is None
    assert tap_flow_from_measurement(1.0, 7.5) == pytest.approx(8.0)
    with pytest.raises(ValueError):
        tap_flow_from_measurement(1.0, 0.5)  # 120 l/min is not a tap
    assert water_locale_for(HU, 6.0).flow_l_per_min == 6.0 and water_locale_for(HU, None) is HU


# -- battery saver ------------------------------------------------------------
def test_power_gate_closed_in_silence_open_while_brushing():
    from make_synthetic import brushing_manual, fan, place
    rng = np.random.default_rng(3)
    x = fan(120, rng)
    place(x, brushing_manual(30, rng), 40)
    t, open_ = gate_mask(x.astype(np.float32))
    assert open_[(t > 42) & (t < 68)].all()
    assert not open_[(t > 90)].any()
    assert open_.mean() < 0.5


# -- data donation ---------------------------------------------------------------
def test_donation_requires_opt_in_and_has_no_audio():
    f = np.random.default_rng(0).normal(size=(4, 66))
    with pytest.raises(PermissionError):
        donation_payload(False, f, np.ones(4), "manual", "0.1")
    d = json.loads(donation_payload(True, f, np.array([0, 1, 1, 0]), "manual", "0.1"))
    assert set(d) == {"id", "feature_version", "app_version", "brush_type", "features", "labels"}
    assert len(d["features"][0]) == 66 and d["labels"] == [0, 1, 1, 0]


# -- floss / mouthwash -----------------------------------------------------------
def test_extras():
    today = date(2026, 10, 26)
    recs = [ExtraRecord(datetime(2026, 10, d, 21), "floss") for d in (23, 24, 25, 26)]
    assert streak(recs, "floss", today) == 4
    assert "kipipálva" in extras_status(recs, "floss", today)
    assert "naponta egyszer" in extras_status([], "floss", today)
    with pytest.raises(ValueError):
        ExtraRecord(datetime(2026, 10, 26, 21), "toothpick")
