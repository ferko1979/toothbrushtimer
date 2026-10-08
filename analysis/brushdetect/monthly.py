"""Monthly summary (also printable for the dentist)."""

from __future__ import annotations

from calendar import monthrange
from dataclasses import dataclass
from datetime import date, timedelta

from .coach import BrushRecord, Goals, is_perfect_day
from .reminders import EVENING_WINDOW, MORNING_WINDOW
from .water_report import HU, WaterLocale

MONTHS_HU = ["január", "február", "március", "április", "május", "június", "július",
             "augusztus", "szeptember", "október", "november", "december"]


@dataclass
class MonthlyReport:
    year: int
    month: int
    days_in_month: int
    sessions: int
    days_brushed: int
    avg_s: float
    pct_goal: float
    perfect_days: int
    best_streak: int
    morning: int
    evening: int
    tap_off_sessions: int
    water_saved_l: float
    water_wasted_l: float


def monthly_report(records: list[BrushRecord], goals: Goals, year: int, month: int,
                   loc: WaterLocale = HU) -> MonthlyReport:
    ndays = monthrange(year, month)[1]
    rs = [r for r in records if r.when.year == year and r.when.month == month]
    days: dict[date, list[BrushRecord]] = {}
    for r in rs:
        days.setdefault(r.when.date(), []).append(r)
    perfect = sorted(d for d, v in days.items() if is_perfect_day(v, goals))
    best = run = 0
    prev = None
    for d in perfect:
        run = run + 1 if prev and d - prev == timedelta(days=1) else 1
        best, prev = max(best, run), d
    flow_l_per_s = loc.flow_l_per_min / 60
    tap_off = [r for r in rs if r.tap_off]
    return MonthlyReport(
        year=year, month=month, days_in_month=ndays,
        sessions=len(rs), days_brushed=len(days),
        avg_s=sum(r.duration_s for r in rs) / len(rs) if rs else 0.0,
        pct_goal=100 * sum(r.duration_s >= goals.target_s for r in rs) / len(rs) if rs else 0.0,
        perfect_days=len(perfect), best_streak=best,
        morning=sum(MORNING_WINDOW[0] <= r.when.time() <= MORNING_WINDOW[1] for r in rs),
        evening=sum(EVENING_WINDOW[0] <= r.when.time() <= EVENING_WINDOW[1] for r in rs),
        tap_off_sessions=len(tap_off),
        water_saved_l=sum(r.duration_s for r in tap_off) * flow_l_per_s,
        water_wasted_l=sum(r.water_running_s for r in rs) * flow_l_per_s,
    )


def format_monthly(rep: MonthlyReport, goals: Goals, name: str = "") -> str:
    expected = rep.days_in_month * goals.per_day
    title = f"Havi fogmosás-összefoglaló – {rep.year}. {MONTHS_HU[rep.month - 1]}"
    lines = [title + (f" – {name}" if name else ""), "-" * len(title),
             f"Fogmosások: {rep.sessions} / {expected} tervezett "
             f"({rep.days_brushed} napon; reggel {rep.morning}, este {rep.evening})",
             f"Átlagos időtartam: {rep.avg_s:.0f} s (cél: {goals.target_s:.0f} s), "
             f"a célidőt elérte: {rep.pct_goal:.0f}%",
             f"Tökéletes napok: {rep.perfect_days}, leghosszabb sorozat: {rep.best_streak} nap",
             f"Elzárt csappal: {rep.tap_off_sessions} fogmosás, megtakarított víz kb. "
             f"{rep.water_saved_l:.0f} l"]
    if rep.water_wasted_l >= 1:
        lines.append(f"Fogmosás közben elfolyt víz: kb. {rep.water_wasted_l:.0f} l")
    lines.append("Mérés: a telefon/óra mikrofonja alapján, a készüléken feldolgozva (hangfelvétel nem készül).")
    return "\n".join(lines)
