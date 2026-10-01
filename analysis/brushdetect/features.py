"""Hand-crafted acoustic features for toothbrushing detection.

The pipeline is deliberately simple so it can later be ported 1:1 to
Swift (Accelerate/vDSP) and Kotlin:

    audio (16 kHz mono)
      -> band-pass 2-7 kHz           (bristle scrubbing lives here)
      -> 10 ms RMS envelope          (100 Hz envelope signal)
      -> 3 s windows, 0.5 s hop
           * rhythm ratio: share of envelope-modulation power in 1.5-7 Hz
             (back-and-forth strokes of a manual brush)
           * modulation depth: std/mean of the envelope
           * tonal prominence: strongest spectral peak in 70-2000 Hz
             above the median (motor hum of an electric brush)
           * spectral flatness (running water is flat, steady noise)
      -> adaptive noise floor (follows the quietest level, rises slowly)
      -> per-window scores in [0, 1]
"""

from __future__ import annotations

import shutil
import subprocess
from dataclasses import dataclass, field

import numpy as np
from scipy import signal

SR = 16000
ENV_HOP = 160  # 10 ms at 16 kHz
ENV_RATE = SR / ENV_HOP  # 100 Hz


@dataclass
class FeatureConfig:
    win_s: float = 3.0
    hop_s: float = 0.5
    scrub_band_hz: tuple[float, float] = (2000.0, 7000.0)
    broad_band_hz: tuple[float, float] = (100.0, 7000.0)
    rhythm_band_hz: tuple[float, float] = (1.5, 7.0)
    rhythm_ref_band_hz: tuple[float, float] = (0.5, 20.0)
    tonal_band_hz: tuple[float, float] = (70.0, 2000.0)
    # Noise floor: drops instantly to quieter levels, rises this many dB per second.
    floor_rise_db_per_s: float = 0.2
    # Score ramps (value at which score starts rising, value at which it is 1).
    snr_ramp_db: tuple[float, float] = (3.0, 9.0)
    rhythm_ramp: tuple[float, float] = (0.35, 0.6)
    depth_ramp: tuple[float, float] = (0.25, 0.5)
    tonal_ramp_db: tuple[float, float] = (15.0, 30.0)


@dataclass
class Features:
    t: np.ndarray  # window centre times (s)
    energy_scrub_db: np.ndarray
    energy_total_db: np.ndarray
    floor_scrub_db: np.ndarray
    floor_total_db: np.ndarray
    rhythm_ratio: np.ndarray
    rhythm_peak_hz: np.ndarray
    mod_depth: np.ndarray
    tonal_prom_db: np.ndarray
    tonal_peak_hz: np.ndarray
    flatness: np.ndarray
    manual_score: np.ndarray
    electric_score: np.ndarray
    water_score: np.ndarray
    score: np.ndarray
    hop_s: float
    extra: dict = field(default_factory=dict)


