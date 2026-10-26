"""Optional floss / mouthwash tracking (one tap after brushing).

ADA: clean between your teeth once a day (floss, interdental brush, water flosser).
https://www.ada.org/resources/ada-library/oral-health-topics/home-care
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta

KINDS = ("floss", "mouthwash")
NAMES = {"floss": "fogselyem", "mouthwash": "szájvíz"}


@dataclass(frozen=True)
class ExtraRecord:
    when: datetime
    kind: str

    def __post_init__(self):
        if self.kind not in KINDS:
            raise ValueError(self.kind)


def streak(records: list[ExtraRecord], kind: str, today: date) -> int:
    days = {r.when.date() for r in records if r.kind == kind}
    d = today if today in days else today - timedelta(days=1)
    n = 0
    while d in days:
        n += 1
        d -= timedelta(days=1)
    return n


def extras_status(records: list[ExtraRecord], kind: str, today: date) -> str:
    done = any(r.kind == kind and r.when.date() == today for r in records)
    s = streak(records, kind, today)
    name = NAMES[kind]
    if done:
        return f"{name.capitalize()}: ma kipipálva ✔️ ({s} nap sorozatban)."
    if kind == "floss":
        return "Fogselyem: ma még nem volt. A fogorvosok naponta egyszer javasolják a fogközök tisztítását."
    return f"{name.capitalize()}: ma még nem volt."
