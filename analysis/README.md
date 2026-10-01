# Fogmosás-felismerés – megvalósíthatósági elemzés

Ez a mappa egy Python prototípust tartalmaz. A célja annak ellenőrzése, hogy
**hang alapján** mennyire megbízhatóan ismerhető fel a fogmosás, mielőtt
megépül az iOS-, watchOS-, Android- és Wear OS-app.

## Mit figyel a detektor?

| Jel | Mire jó | Hogyan |
|---|---|---|
| **Ritmus** | Kézi fogkefe | A 2–7 kHz-es (sörte-súrlódási) sáv hangereje másodpercenként kb. 2–6-szor pulzál a mozdulatok ütemében. |
| **Tonalitás** | Elektromos fogkefe | Stabil motorzúgás (alaphang és felharmonikusai) 70–2000 Hz között. |
| **Zajszint feletti jel** | Távolság, háttérzaj | Adaptív zajszint: követi a ventilátort vagy a bojlert, fogmosás közben nem emelkedik. |
| **Víz** (kísérleti) | Kezdet és vég jelzése | Hangos, egyenletes, nem ritmikus zaj. |

A pontszámokból egy **állapotgép** számolja az időt (`brushdetect/timer.py`):

- a legfeljebb 3 s-os szünetek (köpés, oldalváltás) beleszámítanak,
- a hosszabb szünetek nem számítanak bele, de a munkamenet folytatódik,
- 20 s csend után a munkamenet lezárul.

Ugyanez a logika kerül majd át 1:1-ben az appokba.

## Telepítés

```bash
cd analysis
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# m4a / 3gp / mp3 fájlokhoz ffmpeg is kell (macOS: brew install ffmpeg)
```

## Felvételek készítése

A felvételeket tedd ide: `analysis/recordings/`. Ez a mappa nem kerül fel a
gitre, a hangfelvételek nálad maradnak.

A telefon beépített hangrögzítője megfelelő (iPhone: Diktafon, Android:
Hangrögzítő). **Indítsd a felvételt 5–10 másodperccel a fogmosás előtt**, hogy
a detektor meg tudja mérni a háttérzajt.

Javasolt helyzetek:

| # | Fájlnév példa | Leírás |
|---|---|---|
| 1 | `kezi_30cm__truth120s.m4a` | kézi fogkefe, a telefon a mosdó szélén |
| 2 | `kezi_150cm__truth120s.m4a` | kézi fogkefe, a telefon messzebb (polcon) |
| 3 | `kezi_ventilator__truth120s.m4a` | kézi fogkefe, bekapcsolt szellőzővel |
| 4 | `elektromos_1m__truth120s.m4a` | elektromos fogkefe |
| 5 | `csak_viz__truth0s.m4a` | fogmosás nélkül: csapvíz, kézmosás |
| 6 | `zavaro__truth0s.m4a` | beszéd, hajszárító, zuhany – amit a detektornak *nem* szabad fogmosásnak vennie |

A `__truth<N>s` végződés jelzi a valódi fogmosási időt másodpercben (stopperrel
mérve, durván is elég). Ezzel a szkript ki tudja számolni a hibát. Ha nem
tudod, hagyd el.

## Futtatás

```bash
python analyze.py recordings/* --out out/
```

Kimenet:

- a konzolon: becsült idő, valós idő, eltérés, munkamenetek,
- `out/<fájl>.png`: diagram az alábbi részekkel:
  1. spektrogram,
  2. hangerő és adaptív zajszint,
  3. ritmusarány és ütemfrekvencia: kézi fogmosásnál a ritmusarány 0,6 fölé
     megy, az ütem 2–6 Hz körül van,
  4. tonalitás: elektromos fogkefénél 15–30 dB fölé ugrik, a csúcsfrekvencia
     stabil,
  5. pontszámok; a **zöld sáv** az, amit a detektor fogmosásnak mért,
- `out/summary.csv`: összesítő táblázat.

### YAMNet összehasonlítás (opcionális)

```bash
pip install tensorflow tensorflow-hub
python analyze.py recordings/* --out out/ --yamnet
```

Ez a Google előtanított hangfelismerő modelljének „Toothbrush” / „Electric
toothbrush” pontszámait is felrajzolja, így látszik, hogy a kézzel írt
jellemzők vagy a gépi tanulásos modell működik-e jobban a te felvételeiden.
Első futáskor a modell letöltődik a tfhub.dev-ről, ehhez internetkapcsolat
kell.

## Szintetikus tesztadatok

```bash
python make_synthetic.py --out synthetic/
python analyze.py synthetic/*.wav --out out/
python -m pytest -q tests
```

A szintetikus hangok csak azt ellenőrzik, hogy a feldolgozási lánc helyesen
működik. **Nem helyettesítik a valódi felvételeket.** A küszöbértékek
(`FeatureConfig`, `TimerConfig`) jelenleg becslések, ezeket a valódi
felvételek alapján kell majd finomhangolni.
