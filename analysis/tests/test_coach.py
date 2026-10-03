import os
import sys
from datetime import date, datetime, timedelta

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect.coach import (  # noqa: E402
    BrushRecord, Goals, daily_summary, earned_achievements, new_achievements,
    perfect_streak, session_feedback, weekly_progress,
)

TODAY = date(2026, 10, 10)


def rec(day_offset, hour, dur, water=0.0):
    d = TODAY - timedelta(days=day_offset)
    return BrushRecord(datetime(d.year, d.month, d.day, hour), dur, water)


def test_goal_validation_and_warnings():
    assert Goals().warnings() == []
    assert len(Goals(per_day=1, target_s=60).warnings()) == 2
    with pytest.raises(ValueError):
        Goals(target_s=10)


def test_feedback_praise_and_encouragement():
    g = Goals()
    assert "elérted" in session_feedback(BrushRecord(datetime.now(), 125), g)
    low = session_feedback(BrushRecord(datetime.now(), 40), g)
    assert "80 másodperc hiányzott" in low and "26%" in low
    mid = session_feedback(BrushRecord(datetime.now(), 90), g)
    assert "több az átlagos" in mid


def test_streak_and_achievements():
    g = Goals()
    records = [rec(d, h, 125) for d in range(7) for h in (7, 21)]
    assert perfect_streak(records, g, TODAY) == 7
    got = earned_achievements(records, g, TODAY)
    assert {"first_brush", "goal_reached", "perfect_day", "streak_3", "streak_7", "water_saver_10"} <= got
    assert "streak_30" not in got


def test_streak_counts_from_yesterday_when_today_unfinished():
    g = Goals()
    records = [rec(d, h, 125) for d in range(1, 4) for h in (7, 21)] + [rec(0, 7, 125)]
    assert perfect_streak(records, g, TODAY) == 3


def test_new_achievements_only_reports_new():
    g = Goals()
    before = earned_achievements([rec(1, 7, 40)], g, TODAY)
    new = new_achievements(before, [rec(1, 7, 40), rec(0, 7, 130)], g, TODAY)
    assert [a.key for a in new] == ["above_average", "goal_reached"]


def test_improver_and_weekly_message():
    g = Goals()
    records = [rec(d, 7, 60) for d in range(7, 14)] + [rec(d, 7, 90) for d in range(7)]
    assert "improver" in earned_achievements(records, g, TODAY)
    msg = weekly_progress(records, g, TODAY)
    assert "30 másodperccel jobb" in msg and "30 másodperc hiányzik" in msg


def test_water_waster_does_not_get_saver_badge():
    g = Goals()
    records = [rec(d, 7, 125, water=60) for d in range(12)]
    assert "water_saver_10" not in earned_achievements(records, g, TODAY)


def test_daily_summary():
    g = Goals()
    assert "Még 1 fogmosás" in daily_summary([rec(0, 7, 125)], g, TODAY)
    assert "Tökéletes nap" in daily_summary([rec(0, 7, 125), rec(0, 21, 130)], g, TODAY)