def load_audio(path: str, sr: int = SR) -> np.ndarray:
    """Load any audio file as mono float32 at `sr`.

    WAV/FLAC/OGG are read with soundfile; everything else (m4a, aac, 3gp,
    mp3 - typical phone recorder formats) is decoded with ffmpeg.
    """
    try:
        import soundfile as sf

        x, file_sr = sf.read(path, dtype="float32", always_2d=True)
        x = x.mean(axis=1)
    except Exception:
        if shutil.which("ffmpeg") is None:
            raise RuntimeError(
                f"Cannot read {path}: install ffmpeg or convert it to WAV first."
            )
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", str(sr),
             "-f", "f32le", "-"],
            check=True, capture_output=True,
        ).stdout
        return np.frombuffer(raw, dtype=np.float32).copy()

    if file_sr != sr:
        g = np.gcd(int(file_sr), sr)
        x = signal.resample_poly(x, sr // g, int(file_sr) // g).astype(np.float32)
    return x


def _ramp(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    return np.clip((x - lo) / (hi - lo), 0.0, 1.0)


def _db(p: np.ndarray | float) -> np.ndarray:
    return 10.0 * np.log10(np.asarray(p) + 1e-12)


class FloorTracker:
    """Streaming noise-floor tracker (same logic the app would run live).

    Drops immediately to any quieter level and otherwise rises slowly, so it
    adapts to a fan switching on. While brushing is detected the rise is
    frozen, otherwise a steady electric brush would become the "floor".
    """

    def __init__(self, hop_s: float, rise_db_per_s: float):
        self.rise = rise_db_per_s * hop_s
        self.value: float | None = None

    def update(self, energy_db: float, frozen: bool) -> float:
        if self.value is None or energy_db < self.value:
            self.value = energy_db
        elif not frozen:
            self.value = min(self.value + self.rise, energy_db)
        return self.value


def compute_features(x: np.ndarray, sr: int = SR, cfg: FeatureConfig | None = None) -> Features:
    cfg = cfg or FeatureConfig()
    if sr != SR:
        raise ValueError(f"expected {SR} Hz audio, got {sr}")

    sos_scrub = signal.butter(4, cfg.scrub_band_hz, "bandpass", fs=sr, output="sos")
    sos_broad = signal.butter(4, cfg.broad_band_hz, "bandpass", fs=sr, output="sos")
    scrub = signal.sosfilt(sos_scrub, x)
    broad = signal.sosfilt(sos_broad, x)

    n_env = len(x) // ENV_HOP
    env = np.sqrt(np.mean(scrub[: n_env * ENV_HOP].reshape(n_env, ENV_HOP) ** 2, axis=1))
    env_broad = np.sqrt(np.mean(broad[: n_env * ENV_HOP].reshape(n_env, ENV_HOP) ** 2, axis=1))

    win = int(round(cfg.win_s * ENV_RATE))
    hop = int(round(cfg.hop_s * ENV_RATE))
    starts = np.arange(0, max(n_env - win + 1, 0), hop)

    nfft = 2048
    fmod = np.fft.rfftfreq(nfft, 1.0 / ENV_RATE)
    rhythm_mask = (fmod >= cfg.rhythm_band_hz[0]) & (fmod <= cfg.rhythm_band_hz[1])
    ref_mask = (fmod >= cfg.rhythm_ref_band_hz[0]) & (fmod <= cfg.rhythm_ref_band_hz[1])
    hann = np.hanning(win)

    cols = {k: np.zeros(len(starts)) for k in (
        "e_scrub", "e_total", "ratio", "peak", "depth", "tprom", "tpeak", "flat")}

    for i, s in enumerate(starts):
        e = env[s : s + win]
        cols["e_scrub"][i] = _db(np.mean(e**2))
        cols["e_total"][i] = _db(np.mean(env_broad[s : s + win] ** 2))

        mean = e.mean()
        cols["depth"][i] = e.std() / (mean + 1e-12)
        p = np.abs(np.fft.rfft((e - mean) * hann, nfft)) ** 2
        cols["ratio"][i] = p[rhythm_mask].sum() / (p[ref_mask].sum() + 1e-20)
        cols["peak"][i] = fmod[rhythm_mask][np.argmax(p[rhythm_mask])]

        seg = x[s * ENV_HOP : (s + win) * ENV_HOP]
        f, pxx = signal.welch(seg, fs=sr, nperseg=4096)
        tmask = (f >= cfg.tonal_band_hz[0]) & (f <= cfg.tonal_band_hz[1])
        tdb = _db(pxx[tmask])
        k = int(np.argmax(tdb))
        cols["tprom"][i] = tdb[k] - np.median(tdb)
        cols["tpeak"][i] = f[tmask][k]
        bmask = (f >= cfg.broad_band_hz[0]) & (f <= cfg.broad_band_hz[1])
        pb = pxx[bmask] + 1e-20
        cols["flat"][i] = np.exp(np.mean(np.log(pb))) / np.mean(pb)

    rhythmic = _ramp(cols["ratio"], *cfg.rhythm_ramp) * _ramp(cols["depth"], *cfg.depth_ramp)
    tonal = _ramp(cols["tprom"], *cfg.tonal_ramp_db)

    # Sequential pass, exactly as it would run live: the floor is frozen
    # while the previous window looked like brushing.
    n = len(starts)
    floor_scrub, floor_total = np.zeros(n), np.zeros(n)
    manual, electric = np.zeros(n), np.zeros(n)
    fs_tr = FloorTracker(cfg.hop_s, cfg.floor_rise_db_per_s)
    ft_tr = FloorTracker(cfg.hop_s, cfg.floor_rise_db_per_s)
    brushing = False
    for i in range(n):
        floor_scrub[i] = fs_tr.update(cols["e_scrub"][i], brushing)
        floor_total[i] = ft_tr.update(cols["e_total"][i], brushing)
        manual[i] = _ramp(cols["e_scrub"][i] - floor_scrub[i], *cfg.snr_ramp_db) * rhythmic[i]
        electric[i] = _ramp(cols["e_total"][i] - floor_total[i], *cfg.snr_ramp_db) * tonal[i]
        brushing = max(manual[i], electric[i]) >= 0.4

    snr_total = cols["e_total"] - floor_total
    # Experimental: loud, steady (non-rhythmic), spectrally flat noise = running water.
    water = (_ramp(snr_total, 6.0, 12.0) * (1.0 - rhythmic)
             * _ramp(cols["flat"], 0.05, 0.2) * (1.0 - tonal))

    return Features(
        t=(starts + win / 2) / ENV_RATE,
        energy_scrub_db=cols["e_scrub"],
        energy_total_db=cols["e_total"],
        floor_scrub_db=floor_scrub,
        floor_total_db=floor_total,
        rhythm_ratio=cols["ratio"],
        rhythm_peak_hz=cols["peak"],
        mod_depth=cols["depth"],
        tonal_prom_db=cols["tprom"],
        tonal_peak_hz=cols["tpeak"],
        flatness=cols["flat"],
        manual_score=manual,
        electric_score=electric,
        water_score=water,
        score=np.maximum(manual, electric),
        hop_s=cfg.hop_s,
    )
