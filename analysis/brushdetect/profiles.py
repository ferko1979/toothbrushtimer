"""Family profiles: separate goals/history per person, kid-friendly wording,
and a parent overview.

Sound alone cannot tell who is brushing. A watch is personal, so it maps to
one profile; on a shared phone the person picks their avatar when the
session starts (the app pre-selects the most likely one by time of day).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date

from .coach import (ACHIEVEMENTS, BrushRecord, Goals, earned_achievements, perfect_streak,
                    is_perfect_day)


@dataclass
class Profile:
    id: str
    name: str
    child: bool = False
    goals: Goals = field(default_factory=Goals)  # ADA: 2x2 min for children too
    brush_type: str = "manual"
    age: int | None = None
    can_read: bool = True  # False -> picture-only UI and spoken feedback
    avatar: str | None = None  # avatar id from avatars.AVATARS


# Kid-friendly names for the same achievements.
CHILD_TITLES = {
    "first_brush": "Fogvédő tanonc",
    "above_average": "Gyorsabb a cukorkaszörnynél",
    "goal_reached": "Két perc hős",
    "perfect_day": "Csillogó mosoly",
    "streak_3": "Fogtündér barátja",
    "streak_7": "Fogtündér kedvence",
    "streak_30": "Fogkirály / Fogkirálynő",
    "water_saver_10": "Vízcsepp-mentő",
    "water_saver_50": "Óceán őrzője",
    "improver": "Szintlépés",
}

STICKERS_PER_FIGURE = 7


def achievement_title(key: str, profile: Profile) -> str:
    return CHILD_TITLES.get(key, ACHIEVEMENTS[key].title) if profile.child else ACHIEVEMENTS[key].title


def child_feedback(duration_s: float, goals: Goals) -> str:
    if duration_s >= goals.target_s:
        return "Hurrá! Végig kitartottál, a fogaid ragyognak! ⭐ Kaptál egy matricát."
    if duration_s >= goals.target_s / 2:
        return "Ügyes vagy, már több mint félúton jártál! Legközelebb a végéig, és jár a matrica!"
    return "Jó kezdés! A cukorkaszörnyek még bújkálnak. Holnap mosd tovább, amíg a kör be nem telik!"


@dataclass(frozen=True)
class Feedback:
    text: str
    icons: str  # shown big; for non-readers this *is* the message
    speak: bool  # read the text aloud (text-to-speech)


def feedback_for(profile: Profile, duration_s: float) -> Feedback:
    """Feedback adapted to the person: adults text, kids playful, non-readers icons + voice."""
    from .coach import BrushRecord, session_feedback
    from datetime import datetime

    g = profile.goals
    if not profile.child:
        return Feedback(session_feedback(BrushRecord(datetime.now(), duration_s), g), "", False)
    stars = 3 if duration_s >= g.target_s else 2 if duration_s >= g.target_s / 2 else 1
    icons = "⭐" * stars + ("🏅" if stars == 3 else "")
    return Feedback(child_feedback(duration_s, g), icons, speak=not profile.can_read)


def stickers(records: list[BrushRecord], goals: Goals) -> tuple[int, int]:
    """(stickers, collectible figures): one sticker per perfect day, a figure per 7."""
    days = {}
    for r in records:
        days.setdefault(r.when.date(), []).append(r)
    n = sum(is_perfect_day(rs, goals) for rs in days.values())
    return n, n // STICKERS_PER_FIGURE


def family_overview(profiles: list[Profile], records: dict[str, list[BrushRecord]], today: date) -> str:
    lines = [f"Családi áttekintés – {today.isoformat()}"]
    for p in profiles:
        rs = records.get(p.id, [])
        todays = [r for r in rs if r.when.date() == today]
        good = sum(r.duration_s >= p.goals.target_s for r in todays)
        streak = perfect_streak(rs, p.goals, today)
        line = (f"  {'🧒' if p.child else '🧑'} {p.name}: ma {len(todays)}/{p.goals.per_day} "
                f"(célidőt elérte: {good}), sorozat: {streak} nap")
        if p.child:
            s, figs = stickers(rs, p.goals)
            line += f", matricák: {s}, figurák: {figs}"
        if len(todays) < p.goals.per_day:
            line += "  ← még hiányzik"
        lines.append(line)
        earned = earned_achievements(rs, p.goals, today)
        if earned:
            lines.append("      kitüntetések: " + ", ".join(achievement_title(k, p) for k in sorted(earned)))
    return "\n".join(lines)
