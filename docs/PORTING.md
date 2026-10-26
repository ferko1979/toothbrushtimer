# Átírás Swiftre és Kotlinra – pontos specifikáció

A Python prototípus (`analysis/brushdetect/`) a referencia. A natív kódnak
ugyanazt kell kiszámolnia. Ezt az `analysis/golden/` referencia-tesztvektorai
ellenőrzik: a natív unit teszt beolvassa a `golden_audio.wav` fájlt, lefuttatja
a saját implementációját, és a `golden_expected.json` értékeivel veti össze, az
ott megadott tűréseken belül.

Új tesztvektorok: `cd analysis && python export_golden.py --out golden`

## Mit kell átírni (az app futás közbeni lánca)

```
mikrofon 16 kHz mono float32
 ├─ log_mel (learned.py) ─┬─ window_features 3 s / 0,5 s ─ brush fej ─ causal_smooth(5) ─┐
 │                        └─ window_features 1 s / 0,5 s ─ water fej ────────────────────┤
 └─ detect_sonic (sonic.py), 3 s / 0,5 s ────────────────────────────────────────────────┤
                                     pipeline.py: lineáris interpoláció a víz-ablakok idejére
                                                     ↓
                     SessionDetector (session.py) → események, munkamenet
                                                     ↓
          cues, coach, water_report, reminders, listening, settings… (tiszta logika)
```

A `features.py` (szabályalapú) és a `timer.py` csak az elemzéshez kell, az
appba nem.

## Buktatók, amelyekre figyelni kell

| Lépés | Pontos viselkedés (scipy/numpy) |
|---|---|
| Hangbetöltés (teszt) | int16 PCM → `minta / 32768` |
| STFT (`log_mel`) | `nperseg=1024`, `hop=160`, **periodikus** Hann-ablak (`w[n] = 0.5 − 0.5·cos(2πn/1024)`), nincs padding és nincs határ-kiterjesztés (`boundary=None, padded=False`), az első keret a 0. mintánál kezdődik. **A kimenetet a scipy elosztja az ablak összegével** (`Z = rfft(x·w) / Σw`). |
| Mel-szűrőbank | 32 háromszög, 80–7900 Hz, mel = `2595·log10(1+f/700)`, a csúcsok egyenletesen a mel-skálán, normalizálás nélkül (csúcsérték 1). A frekvenciatengely `rfftfreq(1024, 1/16000)`. |
| log | természetes alapú: `ln(FB · |Z|² + 1e-10)` |
| `window_features` | ablak: 300 keret (3 s) a fogmosáshoz, 100 keret (1 s) a vízhez, lépés 50 keret. A szórás **populációs** (ddof = 0). A medián páros elemszámnál a két középső átlaga. A ritmus-FFT ablaka `np.hanning(win)`, ami **szimmetrikus** Hann (`0.5 − 0.5·cos(2πn/(win−1))`), és 1024 pontra van nullákkal kiegészítve. A zajküszöb ablakról ablakra: `floor = min(floor + 0.01, mu)`, az első ablaknál `floor = mu`. |
| Jellemzővektor | `[mu − mean(mu)] (32) + std (32) + mean(mu − floor) (1) + comb (1)` = 66 szám |
| Modell | `p = 1 / (1 + exp(−(((x − mean) / scale) · coef + intercept)))`, súlyok a `model.json`-ból (`heads.brush`, `heads.water`) |
| `causal_smooth` | az utolsó (legfeljebb) 5 érték átlaga, csak a fogmosás-fejre |
| Szónikus detektor | 3 s-os ablakban három darab 1 s-os rész, mindegyikre Welch: `nperseg=8192`, `noverlap=4096`, periodikus Hann, átlagkivonás (`detrend='constant'`), sűrűség-skálázás, egyoldalas spektrum. A spektrum a részek **teljesítményátlaga**, dB-ben. A „környezet” mediánszűrő `±30 Hz` széles, a széleken a legközelebbi értékkel kiegészítve (`mode='nearest'`). A részletek és a küszöbök a `sonic.py`-ban. |
| Interpoláció | `np.interp(t_víz, t_fogmosás, p)`: lineáris; az első pont előtt 0, az utolsó után az utolsó érték |
| Állapotgép | `session.py` 1:1-ben, `dt = 0,5 s`, az idő az ablak közepe + `dt/2` |

## Platformonkénti megfelelők

| | iOS / watchOS | Android / Wear OS |
|---|---|---|
| FFT | Accelerate `vDSP.FFT` (valós) | JTransforms vagy saját radix-2 |
| Mátrixszorzás | `vDSP_mmul` | egyszerű ciklus (32 × 513) |
| Mikrofon | `AVAudioEngine` inputNode, 16 kHz-re konvertálva | `AudioRecord` 16 kHz mono float |
| Gyorsulásmérő (`listening.py`) | `CMMotionManager.deviceMotion.gravity` | `Sensor.TYPE_GRAVITY` (m/s² → osztás 9,81-gyel) |
| Ébredés utáni első feloldás | nincs → ütemezett értesítés az ébredés idejére | `ACTION_USER_PRESENT` → `on_first_unlock()` |
| Háttérben figyelés | „audio” háttérmód, csak előtérből indítható | előtérszolgáltatás `microphone` típussal, csak előtérből indítható |
| Óra-futás | `WKExtendedRuntimeSession` (önápolás) | előtérszolgáltatás + folyamatban lévő tevékenység (Ongoing Activity) |
