"""Toothbrush / brush-head replacement reminder.

ADA: replace the toothbrush (or electric brush head) every 3-4 months, or
sooner if the bristles are visibly matted or frayed
(https://www.ada.org/resources/ada-library/oral-health-topics/toothbrushes).
Swapping it after a cold/flu is a common extra tip. The app counts the uses
anyway, so it can show both the age and the number of uses.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date

from .coach import BrushRecord

REPLACE_AFTER_DAYS = 90  # remind at 3 months (the ADA range is 3-4 months)
WARN_BEFORE_DAYS = 7


@dataclass(frozen=True)
class BrushHead:
    installed: date
    kind: str = "manual"  # "manual" or "electric"


@dataclass(frozen=True)
class HeadStatus:
    age_days: int
    uses: int
    due: bool
    soon: bool
    message: str


def head_status(head: BrushHead, records: list[BrushRecord], today: date,
                after_illness: bool = False) -> HeadStatus:
    age = (today - head.installed).days
    uses = sum(1 for r in records if r.when.date() >= head.installed)
    thing = "fogkefefejet" if head.kind == "electric" else "fogkefét"
    if after_illness:
        msg = f"Betegség után érdemes új {thing} használni, hogy ne maradjanak kórokozók a sörtéken."
        return HeadStatus(age, uses, True, False, msg)
    if age >= REPLACE_AFTER_DAYS:
        msg = (f"Ideje új {thing} venni: {age} napja ({uses} fogmosás) használod. "
               "A fogorvosok 3–4 havonta javasolják a cserét.")
        return HeadStatus(age, uses, True, False, msg)
    if age >= REPLACE_AFTER_DAYS - WARN_BEFORE_DAYS:
        msg = f"Egy héten belül esedékes a csere: {age} napja ({uses} fogmosás) használod."
        return HeadStatus(age, uses, False, True, msg)
    msg = (f"{age} napos, {uses} fogmosás. Ha a sörték szétállnak vagy elhajlottak, "
           "cseréld hamarabb.")
    return HeadStatus(age, uses, False, False, msg)
