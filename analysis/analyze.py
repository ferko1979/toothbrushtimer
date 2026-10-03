"""Analyse toothbrushing recordings and plot what the detector sees.

    python analyze.py recordings/*.m4a --out out/
    python analyze.py recordings/*.wav --out out/ --yamnet
    python analyze.py recordings/*.m4a --out out/ --model model.json

With --model (see train.py) the full session logic runs: water cue ->
brushing (scrubbing or sonic hum) -> rinse, with a water-waste report at the
end (--locale hu|us). Without it the hand-written rule-based scores are used.

For every input file a PNG is written to --out, plus summary.csv for all
files. If a file name contains `__truth<N>s` (e.g. `kezi_1m__truth120s.m4a`)
the estimated brushing time is compared with N seconds.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import sys

import numpy as np

from brushdetect import SR, TimerConfig, compute_features, load_audio, run_timer


def parse_truth(path: str) -> float | None:
    m = re.search(r"__truth(\d+)s", os.path.basename(path))
    return float(m.group(1)) if m else None


def plot(path, x, feats, sessions, tcfg, yam, out_png):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(5, 1, figsize=(14, 13), sharex=True,
                             gridspec_kw={"height_ratios": [2, 1, 1, 1, 1.4]})
    ax = axes[0]
    ax.specgram(x + 1e-9, NFFT=512, Fs=SR, noverlap=256, cmap="magma", vmin=-120)
    ax.set_ylabel("Hz")
    ax.set_title("Spektrogram")

    ax = axes[1]
    ax.plot(feats.t, feats.energy_scrub_db, label="súrolási sáv (2–7 kHz)")
    ax.plot(feats.t, feats.floor_scrub_db, "--", label="zajszint (súrolási sáv)")
    ax.plot(feats.t, feats.energy_total_db, alpha=0.6, label="teljes sáv")
    ax.plot(feats.t, feats.floor_total_db, ":", label="zajszint (teljes)")
    ax.set_ylabel("dB")
    ax.legend(loc="upper right", fontsize=8)

    ax = axes[2]
    ax.plot(feats.t, feats.rhythm_ratio, label="ritmusarány (1,5–7 Hz)")
    ax.plot(feats.t, feats.mod_depth, label="modulációs mélység")
    ax2 = ax.twinx()
    ax2.plot(feats.t, feats.rhythm_peak_hz, ".", ms=3, color="gray", label="ütemfrekvencia")
    ax2.set_ylabel("Hz")
    ax.set_ylim(0, 1.5)
    ax.legend(loc="upper left", fontsize=8)
    ax2.legend(loc="upper right", fontsize=8)

    ax = axes[3]
    ax.plot(feats.t, feats.tonal_prom_db, label="tonalitás (csúcs a medián felett)")
    ax3 = ax.twinx()
    ax3.plot(feats.t, feats.tonal_peak_hz, ".", ms=3, color="gray", label="csúcsfrekvencia")
    ax3.set_ylabel("Hz")
    ax.set_ylabel("dB")
    ax.legend(loc="upper left", fontsize=8)
    ax3.legend(loc="upper right", fontsize=8)

    ax = axes[4]
    ax.plot(feats.t, feats.manual_score, label="kézi fogkefe")
    ax.plot(feats.t, feats.electric_score, label="elektromos fogkefe")
    ax.plot(feats.t, feats.water_score, alpha=0.6, label="víz (kísérleti)")
    if yam is not None:
        yt, groups, _ = yam
        for g, s in groups.items():
            ax.plot(yt, s, "--", lw=1, label=f"YAMNet: {g}")
    ax.axhline(tcfg.on, color="k", lw=0.5, ls=":")
    ax.axhline(tcfg.off, color="k", lw=0.5, ls=":")
    for s in sessions:
        for a, b in s.intervals:
            for axx in axes:
                axx.axvspan(a, b, color="green", alpha=0.12)
    ax.set_ylim(-0.05, 1.05)
    ax.set_ylabel("pontszám")
    ax.set_xlabel("idő (s)  —  zöld sáv = mértnek számított fogmosás")
    ax.legend(loc="upper right", fontsize=8, ncol=2)

    total = sum(s.active_s for s in sessions)
    fig.suptitle(f"{os.path.basename(path)}   becsült fogmosási idő: {total:.0f} s")
    fig.tight_layout()
    fig.savefig(out_png, dpi=110)
    plt.close(fig)


def plot_session(path, x, sc, sessions, events, out_png):
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(2, 1, figsize=(14, 7), sharex=True,
                             gridspec_kw={"height_ratios": [2, 1.3]})
    axes[0].specgram(x + 1e-9, NFFT=512, Fs=SR, noverlap=256, cmap="magma", vmin=-120)
    axes[0].set_ylabel("Hz")
    ax = axes[1]
    ax.plot(sc.t, sc.water, color="C0", label="víz")
    ax.plot(sc.t, sc.brush, color="C2", label="fogmosás (tanult)")
    ax.plot(sc.t, sc.sonic, color="C1", lw=0.8, label="szónikus zúgás")
    for s in sessions:
        for axx in axes:
            axx.axvspan(s.start, s.end, color="green", alpha=0.12)
    for t, e in events:
        if e in ("water_start", "water_stop", "brushing_detected", "rinse_start", "waste_icon_on"):
            ax.axvline(t, color="red" if e == "waste_icon_on" else "gray", lw=0.7, ls="--")
            ax.text(t, 1.02, e, rotation=90, fontsize=7, va="bottom")
    ax.set_ylim(-0.05, 1.05)
    ax.set_xlabel("idő (s)  —  zöld sáv = mért fogmosás")
    ax.legend(loc="center right", fontsize=8)
    title = ", ".join(f"{s.start:.1f}–{s.end:.1f} s ({s.duration_s:.0f} s, víz {s.water_running_s:.0f} s)"
                      for s in sessions) or "nincs fogmosás"
    fig.suptitle(f"{os.path.basename(path)}   {title}")
    fig.tight_layout()
    fig.savefig(out_png, dpi=110)
    plt.close(fig)


def run_session_mode(args) -> list[dict]:
    from brushdetect.learned import load_heads
    from brushdetect.pipeline import score_recording
    from brushdetect.session import run_sessions
    from brushdetect.sonic import describe_tone
    from brushdetect.water_report import LOCALES, format_report

    heads = load_heads(args.model)
    loc = LOCALES[args.locale]
    types = {}
    if args.labels:
        from train import read_labels

        types = {os.path.abspath(p): info["type"] for p, info in read_labels(args.labels).items()}
    rows = []
    for path in args.files:
        x = load_audio(path)
        sc = score_recording(x, heads)
        brush_type = types.get(os.path.abspath(path)) or args.brush_type
        # The app asks the user for the brush type. With a manual brush a
        # sonic hum belongs to someone/something else, so it must not count.
        sonic = np.zeros_like(sc.sonic) if brush_type == "manual" else sc.sonic
        sessions, events = run_sessions(sc.t, sc.water, sc.brush, sonic, sc.hop_s)
        print(f"\n=== {os.path.basename(path)} (fogkefe: {brush_type}) ===")
        print("  események: " + ", ".join(f"{t:.1f}s {e}" for t, e in events))
        for s in sessions:
            in_s = (sc.t >= s.start) & (sc.t <= s.end) & (sonic > 0.5)
            tone = describe_tone(float(np.median(sc.sonic_f0[in_s]))) if in_s.sum() >= 4 else ""
            if brush_type == "manual":
                kind = "kézi fogkefe (súrolás alapján)"
            elif brush_type == "electric":
                kind = tone or "elektromos fogkefe (stabil motorhangot nem hallottam, súrolás alapján mérve)"
            else:
                kind = tone or "valószínűleg kézi fogkefe (nincs stabil motorhang)"
            print(f"  fogmosás: {s.start:.1f}–{s.end:.1f} s  (indítás: "
                  f"{'víz elzárása' if s.cue == 'water' else 'víz nélkül'})")
            print(f"  hang alapján: {kind}")
            print("  " + format_report(s.duration_s, s.water_running_s, loc).replace("\n", "\n  "))
            rows.append({"file": os.path.basename(path), "start_s": round(s.start, 1),
                         "end_s": round(s.end, 1), "duration_s": round(s.duration_s, 1),
                         "water_running_s": round(s.water_running_s, 1),
                         "wasted_water": s.wasted_water, "brush": kind})
        if not sessions:
            print("  nem észleltem fogmosást")
            rows.append({"file": os.path.basename(path)})
        if not args.no_plot:
            png = os.path.join(args.out, os.path.splitext(os.path.basename(path))[0] + ".png")
            plot_session(path, x, sc, sessions, events, png)
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", default="out")
    ap.add_argument("--yamnet", action="store_true", help="also run YAMNet (needs tensorflow)")
    ap.add_argument("--model", help="learned model JSON from train.py")
    ap.add_argument("--brush-type", choices=["auto", "manual", "electric"], default="auto",
                    help="what the user said they brush with (the app asks this)")
    ap.add_argument("--labels", help="labels.csv; its brush_type column overrides --brush-type per file")
    ap.add_argument("--locale", choices=["hu", "us"], default="hu",
                    help="units, prices and language of the water report")
    ap.add_argument("--no-plot", action="store_true")
    args = ap.parse_args(argv)

    os.makedirs(args.out, exist_ok=True)
    if args.model:
        rows = run_session_mode(args)
        _write_summary(args.out, rows)
        return rows

    tcfg = TimerConfig()
    rows = []
    for path in args.files:
        x = load_audio(path)
        feats = compute_features(x)
        sessions = run_timer(feats.t, feats.score, feats.hop_s, tcfg)
        total = sum(s.active_s for s in sessions)
        truth = parse_truth(path)

        yam = None
        if args.yamnet:
            try:
                from brushdetect.yamnet import yamnet_scores

                yam = yamnet_scores(x)
            except Exception as e:  # missing tensorflow, no network, ...
                print(f"  ! YAMNet kihagyva ({type(e).__name__}: {e})", file=sys.stderr)
                args.yamnet = False

        row = {
            "file": os.path.basename(path),
            "duration_s": round(len(x) / SR, 1),
            "estimated_s": round(total, 1),
            "truth_s": truth if truth is not None else "",
            "error_s": round(total - truth, 1) if truth is not None else "",
            "sessions": len(sessions),
            "mean_rhythm_hz": round(float(np.median(feats.rhythm_peak_hz[feats.manual_score > 0.5])), 2)
            if np.any(feats.manual_score > 0.5) else "",
            "tonal_peak_hz": round(float(np.median(feats.tonal_peak_hz[feats.electric_score > 0.5])), 1)
            if np.any(feats.electric_score > 0.5) else "",
        }
        if yam is not None:
            row["yamnet_toothbrush_max"] = round(float(yam[1]["toothbrush"].max()), 3)
        rows.append(row)

        msg = f"{row['file']:<40} becsült: {total:6.1f} s"
        if truth is not None:
            msg += f"   valós: {truth:6.1f} s   eltérés: {total - truth:+6.1f} s"
        print(msg)
        for s in sessions:
            print(f"    munkamenet {s.start:6.1f}–{s.end:6.1f} s, aktív {s.active_s:5.1f} s")

        if not args.no_plot:
            png = os.path.join(args.out, os.path.splitext(row["file"])[0] + ".png")
            plot(path, x, feats, sessions, tcfg, yam, png)

    _write_summary(args.out, rows)
    return rows


def _write_summary(out_dir, rows):
    keys = list(dict.fromkeys(k for r in rows for k in r))
    with open(os.path.join(out_dir, "summary.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)
    print(f"\nÖsszesítés: {os.path.join(out_dir, 'summary.csv')}")


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
