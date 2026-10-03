import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect.session import run_sessions  # noqa: E402
from brushdetect.water_report import HU, US, format_report, water_report  # noqa: E402

DT = 0.5


def seq(*parts):
    """parts: (seconds, water, brush, sonic) -> per-window arrays."""
    t, w, b, s = [], [], [], []
    for dur, wv, bv, sv in parts:
        for _ in range(int(dur / DT)):
            t.append(len(t) * DT)
            w.append(wv)
            b.append(bv)
            s.append(sv)
    return t, w, b, s


def test_water_cue_brush_rinse():
    # 3 s silence, 4 s wetting, 50 s brushing (tap off), 10 s rinse, 10 s silence
    t, w, b, s = seq((3, 0, 0, 0), (4, 1, 0, 0), (50, 0, 1, 0), (10, 1, 0, 0), (10, 0, 0, 0))
    sessions, events = run_sessions(t, w, b, s, DT)
    assert len(sessions) == 1
    ses = sessions[0]
    assert ses.cue == "water"
    assert ses.start == pytest.approx(7.0, abs=0.6)  # when the wetting water stopped
    assert ses.end == pytest.approx(57.0, abs=0.6)  # when the rinse water started
    assert ses.water_running_s == 0
    assert not ses.wasted_water
    names = [e for _, e in events]
    assert names.index("water_start") < names.index("water_stop") < names.index("brushing_detected")
    assert "rinse_start" in names and "waste_icon_on" not in names


def test_sonic_hum_alone_counts_as_brushing():
    t, w, b, s = seq((4, 1, 0, 0), (40, 0, 0.1, 1), (8, 1, 0, 0), (10, 0, 0, 0))
    sessions, _ = run_sessions(t, w, b, s, DT)
    assert len(sessions) == 1
    assert sessions[0].duration_s == pytest.approx(40, abs=1)


def test_tap_left_running_is_waste():
    # Water never stops: wetting, brushing and rinsing with the tap on.
    t, w, b, s = seq((3, 0, 0, 0), (4, 1, 0, 0), (50, 1, 1, 0), (10, 1, 0, 0), (20, 0, 0, 0))
    sessions, events = run_sessions(t, w, b, s, DT)
    assert len(sessions) == 1
    ses = sessions[0]
    assert ses.wasted_water
    assert ses.water_running_s >= 45
    assert "waste_icon_on" in [e for _, e in events]


def test_short_rewet_mid_brushing_continues_session():
    t, w, b, s = seq((4, 1, 0, 0), (25, 0, 1, 0), (3, 1, 0, 0), (25, 0, 1, 0), (6, 1, 0, 0), (10, 0, 0, 0))
    sessions, events = run_sessions(t, w, b, s, DT)
    assert len(sessions) == 1
    assert sessions[0].duration_s == pytest.approx(53, abs=1.5)
    assert "brushing_resumed" in [e for _, e in events]


def test_no_water_fallback():
    t, w, b, s = seq((3, 0, 0, 0), (30, 0, 1, 0), (20, 0, 0, 0))
    sessions, _ = run_sessions(t, w, b, s, DT)
    assert len(sessions) == 1 and sessions[0].cue == "no_water"


def test_water_only_is_not_brushing():
    t, w, b, s = seq((30, 1, 0, 0), (20, 0, 0, 0))
    sessions, _ = run_sessions(t, w, b, s, DT)
    assert sessions == []


def test_water_report_numbers():
    r = water_report(60, HU)  # one minute of an 8 L/min tap
    assert r.litres == pytest.approx(8.0)
    assert r.glasses == pytest.approx(32.0)
    assert r.cost == pytest.approx(8.0 * 0.653)
    assert r.litres_per_year == pytest.approx(8.0 * 730)
    us = water_report(60, US)
    assert us.gallons == pytest.approx(2.2)


def test_report_texts():
    assert "VÍZPAZARLÁS" in format_report(60, 50, HU)
    assert "elzártad" in format_report(60, 0, HU)
    assert "WATER WASTE" in format_report(60, 50, US)
    assert "gallons" in format_report(60, 0, US)
