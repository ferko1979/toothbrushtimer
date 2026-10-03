"""Water-waste estimate: how much water ran while brushing, and what that means.

All numbers are rough, adjustable defaults (pass your own WaterLocale):

* Flow: a typical bathroom tap delivers ~6-9 L/min. US federal maximum for
  lavatory faucets is 2.2 gal/min, WaterSense-labelled ones 1.5 gal/min
  (https://basc.pnnl.gov/resource-guides/bathroom-faucets,
   https://www.energy.gov/cmei/femp/best-management-practice-7-faucets-and-showerheads).
* Price (water + sewage, residential, gross):
  Budapest 2025/26: 218.9 Ft/m3 water + 433.72 Ft/m3 sewage ~ 653 Ft/m3
  (https://www.vizmuvek.hu/files/public/new/altalanos-pdf/dijszabas/szolgaltatasok-dijszabasa.pdf,
   https://www.fcsm.hu/ugyfelszolgalat/budapest/szolgaltatasi-dijak/csatornahasznalati-dij).
  US: typically $9-16 per 1,000 gallons incl. sewer -> ~$0.0125/gal
  (https://www.balkanplumbing.com/water-bill-calculator/).
* Daily household use per person: Hungary ~105 L (2024,
  https://www.forsense.hu/mennyi-vizet-fogyasztanak-a-magyar-haztartasok/),
  US ~82 gal (EPA WaterSense, https://www.epa.gov/watersense/statistics-and-facts).
* Recommended drinking water: ~2 L/day.
"""

from __future__ import annotations

from dataclasses import dataclass

L_PER_GAL = 3.785411784


@dataclass(frozen=True)
class WaterLocale:
    name: str
    flow_l_per_min: float
    price_per_litre: float
    currency: str
    daily_use_per_person_l: float
    glass_l: float
    glass_name: str
    imperial: bool


HU = WaterLocale("hu", flow_l_per_min=8.0, price_per_litre=0.653, currency="Ft",
                 daily_use_per_person_l=105.0, glass_l=0.25, glass_name="pohár (2,5 dl)",
                 imperial=False)
US = WaterLocale("us", flow_l_per_min=2.2 * L_PER_GAL, price_per_litre=0.0125 / L_PER_GAL,
                 currency="$", daily_use_per_person_l=82 * L_PER_GAL, glass_l=0.2366,
                 glass_name="8 oz glass", imperial=True)
LOCALES = {"hu": HU, "us": US}
DRINKING_L_PER_DAY = 2.0


@dataclass
class WaterReport:
    seconds: float
    litres: float
    gallons: float
    cost: float
    glasses: float
    pct_daily_use: float
    pct_drinking: float
    litres_per_year: float  # if it happens twice a day, every day
    cost_per_year: float


def water_report(seconds: float, loc: WaterLocale = HU) -> WaterReport:
    litres = seconds / 60.0 * loc.flow_l_per_min
    per_year = litres * 2 * 365
    return WaterReport(
        seconds=seconds,
        litres=litres,
        gallons=litres / L_PER_GAL,
        cost=litres * loc.price_per_litre,
        glasses=litres / loc.glass_l,
        pct_daily_use=100 * litres / loc.daily_use_per_person_l,
        pct_drinking=100 * litres / DRINKING_L_PER_DAY,
        litres_per_year=per_year,
        cost_per_year=per_year * loc.price_per_litre,
    )


def _num(x: float, nd: int = 1) -> str:
    return f"{x:,.{nd}f}".replace(",", " ").replace(".", ",")


def format_report(brushing_s: float, water_running_s: float, loc: WaterLocale = HU) -> str:
    """User-facing end-of-session message."""
    if loc.imperial:
        return _format_us(brushing_s, water_running_s, loc)
    lines = [f"Fogmosás időtartama: {brushing_s:.0f} s"]
    if water_running_s >= 5:
        r = water_report(water_running_s, loc)
        lines += [
            f"⚠️ VÍZPAZARLÁS: a csap {water_running_s:.0f} másodpercig folyt fogmosás közben!",
            f"   Ez kb. {_num(r.litres)} liter víz (~{_num(r.glasses, 0)} {loc.glass_name}), "
            f"kb. {_num(r.cost, 1)} {loc.currency}.",
            f"   Ennyi víz egy ember napi vízfogyasztásának kb. {_num(r.pct_daily_use, 0)}%-a, "
            f"a napi ajánlott ivóvízmennyiség {_num(r.pct_drinking, 0)}%-a.",
            f"   Ha minden reggel és este így mosol fogat, az évente kb. {_num(r.litres_per_year / 1000, 1)} m³ "
            f"(~{_num(r.cost_per_year, 0)} {loc.currency}).",
            "   Tipp: a fogkefe benedvesítése után zárd el a csapot, és csak öblítéskor nyisd meg újra.",
        ]
    else:
        r = water_report(brushing_s, loc)
        lines += [
            "💧 Szép munka, fogmosás közben elzártad a csapot!",
            f"   Ha folyt volna, kb. {_num(r.litres)} liter (~{_num(r.glasses, 0)} pohár) víz "
            f"folyt volna el feleslegesen, évente kb. {_num(r.litres_per_year / 1000, 1)} m³.",
        ]
    return "\n".join(lines)


def _format_us(brushing_s: float, water_running_s: float, loc: WaterLocale) -> str:
    lines = [f"Brushing time: {brushing_s:.0f} s"]
    if water_running_s >= 5:
        r = water_report(water_running_s, loc)
        lines += [
            f"⚠️ WATER WASTE: the tap ran for {water_running_s:.0f} s while you brushed!",
            f"   That is about {r.gallons:.1f} gallons ({r.litres:.1f} L, ~{r.glasses:.0f} {loc.glass_name}es), "
            f"about {loc.currency}{r.cost:.3f}.",
            f"   That's ~{r.pct_daily_use:.0f}% of an average American's daily home water use.",
            f"   Twice a day for a year: ~{r.litres_per_year / L_PER_GAL:,.0f} gallons "
            f"(~{loc.currency}{r.cost_per_year:.0f}).",
            "   Tip: turn the tap off after wetting your brush and back on only to rinse.",
        ]
    else:
        r = water_report(brushing_s, loc)
        lines += [
            "💧 Nice, you kept the tap off while brushing!",
            f"   A running tap would have wasted ~{r.gallons:.1f} gallons "
            f"(~{r.litres_per_year / L_PER_GAL:,.0f} gallons a year).",
        ]
    return "\n".join(lines)
