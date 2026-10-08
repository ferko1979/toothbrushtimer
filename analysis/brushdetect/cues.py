"""Haptic/visual cues while brushing: one buzz per quadrant, a pattern at the goal.

The watch/phone calls CueTracker.update(elapsed_s) on every timer tick and
plays whatever cues it returns. progress() drives the circular indicator.
"""

from __future__ import annotations

from dataclasses import dataclass

QUADRANTS = ("jobb felső", "bal felső", "bal alsó", "jobb alsó")


@dataclass(frozen=True)
class Cue:
    at_s: float
    kind: str  # "start", "quadrant" (move on) or "done" (goal reached)
    quadrant: int  # quadrant to brush next, 1-4 (4 for "done")
    haptic: str  # pattern name for the app: "tap" or "success"
    text: str


def cue_schedule(target_s: float) -> list[Cue]:
    step = target_s / len(QUADRANTS)
    cues = [Cue(0.0, "start", 1, "tap", f"Kezdd a {QUADRANTS[0]} negyeddel")]
    cues += [Cue(step * k, "quadrant", k + 1, "tap", f"Jöhet a {QUADRANTS[k]} negyed")
            for k in range(1, len(QUADRANTS))]
    cues.append(Cue(target_s, "done", len(QUADRANTS), "success", "Kész, elérted a célidőt! 🎉"))
    return cues


@dataclass(frozen=True)
class Progress:
    fraction: float  # 0..1 of the goal (capped)
    quadrant: int  # 1-4, the quadrant to brush now
    quadrant_name: str
    remaining_s: float


def progress(elapsed_s: float, target_s: float) -> Progress:
    frac = min(max(elapsed_s / target_s, 0.0), 1.0)
    q = min(int(frac * len(QUADRANTS)), len(QUADRANTS) - 1)
    return Progress(frac, q + 1, QUADRANTS[q], max(target_s - elapsed_s, 0.0))


class CueTracker:
    """Returns each cue exactly once, as soon as its time has passed."""

    def __init__(self, target_s: float):
        self._pending = cue_schedule(target_s)

    def update(self, elapsed_s: float) -> list[Cue]:
        fired = [c for c in self._pending if c.at_s <= elapsed_s]
        self._pending = [c for c in self._pending if c.at_s > elapsed_s]
        return fired
