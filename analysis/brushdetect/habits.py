"""Spot recurring bad habits in the last weeks and give a targeted tip."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, timedelta

from .coach import BrushRecord, Goals
from .reminders import EVENING_WINDOW, MORNING_WINDOW

RUSH_S = 30.0
OVERBRUSH_S = 240.0


@dataclass(frozen=True)
class Habit:
    key: str
    message: str


def _window(records, today: date, days: int, offset: int = 0):
    start = today - timedelta(days=days - 1 + offset)
    end = today - timedelta(days=offset)
    return [r for r in records if start <= r.when.date() <= end]


def _days_missing(records, today: date, window) -> int:
    have = {r.when.date() for r in records if window[0] <= r.when.time() <= window[1]}
    return sum((today - timedelta(days=i)) not in have for i in range(1, 8))  # last 7 full days


def _avg(rs):
    return sum(r.duration_s for r in rs) / len(rs) if rs else None


def detect_habits(records: list[BrushRecord], goals: Goals, today: date) -> list[Habit]:
    out = []
    last14 = _window(records, today, 14)
    last7 = _window(records, today, 7)
    if len(last14) >= 4:
        if sum(r.duration_s < RUSH_S for r in last14) / len(last14) >= 0.5:
            out.append(Habit("rushing",
                             f"Az utóbbi két hétben a fogmosások fele {RUSH_S:.0f} másodpercnél rövidebb volt. "
                             "Kövesd a negyedenkénti rezgést: minden jelzésnél válts a következő fogsornegyedre."))
        if sum(r.duration_s > OVERBRUSH_S for r in last14) / len(last14) >= 0.5:
            out.append(Habit("overbrushing",
                             "Gyakran 4 percnél is tovább mosol fogat. A 2–3 perc elég; a túl hosszú, erős "
                             "súrolás az ínyt és a zománcot koptathatja. Puha sörtéjű fogkefe ajánlott."))
    if records and goals.per_day >= 2:
        if _days_missing(records, today, EVENING_WINDOW) >= 3:
            out.append(Habit("evening_skipped",
                             "Az elmúlt héten legalább 3 este kimaradt a fogmosás. Az esti a legfontosabb: "
                             "éjszaka kevesebb nyál termelődik, ezért a lepedék könnyebben károsít. "
                             "Kapcsold be a lefekvés előtti emlékeztetőt!"))
        if _days_missing(records, today, MORNING_WINDOW) >= 3:
            out.append(Habit("morning_skipped",
                             "Az elmúlt héten legalább 3 reggel kimaradt a fogmosás. Próbáld egy meglévő "
                             "szokáshoz kötni (pl. reggeli után, öltözködés előtt)."))
    if sum(not r.tap_off for r in last7) >= 3:
        out.append(Habit("tap_running",
                         "Az elmúlt héten többször folyt a csap fogmosás közben. Nedvesítés után zárd el, "
                         "és csak öblítéskor nyisd meg újra."))
    weekday = [r for r in last14 if r.when.weekday() < 5]
    weekend = [r for r in last14 if r.when.weekday() >= 5]
    if len(weekday) >= 2 and len(weekend) >= 2 and _avg(weekend) < _avg(weekday) - 20:
        out.append(Habit("weekend_dip",
                         f"Hétvégén átlagosan {_avg(weekday) - _avg(weekend):.0f} másodperccel rövidebben mosol "
                         "fogat, mint hétköznap. A fogaidnak nincs hétvégéjük. 😉"))
    prev7 = _window(records, today, 7, offset=7)
    if len(last7) >= 3 and len(prev7) >= 3 and _avg(last7) < _avg(prev7) - 15:
        out.append(Habit("declining",
                         f"Az utóbbi héten {_avg(prev7) - _avg(last7):.0f} másodperccel rövidebbek a "
                         "fogmosásaid, mint előtte. Tűzz ki egy rövid célt: holnap legalább egyszer a teljes kör!"))
    return out
