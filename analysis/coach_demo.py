"""Demo of the coaching features on a simulated month of history.

    python coach_demo.py

Simulates an adult (improving, sometimes skipping evenings, occasionally
leaving the tap on) and a child, then prints what the app would show.
"""

from __future__ import annotations

import random
from datetime import date, datetime, time, timedelta

from brushdetect.brush_head import BrushHead, head_status
from brushdetect.coach import BrushRecord, Goals, daily_summary, session_feedback, weekly_progress
from brushdetect.cues import CueTracker, progress
from brushdetect.habits import detect_habits
from brushdetect.health_export import to_healthkit_samples
from brushdetect.monthly import format_monthly, monthly_report
from brushdetect.profiles import Profile, child_feedback, family_overview
from brushdetect.reminders import ReminderSettings, due_reminders

TODAY = date(2026, 10, 31)


def simulate(seed: int, base_s: float, gain_s: float, skip_evening: float, tap_on: float):
    rng = random.Random(seed)
    out = []
    for i in range(30, -1, -1):
        d = TODAY - timedelta(days=i)
        for slot, hour in (("morning", 7), ("evening", 21)):
            if d == TODAY and slot == "evening":
                continue
            if slot == "evening" and rng.random() < skip_evening:
                continue
            dur = max(15.0, rng.gauss(base_s + gain_s * (30 - i), 15))
            when = datetime.combine(d, time(hour, rng.randint(0, 50)))
            out.append(BrushRecord(when, dur, dur if rng.random() < tap_on else 0.0))
    return out


def main():
    anna = Profile("anna", "Anna")
    bence = Profile("bence", "Bence", child=True)
    records = {
        "anna": simulate(1, base_s=70, gain_s=2.0, skip_evening=0.45, tap_on=0.15),
        "bence": simulate(2, base_s=100, gain_s=0.8, skip_evening=0.1, tap_on=0.0),
    }
    g = anna.goals

    print("== 1. Jelzések fogmosás közben (célidő 120 s) ==")
    tracker = CueTracker(g.target_s)
    for sec in range(0, 125, 5):
        for c in tracker.update(sec):
            p = progress(sec, g.target_s)
            print(f"  {sec:3d} s  [{c.haptic:7s}] {c.text}   (kör: {p.fraction:.0%})")

    print("\n== 2. Emlékeztetők (Anna, ma este 22:05, még nincs esti fogmosás) ==")
    now = datetime.combine(TODAY, time(22, 5))
    for r in due_reminders(now, records["anna"], g, ReminderSettings(), set()):
        print(f"  [{r.key}] {r.text}")

    print("\n== 3. Fogkefe ==")
    print("  " + head_status(BrushHead(TODAY - timedelta(days=95)), records["anna"], TODAY).message)

    print("\n== 4. Családi áttekintés ==")
    print(family_overview([anna, bence], records, TODAY))
    print("  Bence visszajelzése egy 70 s-os fogmosás után: " + child_feedback(70, bence.goals))

    print("\n== 5. Apple Health minta (Anna utolsó fogmosása) ==")
    print("  ", to_healthkit_samples(records["anna"][-1:])[0])

    print("\n== 6. Havi összefoglaló ==")
    print(format_monthly(monthly_report(records["anna"], g, 2026, 10), g, "Anna"))

    print("\n== 7. Szokások ==")
    habits = detect_habits(records["anna"], g, TODAY)
    for h in habits or []:
        print(f"  [{h.key}] {h.message}")
    if not habits:
        print("  Nincs visszatérő rossz szokás. 👍")

    print("\n== Napi/heti állapot és utolsó visszajelzés (Anna) ==")
    print("  " + daily_summary(records["anna"], g, TODAY))
    print("  " + weekly_progress(records["anna"], g, TODAY))
    print("  " + session_feedback(records["anna"][-1], g))


if __name__ == "__main__":
    main()
