"""Tests for cues, reminders, brush head, profiles, health export, monthly, habits."""
import json
import os
import sys
from datetime import date, datetime, time, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from brushdetect.brush_head import BrushHead, head_status  # noqa: E402
from brushdetect.coach import BrushRecord, Goals  # noqa: E402
from brushdetect.cues import CueTracker, cue_schedule, progress  # noqa: E402
from brushdetect.habits import detect_habits  # noqa: E402
from brushdetect.health_export import HK_TYPE, to_csv, to_healthkit_samples, to_json  # noqa: E402
from brushdetect.monthly import format_monthly, monthly_report  # noqa: E402
from brushdetect.profiles import Profile, achievement_title, child_feedback, family_overview, stickers  # noqa: E402
from brushdetect.reminders import ReminderSettings, due_reminders, on_first_unlock  # noqa: E402

TODAY = date(2026, 10, 31)  # a Saturday
G = Goals()


def at(day_offset, hour, dur=125.0, water=0.0, minute=0):
    d = TODAY - timedelta(days=day_offset)
    return BrushRecord(datetime.combine(d, time(hour, minute)), dur, water)


# 1. cues
def test_cue_schedule_and_tracker():
    cues = cue_schedule(120)
    assert [c.at_s for c in cues] == [0, 30, 60, 90, 120]
    assert cues[-1].kind == "done" and cues[-1].haptic == "success"
    tr = CueTracker(120)
    assert [c.kind for c in tr.update(0)] == ["start"]
    assert tr.update(10) == []
    assert [c.at_s for c in tr.update(65)] == [30, 60]  # catches up after a gap
    assert tr.update(65) == []
    p = progress(75, 120)
    assert p.quadrant == 3 and round(p.remaining_s) == 45
    assert progress(500, 120).fraction == 1.0 and progress(500, 120).quadrant == 4


# 2. reminders
def test_reminders_morning_bedtime_followup():
    s = ReminderSettings()  # wake 7:00, bedtime 22:30 (-15 min), follow-up after 20 min
    early = datetime.combine(TODAY, time(6, 30))
    assert due_reminders(early, [], G, s, {}) == []
    morning = datetime.combine(TODAY, time(7, 5))
    assert [r.key for r in due_reminders(morning, [], G, s, {})] == ["morning"]
    assert due_reminders(morning, [at(0, 7)], G, s, {}) == []  # already brushed
    sent = {"morning": morning}
    assert due_reminders(datetime.combine(TODAY, time(7, 15)), [], G, s, sent) == []
    fu = due_reminders(datetime.combine(TODAY, time(7, 26)), [], G, s, sent)
    assert [r.key for r in fu] == ["morning_followup1"]
    sent["morning_followup1"] = datetime.combine(TODAY, time(7, 26))
    assert due_reminders(datetime.combine(TODAY, time(8, 30)), [], G, s, sent) == []  # max 1 follow-up
    # brushed after the reminder -> no follow-up
    assert due_reminders(datetime.combine(TODAY, time(7, 30)), [at(0, 7, minute=10)], G, s,
                         {"morning": morning}) == []

    # bedtime reminder 15 min before 22:30, default on; no "evening" reminder by default
    assert due_reminders(datetime.combine(TODAY, time(21, 0)), [at(0, 7)], G, s, {}) == []
    bt = due_reminders(datetime.combine(TODAY, time(22, 15)), [at(0, 7)], G, s, {})
    assert [r.key for r in bt] == ["bedtime"] and bt[0].arm_listening
    assert due_reminders(datetime.combine(TODAY, time(22, 15)), [at(0, 7), at(0, 21)], G, s, {}) == []
    assert due_reminders(morning, [], G, ReminderSettings(enabled=False), {}) == []
    assert due_reminders(morning, [], G, ReminderSettings(morning_enabled=False), {}) == []
    custom = ReminderSettings(bedtime=time(23, 0), bedtime_lead_min=30, evening_enabled=True)
    assert [r.key for r in due_reminders(datetime.combine(TODAY, time(20, 10)), [at(0, 7)], G, custom, {})] \
        == ["evening"]


