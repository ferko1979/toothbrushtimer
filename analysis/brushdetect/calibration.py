"""Personal calibration.

1. Brush tone: after the first few sessions with an electric (sonic) brush,
   remember its frequency (e.g. 256 Hz) and from then on only accept a hum
   within +-`tolerance_hz` of it. Fewer false alarms from other hums.
2. Tap flow: "fill a 1 litre bottle and press stop" -> litres/minute of your
   own tap, used instead of the country default in the water report.
"""

from __future__ import annotations

from dataclasses import dataclass, field, replace
from statistics import median

from .sonic import SonicConfig
from .water_report import WaterLocale

SESSIONS_NEEDED = 3


@dataclass
class BrushCalibration:
    sessions_needed: int = SESSIONS_NEEDED
    agree_hz: float = 5.0
    tolerance_hz: float = 10.0
    _f0s: list[float] = field(default_factory=list)

    def add_session(self, f0_hz: float | None) -> None:
        """Median sonic frequency of one detected session (None if no hum was heard)."""
        if f0_hz:
            self._f0s.append(float(f0_hz))

    @property
    def brush_f0(self) -> float | None:
        recent = self._f0s[-self.sessions_needed:]
        if len(recent) < self.sessions_needed:
            return None
        m = median(recent)
        return m if all(abs(f - m) <= self.agree_hz for f in recent) else None

    @property
    def remaining(self) -> int:
        return max(self.sessions_needed - len(self._f0s), 0)

    def sonic_config(self, base: SonicConfig | None = None) -> SonicConfig:
        base = base or SonicConfig()
        f0 = self.brush_f0
        if f0 is None:
            return base
        return replace(base, band_hz=(f0 - self.tolerance_hz, f0 + self.tolerance_hz))

    def status_text(self) -> str:
        if self.brush_f0 is not None:
            return f"Kalibrálva: a fogkeféd {self.brush_f0:.0f} Hz-en zúg."
        if self.remaining:
            return f"Kalibráció: még {self.remaining} fogmosás kell a fogkeféd hangjának megtanulásához."
        return "Kalibráció: a fogkefe hangja még nem egyértelmű, folytatom a tanulást."


def tap_flow_from_measurement(litres: float, seconds: float) -> float:
    """Litres per minute from a bucket/bottle test."""
    if litres <= 0 or seconds <= 0:
        raise ValueError("litres and seconds must be positive")
    flow = litres / seconds * 60.0
    if not 1.0 <= flow <= 30.0:
        raise ValueError(f"{flow:.1f} l/perc nem tűnik reálisnak (1–30 l/perc)")
    return flow


def water_locale_for(base: WaterLocale, tap_flow_l_per_min: float | None) -> WaterLocale:
    return base if tap_flow_l_per_min is None else replace(base, flow_l_per_min=tap_flow_l_per_min)
