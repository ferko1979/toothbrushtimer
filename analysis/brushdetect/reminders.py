"""Brushing reminders: morning, evening and a gentle nudge before bedtime.

due_reminders() is called periodically by the app (e.g. from a background
task every 15 min); it returns the reminders that should fire now and have
not been sent yet today.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time

from .coach import BrushRecord, Goals

MORNING_WINDOW = (time(4, 0), time(12, 0))
EVENING_WINDOW = (time(17, 0), time(23, 59, 59))


@dataclass(frozen=True)
class ReminderSettings:
    enabled: bool = True
    morning: time = time(7, 30)
    evening: time = time(21, 0)
    bedtime: time = time(22, 30)
    nudge_before_bed_min: int = 30


@dataclass(frozen=True)
class Reminder:
    key: str  # "morning", "evening", "bedtime_nudge"
    text: str


def _in(t: time, window) -> bool:
    return window[0] <= t <= window[1]


def due_reminders(now: datetime, records: list[BrushRecord], goals: Goals,
                  settings: ReminderSettings, already_sent: set[str]) -> list[Reminder]:
    if not settings.enabled:
        return []
    today = [r for r in records if r.when.date() == now.date()]
    if len(today) >= goals.per_day:
        return []
    morning_done = any(_in(r.when.time(), MORNING_WINDOW) for r in today)
    evening_done = any(_in(r.when.time(), EVENING_WINDOW) for r in today)
    nudge_at = (datetime.combine(now.date(), settings.bedtime).timestamp()
                - settings.nudge_before_bed_min * 60)

    out = []
    if not morning_done and settings.morning <= now.time() < MORNING_WINDOW[1]:
        out.append(Reminder("morning", "Jó reggelt! Ideje fogat mosni. 🪥"))
    if goals.per_day >= 2 and not evening_done:
        if settings.evening <= now.time() and now.timestamp() < nudge_at:
            out.append(Reminder("evening", "Esti fogmosás: 2 perc, és kész is vagy a mai céllal."))
        elif now.timestamp() >= nudge_at:
            out.append(Reminder("bedtime_nudge",
                                "Lefekvés előtt még hiányzik az esti fogmosás. "
                                "Éjszaka termelődik a legkevesebb nyál, ilyenkor a legfontosabb a tiszta fog."))
    return [r for r in out if r.key not in already_sent]
