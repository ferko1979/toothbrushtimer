"""Brushing reminders: after waking up, before bedtime, plus a follow-up.

Defaults (all switchable in the settings):
  * bedtime reminder ON, 15 min before the configured bedtime
  * morning reminder ON, from the configured wake-up time; shown when the
    phone is first picked up / unlocked after waking (see below)
  * follow-up ON: if nobody brushed within `followup_after_min` after a
    reminder, one more (up to `max_followups`)
  * extra evening reminder (e.g. after dinner) OFF

"First pick-up": Android can react to the first unlock after the wake-up
time (ACTION_USER_PRESENT while the app's process is alive) and call
on_first_unlock(). iOS does not tell apps about unlocks, so there the
morning reminder is a local notification scheduled at the wake-up time;
it is waiting on the lock screen when the phone is first picked up.

Opening the app from one of these notifications "arms" listening: the app
expects brushing right away (see listening.py).
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, time, timedelta

from .coach import BrushRecord, Goals

MORNING_WINDOW = (time(4, 0), time(12, 0))
EVENING_WINDOW = (time(17, 0), time(23, 59, 59))


@dataclass(frozen=True)
class ReminderSettings:
    enabled: bool = True
    morning_enabled: bool = True
    wake_time: time = time(7, 0)
    bedtime_enabled: bool = True
    bedtime: time = time(22, 30)
    bedtime_lead_min: int = 15
    evening_enabled: bool = False
    evening_time: time = time(20, 0)
    followup_enabled: bool = True
    followup_after_min: int = 20
    max_followups: int = 1


@dataclass(frozen=True)
class Reminder:
    key: str  # "morning", "bedtime", "evening", "<base>_followup<n>"
    text: str
    arm_listening: bool = True  # opening it makes the app expect brushing


TEXTS = {
    "morning": "Jó reggelt! Kezdd a napot 2 perc fogmosással. 🪥",
    "bedtime": "Hamarosan lefekvés: még hiányzik az esti fogmosás. Éjszaka kevesebb nyál termelődik, "
               "ilyenkor a legfontosabb a tiszta fog.",
    "evening": "Esti fogmosás: 2 perc, és kész is vagy a mai céllal.",
    "followup": "Még mindig vár a fogkefe. 😉 Nyisd meg az appot, és kezdheted.",
}


def _in(t: time, window) -> bool:
    return window[0] <= t <= window[1]


def _brushed_since(records, since: datetime) -> bool:
    return any(r.when >= since for r in records)


def _base_due(now: datetime, records, goals: Goals, s: ReminderSettings) -> list[str]:
    today = [r for r in records if r.when.date() == now.date()]
    morning_done = any(_in(r.when.time(), MORNING_WINDOW) for r in today)
    evening_done = any(_in(r.when.time(), EVENING_WINDOW) for r in today)
    bedtime_at = datetime.combine(now.date(), s.bedtime) - timedelta(minutes=s.bedtime_lead_min)
    out = []
    if s.morning_enabled and not morning_done and s.wake_time <= now.time() < MORNING_WINDOW[1]:
        out.append("morning")
    if goals.per_day >= 2 and not evening_done:
        if s.bedtime_enabled and now >= bedtime_at:
            out.append("bedtime")
        elif s.evening_enabled and now.time() >= s.evening_time:
            out.append("evening")
    return out


def due_reminders(now: datetime, records: list[BrushRecord], goals: Goals,
                  settings: ReminderSettings, sent: dict[str, datetime]) -> list[Reminder]:
    """Reminders to fire now. `sent` maps keys already sent today to when they were sent."""
    if not settings.enabled:
        return []
    out = []
    for key in _base_due(now, records, goals, settings):
        if key not in sent:
            out.append(Reminder(key, TEXTS[key]))
            continue
        if not settings.followup_enabled:
            continue
        # Follow-ups: one after another, each `followup_after_min` after the previous.
        last_key, last_at = key, sent[key]
        for n in range(1, settings.max_followups + 1):
            fk = f"{key}_followup{n}"
            if fk in sent:
                last_key, last_at = fk, sent[fk]
                continue
            if (now >= last_at + timedelta(minutes=settings.followup_after_min)
                    and not _brushed_since(records, sent[key])):
                out.append(Reminder(fk, TEXTS["followup"]))
            break
    return out


def on_first_unlock(now: datetime, records: list[BrushRecord], goals: Goals,
                    settings: ReminderSettings, sent: dict[str, datetime]) -> Reminder | None:
    """Android: the phone was unlocked for the first time today -> morning reminder now."""
    if not (settings.enabled and settings.morning_enabled) or "morning" in sent:
        return None
    due = [r for r in due_reminders(now, records, goals, settings, sent) if r.key == "morning"]
    return due[0] if due else None
