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

## Tanult detektor (ajánlott)

A valódi felvételeken a kézzel írt szabályok gyengének bizonyultak. A súrolás
ritmusa ugyan látszik, de sok más hang is hasonló. Ezért van egy kis tanuló
modell is (`brushdetect/learned.py`), amely a következőkből dolgozik:

- **hangszín:** 32 mel-sáv átlaga, hangerőtől függetlenül,
- **hangszín-ingadozás:** sávonkénti szórás,
- **szint a zajküszöb felett,**
- **súrolási ritmus:** a burkológörbe 3–6,5 Hz-es csúcsa és a kétszeres
  frekvenciájú felharmonikusa. Az oda-vissza mozdulat így látszik a hangban.

A modell egy logisztikus regresszió. Az appban ez ablakonként egyetlen
szorzatösszeg, így az iOS-, watchOS-, Android- és Wear OS-kódba könnyen
átvihető.

Ehhez címkefájl kell: `recordings/labels.csv`.

```csv
file,kind,brush_type,start_s,end_s
record_1_electric_brush.m4a,water,electric,1.6,2.6
record_1_electric_brush.m4a,brush,electric,2.6,67.1
record_1_electric_brush.m4a,water,electric,67.1,78.8
csak_beszed.m4a,brush,,,
```

Egy sor egy szakaszt jelöl. A `kind` értéke lehet `brush` (fogmosás) vagy
`water` (víz). A fogmosás a nedvesítő víz elzárásától az öblítés kezdetéig
tart. Ha egy fájlhoz üres időpontokat adsz meg, az azt jelenti, hogy abban
nincs ilyen szakasz (negatív példa).

```bash
python train.py --labels recordings/labels.csv --out model.json
python analyze.py recordings/* --out out/ --model model.json
```

A `train.py` kihagyásos validációt is futtat: minden felvételt egy olyan
modellel értékel, amely azt a felvételt nem látta. Ez a becslés mutatja meg
őszintén, mennyire működik a modell egy új felvételen.

**Ismert korlát:** a modell csak olyan távolságra és zajszintre általánosít,
amilyet a tanítóadatban látott. Ezért érdemes több távolságból és többféle
háttérzajjal is felvenni.

## Teljes munkamenet: víz → fogmosás → öblítés

Fő szabály (`brushdetect/session.py`). A telefon a mosdó mellett fekszik,
és folyamatosan figyel:

1. **Vízcsobogás** (a fogkefe benedvesítése): az app felkészül.
2. **A víz elhallgat, utána súrolás vagy szónikus zúgás hallatszik:** az app
   jelzi, hogy *„fogmosás észlelve”*. Az időmérés **a víz elzárásának
   pillanatától** indul.
3. **Újra folyik a víz (öblítés):** itt ér véget a fogmosás. Az öblítés vize
   nem számít pazarlásnak.
4. **Ha a csap fogmosás közben is folyik:** 5 s után megjelenik a pazarlás
   ikon, a végén pedig egyértelmű figyelmeztetés jön. Ebben szerepel, hány
   liter (gallon) víz folyt el, mennyibe került, hány pohárnak felel meg,
   a napi fogyasztás hány százaléka, és mennyi ez egy év alatt.
5. **Ha nincs víz, de 6 s-on át fogmosás hallatszik,** az is elindítja a
   mérést (például ha valaki pohárból nedvesíti a fogkefét).

Három detektor dolgozik együtt (`brushdetect/pipeline.py`):

- **víz:** tanult modell, 1 s-os ablakkal, hogy a rövid csobogás is
  meglegyen,
- **fogmosás:** tanult modell, 3 s-os ablakkal, a súrolási ritmus és a
  hangszín alapján,
- **szónikus zúgás** (`brushdetect/sonic.py`): egy új, stabil, keskeny hang
  150–400 Hz között, a kétszeres felharmonikusával. Egy Sonicare 256 Hz-en
  zúg, ez kb. 31 000 mozdulat/perc. Kézi fogkefénél ezt a jelet figyelmen
  kívül hagyjuk, mert akkor a zúgás valaki másé.

```bash
python train.py --labels recordings/labels.csv --out model.json --verbose
python analyze.py recordings/* --out out/ --model model.json --labels recordings/labels.csv
python analyze.py recordings/* --out out/ --model model.json --brush-type electric --locale us
```

A víz becsült mennyisége és ára (`brushdetect/water_report.py`, a források a
fájlban vannak):

| | Magyarország | USA |
|---|---|---|
| csap | 8 l/perc | 2,2 gal/perc (szövetségi felső határ) |
| ár (víz és csatorna) | kb. 653 Ft/m³ (Budapest 2025/26) | kb. 0,0125 $/gal |
| napi fogyasztás/fő | kb. 105 l | kb. 82 gal (EPA) |

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