def test_first_unlock_morning():
    s = ReminderSettings()
    r = on_first_unlock(datetime.combine(TODAY, time(7, 40)), [], G, s, {})
    assert r is not None and r.key == "morning"
    assert on_first_unlock(datetime.combine(TODAY, time(6, 40)), [], G, s, {}) is None
    assert on_first_unlock(datetime.combine(TODAY, time(7, 40)), [], G, s,
                           {"morning": datetime.combine(TODAY, time(7, 0))}) is None


# 3. brush head
def test_brush_head():
    recs = [at(d, 7) for d in range(10)]
    assert not head_status(BrushHead(TODAY - timedelta(days=30)), recs, TODAY).due
    assert head_status(BrushHead(TODAY - timedelta(days=85)), recs, TODAY).soon
    st = head_status(BrushHead(TODAY - timedelta(days=92), "electric"), recs, TODAY)
    assert st.due and "fogkefefejet" in st.message and st.uses == 10
    assert head_status(BrushHead(TODAY), recs, TODAY, after_illness=True).due


# 4. profiles
def test_profiles():
    kid = Profile("b", "Bence", child=True)
    adult = Profile("a", "Anna")
    assert achievement_title("streak_7", kid) == "Fogtündér kedvence"
    assert achievement_title("streak_7", adult) == "Egy hét fegyelem"
    assert "matricát" in child_feedback(130, kid.goals)
    recs = [at(d, h) for d in range(8) for h in (7, 21)]
    assert stickers(recs, kid.goals) == (8, 1)
    text = family_overview([adult, kid], {"a": [at(0, 7)], "b": recs}, TODAY)
    assert "Anna: ma 1/2" in text and "még hiányzik" in text and "figurák: 1" in text


# 5. health export
def test_health_export():
    r = [BrushRecord(datetime(2026, 10, 31, 7, 0, 0), 125.4, 0)]
    s = to_healthkit_samples(r)[0]
    assert s["type"] == HK_TYPE
    assert s["startDate"] == "2026-10-31T07:00:00" and s["endDate"] == "2026-10-31T07:02:05"
    assert to_csv(r).splitlines()[1] == "2026-10-31T07:00:00,125.4,0"
    assert json.loads(to_json(r))[0]["duration_s"] == 125.4


# 6. monthly
def test_monthly_report():
    recs = [at(d, h, 125) for d in range(1, 4) for h in (7, 21)] + [at(5, 7, 60, water=60)]
    rep = monthly_report(recs, G, 2026, 10)
    assert rep.sessions == 7 and rep.days_brushed == 4 and rep.perfect_days == 3 and rep.best_streak == 3
    assert rep.morning == 4 and rep.evening == 3 and rep.tap_off_sessions == 6
    assert round(rep.water_saved_l) == round(6 * 125 / 60 * 8)
    assert round(rep.water_wasted_l) == 8
    text = format_monthly(rep, G, "Anna")
    assert "október" in text and "7 / 62" in text and "elfolyt víz" in text


# 7. habits
def keys(recs, goals=G):
    return {h.key for h in detect_habits(recs, goals, TODAY)}


def test_habits():
    good = [at(d, h) for d in range(14) for h in (7, 21)]
    assert keys(good) == set()
    assert "rushing" in keys([at(d, h, 20) for d in range(14) for h in (7, 21)])
    assert "overbrushing" in keys([at(d, h, 300) for d in range(14) for h in (7, 21)])
    no_evening = [at(d, 7) for d in range(14)]
    assert "evening_skipped" in keys(no_evening)
    assert "evening_skipped" not in keys(no_evening, Goals(per_day=1))
    assert "tap_running" in keys([at(d, 7, water=60) for d in range(7)] + good)
    weekend_short = [at(d, h, 60 if (TODAY - timedelta(days=d)).weekday() >= 5 else 125)
                     for d in range(14) for h in (7, 21)]
    assert "weekend_dip" in keys(weekend_short)
    declining = [at(d, h, 125 if d >= 7 else 90) for d in range(14) for h in (7, 21)]
    assert "declining" in keys(declining)
