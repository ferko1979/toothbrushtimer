"""Goals, feedback, achievements and encouragement on top of detected sessions.

Recommendation defaults (adjustable per user):
  * ADA: brush twice a day for two minutes
    (https://www.ada.org/resources/ada-library/oral-health-topics/home-care).
  * The average person actually brushes ~45 s; 120 s removes ~26% more plaque
    than 45 s (Creeth et al., J Dent Hyg 2009, https://jdh.adha.org/content/83/3/111).
  * Two minutes = 30 s per quadrant.

Pure functions over a list of BrushRecord, so the apps can keep the records in
their own storage and call the same logic.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta

RECOMMENDED_PER_DAY = 2
RECOMMENDED_S = 120.0
POPULATION_AVG_S = 45.0
QUADRANT_S = 30.0


@dataclass(frozen=True)
class Goals:
    per_day: int = RECOMMENDED_PER_DAY
    target_s: float = RECOMMENDED_S

    def __post_init__(self):
        if not 1 <= self.per_day <= 4:
            raise ValueError("per_day must be 1-4")
        if not 30 <= self.target_s <= 300:
            raise ValueError("target_s must be 30-300 s")

    def warnings(self) -> list[str]:
        w = []
        if self.target_s < RECOMMENDED_S:
            w.append(f"A fogorvosok legalább {RECOMMENDED_S:.0f} másodpercet javasolnak, "
                     f"a célod ({self.target_s:.0f} s) ennél rövidebb.")
        if self.per_day < RECOMMENDED_PER_DAY:
            w.append("A fogorvosok naponta kétszeri fogmosást javasolnak (reggel és lefekvés előtt).")
        return w


@dataclass(frozen=True)
class BrushRecord:
    when: datetime
    duration_s: float
    water_running_s: float = 0.0

    @property
    def tap_off(self) -> bool:
        return self.water_running_s < 5.0


@dataclass(frozen=True)
class Achievement:
    key: str
    title: str
    description: str


ACHIEVEMENTS = {a.key: a for a in [
    Achievement("first_brush", "Első lépés", "Az első mért fogmosás."),
    Achievement("above_average", "Átlag felett", f"Tovább mostál fogat, mint az átlagember ({POPULATION_AVG_S:.0f} s)."),
    Achievement("goal_reached", "Célba értél", "Először érted el a kitűzött fogmosási időt."),
    Achievement("perfect_day", "Tökéletes nap", "Egy napon belül minden fogmosás elérte a célidőt."),
    Achievement("streak_3", "Három nap sorban", "3 tökéletes nap egymás után."),
    Achievement("streak_7", "Egy hét fegyelem", "7 tökéletes nap egymás után."),
    Achievement("streak_30", "Egy hónap bajnok", "30 tökéletes nap egymás után."),
    Achievement("water_saver_10", "Víztakarékos", "10 fogmosás elzárt csappal."),
    Achievement("water_saver_50", "Vízőr", "50 fogmosás elzárt csappal."),
    Achievement("improver", "Fejlődés", "A heti átlagod legalább 15 másodperccel jobb, mint az előző héten."),
]}


def session_feedback(rec: BrushRecord, goals: Goals) -> str:
    """Message right after a session: praise or concrete encouragement."""
    d, t = rec.duration_s, goals.target_s
    if d >= t:
        msg = f"Szuper! {d:.0f} másodperc, elérted a {t:.0f} másodperces célt."
        if d > 2 * t:
            msg += " Nem kell ennél sokkal tovább: a túl hosszú, erős súrolás az ínyt is koptathatja."
        return msg
    missing = t - d
    quadrants_done = int(d // QUADRANT_S)
    msg = f"{d:.0f} másodperc, még {missing:.0f} másodperc hiányzott a célhoz."
    if d >= POPULATION_AVG_S:
        msg += f" Ez már több az átlagos {POPULATION_AVG_S:.0f} másodpercnél, így tovább!"
    else:
        msg += (f" Az átlagember kb. {POPULATION_AVG_S:.0f} másodpercig mos fogat. A 2 perces fogmosás "
                "kb. 26%-kal több lepedéket távolít el.")
    msg += (f" Tipp: mind a 4 fogsornegyedre jusson {QUADRANT_S:.0f} másodperc "
            f"(most kb. {quadrants_done} negyed jutott rá teljesen). Az óra/telefon jelez a negyedeknél.")
    return msg


def _by_day(records):
    days: dict[date, list[BrushRecord]] = {}
    for r in sorted(records, key=lambda r: r.when):
        days.setdefault(r.when.date(), []).append(r)
    return days


def is_perfect_day(day_records, goals: Goals) -> bool:
    good = [r for r in day_records if r.duration_s >= goals.target_s]
    return len(good) >= goals.per_day


def perfect_streak(records, goals: Goals, today: date) -> int:
    """Consecutive perfect days ending today (or yesterday, if today is not done yet)."""
    days = _by_day(records)
    d = today if is_perfect_day(days.get(today, []), goals) else today - timedelta(days=1)
    n = 0
    while is_perfect_day(days.get(d, []), goals):
        n += 1
        d -= timedelta(days=1)
    return n


def _week_avg(records, start: date):
    rs = [r.duration_s for r in records if start <= r.when.date() < start + timedelta(days=7)]
    return sum(rs) / len(rs) if rs else None


def earned_achievements(records, goals: Goals, today: date) -> set[str]:
    """All achievements earned by the given history (the app shows the new ones)."""
    out = set()
    if not records:
        return out
    out.add("first_brush")
    if any(r.duration_s >= POPULATION_AVG_S for r in records):
        out.add("above_average")
    if any(r.duration_s >= goals.target_s for r in records):
        out.add("goal_reached")
    days = _by_day(records)
    perfect = sorted(d for d, rs in days.items() if is_perfect_day(rs, goals))
    if perfect:
        out.add("perfect_day")
    best, run, prev = 0, 0, None
    for d in perfect:
        run = run + 1 if prev is not None and d - prev == timedelta(days=1) else 1
        best, prev = max(best, run), d
    for n in (3, 7, 30):
        if best >= n:
            out.add(f"streak_{n}")
    saved = sum(r.tap_off for r in records)
    if saved >= 10:
        out.add("water_saver_10")
    if saved >= 50:
        out.add("water_saver_50")
    this_week = today - timedelta(days=6)
    a, b = _week_avg(records, this_week), _week_avg(records, this_week - timedelta(days=7))
    if a is not None and b is not None and a - b >= 15:
        out.add("improver")
    return out


def new_achievements(before, after_records, goals: Goals, today: date) -> list[Achievement]:
    return [ACHIEVEMENTS[k] for k in sorted(earned_achievements(after_records, goals, today) - set(before))]


def daily_summary(records, goals: Goals, today: date) -> str:
    rs = _by_day(records).get(today, [])
    good = sum(r.duration_s >= goals.target_s for r in rs)
    left = max(goals.per_day - len(rs), 0)
    streak = perfect_streak(records, goals, today)
    parts = [f"Ma: {len(rs)}/{goals.per_day} fogmosás, ebből {good} érte el a {goals.target_s:.0f} s-ot."]
    if left:
        parts.append(f"Még {left} fogmosás van hátra mára.")
    elif good >= goals.per_day:
        parts.append("Tökéletes nap! 🎉")
    if streak >= 2:
        parts.append(f"{streak} tökéletes nap sorozatban.")
    return " ".join(parts)


def weekly_progress(records, goals: Goals, today: date) -> str:
    this_week = today - timedelta(days=6)
    a, b = _week_avg(records, this_week), _week_avg(records, this_week - timedelta(days=7))
    if a is None:
        return "Ezen a héten még nincs mért fogmosás."
    msg = f"Heti átlag: {a:.0f} s (cél: {goals.target_s:.0f} s)."
    if b is not None:
        diff = a - b
        if diff >= 5:
            msg += f" {diff:.0f} másodperccel jobb, mint a múlt héten, szép fejlődés!"
        elif diff <= -5:
            msg += f" {-diff:.0f} másodperccel kevesebb, mint a múlt héten. Próbáld meg a negyedenkénti jelzést követni!"
        else:
            msg += " Nagyjából ugyanannyi, mint a múlt héten."
    if a < goals.target_s:
        msg += f" Átlagban még {goals.target_s - a:.0f} másodperc hiányzik a célhoz."
    return msg
