"""Export brushing records to health platforms and portable files.

* Apple Health: HealthKit has a category type for this,
  HKCategoryTypeIdentifierToothbrushingEvent; a sample carries a start and
  end date (duration = end - start) and the value HKCategoryValueNotApplicable.
  The iOS/watchOS app writes these with HKCategorySample.
* Android Health Connect has no toothbrushing / oral-hygiene record type
  (checked against the data-types list), so on Android the records stay in
  the app and can be exported as CSV/JSON instead.
"""

from __future__ import annotations

import csv
import io
import json
from datetime import timedelta

from .coach import BrushRecord

HK_TYPE = "HKCategoryTypeIdentifierToothbrushingEvent"
HK_VALUE = "HKCategoryValueNotApplicable"


def to_healthkit_samples(records: list[BrushRecord], source: str = "Fogmosás-időzítő") -> list[dict]:
    """Field-for-field description of the HKCategorySample objects to save."""
    return [{
        "type": HK_TYPE,
        "value": HK_VALUE,
        "startDate": r.when.isoformat(timespec="seconds"),
        "endDate": (r.when + timedelta(seconds=round(r.duration_s))).isoformat(timespec="seconds"),
        "metadata": {"HKWasUserEntered": False, "source": source,
                     "waterRunningSeconds": round(r.water_running_s, 1)},
    } for r in records]


def to_csv(records: list[BrushRecord]) -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["start", "duration_s", "water_running_s"])
    for r in sorted(records, key=lambda r: r.when):
        w.writerow([r.when.isoformat(), round(r.duration_s, 1), round(r.water_running_s, 1)])
    return buf.getvalue()


def to_json(records: list[BrushRecord]) -> str:
    return json.dumps([{"start": r.when.isoformat(), "duration_s": round(r.duration_s, 1),
                        "water_running_s": round(r.water_running_s, 1)}
                       for r in sorted(records, key=lambda r: r.when)], indent=1)
