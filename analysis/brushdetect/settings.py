"""All user-facing switches in one place (the Settings screen is generated from FEATURES).

Every optional feature can be turned on/off. Defaults: the core experience is
on; anything that shares data or adds extra tracking is off until the user
opts in. Platform-only features list the platforms that have them.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, replace
from datetime import time

from .reminders import ReminderSettings

ALL = ("ios", "watchos", "android", "wearos")


@dataclass(frozen=True)
class Feature:
    key: str
    title: str
    description: str
    default: bool
    group: str
    platforms: tuple[str, ...] = ALL


FEATURES = [
    # Mérés
    Feature("auto_detect", "Automatikus felismerés",
            "A víz, a súrolás és a szónikus zúgás alapján indul és áll le a mérés.", True, "Mérés"),
    Feature("keep_listening_when_placed", "Figyelés letett telefonnal",
            "Ha a telefon vízszintesen, nyugalomban fekszik, a képernyő lezárása után is figyel.", True, "Mérés",
            ("ios", "android")),
    Feature("calibration", "Kalibráció",
            "Az első 3 fogmosásból megtanulja a fogkeféd hangját és a fürdőszoba zaját.", True, "Mérés"),
    Feature("battery_saver", "Akkumulátorkímélő mód",
            "Csak akkor futtatja a felismerő modellt, ha egyáltalán hallatszik valami.", True, "Mérés"),
    # Fogmosás közben
    Feature("quadrant_cues", "Rezgés a negyedeknél",
            "Indításkor, 30/60/90 másodpercnél és a célidőnél jelez.", True, "Fogmosás közben"),
    Feature("spoken_feedback", "Felolvasott visszajelzés",
            "Gyerekeknél (és ha kéred, nálad is) felolvassa az üzeneteket.", True, "Fogmosás közben"),
    Feature("live_activity", "Élő kijelzés a lezárt képernyőn",
            "iPhone: élő tevékenység a lezárt képernyőn és a Dynamic Islanden; Android: folyamatos értesítés.",
            True, "Fogmosás közben", ("ios", "android")),
    # Víz
    Feature("water_warnings", "Vízpazarlás-figyelmeztetés",
            "Ikon, ha folyik a csap fogmosás közben, és összesítés a végén.", True, "Víz"),
    # Értesítések (részletek: ReminderSettings)
    Feature("notifications", "Emlékeztetők", "Reggel, lefekvés előtt és ismétlés.", True, "Értesítések"),
    Feature("brush_head_reminder", "Fogkefecsere-emlékeztető", "3 havonta, illetve betegség után.", True,
            "Értesítések"),
    # Motiváció
    Feature("achievements", "Kitüntetések és sorozatok", "", True, "Motiváció"),
    Feature("habit_tips", "Szokás-tippek", "Figyelmeztet, ha visszatérő rossz szokást lát.", True, "Motiváció"),
    Feature("watch_complication", "Számlapelem az órán", "A sorozat és a mai haladás a számlapon.", True,
            "Motiváció", ("watchos", "wearos")),
    # Kiegészítők
    Feature("floss_tracking", "Fogselyem követése",
            "Egy koppintással jelölheted fogmosás után (az ADA naponta egyszer javasolja).", False, "Kiegészítők"),
    Feature("mouthwash_tracking", "Szájvíz követése", "", False, "Kiegészítők"),
    Feature("voice_shortcuts", "Hangvezérlés",
            "„Hé Siri / Hé Google, fogmosás indul”.", True, "Kiegészítők"),
    # Adatok
    Feature("health_sync", "Mentés az Egészség appba", "Apple Health: Fogmosás.", False, "Adatok",
            ("ios", "watchos")),
    Feature("monthly_report", "Havi összefoglaló", "Kinyomtatható, a fogorvosnak is megmutatható.", True, "Adatok"),
    Feature("family_sync", "Családi szinkron",
            "A gyerekek órája és a szülő telefonja között (iCloud / Google, titkosítva).", False, "Adatok"),
    Feature("data_donation", "Adatfelajánlás a fejlesztéshez",
            "Névtelen hangjellemzők (hangfelvétel nélkül) a felismerés javításához.", False, "Adatok"),
]
FEATURE_KEYS = {f.key for f in FEATURES}


@dataclass(frozen=True)
class Settings:
    language: str = "hu"  # "hu" or "en"
    locale: str = "hu"  # units/prices for the water report: "hu" or "us"
    tap_flow_l_per_min: float | None = None  # measured by the user; None -> locale default
    reminders: ReminderSettings = field(default_factory=ReminderSettings)
    enabled: dict = field(default_factory=lambda: {f.key: f.default for f in FEATURES})

    def is_on(self, key: str, platform: str | None = None) -> bool:
        if key not in FEATURE_KEYS:
            raise KeyError(key)
        feat = next(f for f in FEATURES if f.key == key)
        if platform is not None and platform not in feat.platforms:
            return False
        return bool(self.enabled.get(key, feat.default))

    def toggle(self, key: str, on: bool) -> "Settings":
        if key not in FEATURE_KEYS:
            raise KeyError(key)
        return replace(self, enabled={**self.enabled, key: on})

    def screen(self, platform: str) -> dict[str, list[tuple[Feature, bool]]]:
        """Settings screen for one platform: group -> [(feature, on)]."""
        out: dict[str, list] = {}
        for f in FEATURES:
            if platform in f.platforms:
                out.setdefault(f.group, []).append((f, self.is_on(f.key)))
        return out

    # -- persistence ---------------------------------------------------------
    def to_json(self) -> str:
        r = self.reminders
        return json.dumps({
            "language": self.language, "locale": self.locale,
            "tap_flow_l_per_min": self.tap_flow_l_per_min, "enabled": self.enabled,
            "reminders": {k: (v.strftime("%H:%M") if isinstance(v, time) else v)
                          for k, v in r.__dict__.items()},
        }, ensure_ascii=False, indent=1)

    @classmethod
    def from_json(cls, text: str) -> "Settings":
        d = json.loads(text)
        rem = {k: (time.fromisoformat(v) if isinstance(v, str) else v) for k, v in d["reminders"].items()}
        defaults = {f.key: f.default for f in FEATURES}  # new features get their default
        enabled = {**defaults, **{k: v for k, v in d["enabled"].items() if k in FEATURE_KEYS}}
        return cls(d["language"], d["locale"], d["tap_flow_l_per_min"], ReminderSettings(**rem), enabled)
