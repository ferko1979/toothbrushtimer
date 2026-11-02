# Fordítás / Translations

A forrásszöveg magyar; az angol a `strings.json`-ban (appok) és a `web.json`-ban (weboldal) van.

- Kotlin és Swift: `tr("Ma {0}/{1}", n, perDay)`. A `{0}`, `{1}`… helyére kerülnek az értékek.
  Angol többes szám: `{"one": "…", "other": "…"}` (az első számérték dönt).
- A nyelv: Beállítások → Nyelv / Language (alapból a telefon nyelve). Az órák és a widgetek a készülék nyelvét követik.
- Új szöveg után: `./i18n/sync.sh` (bemásolja a szótárt az appokba és a weboldalra, és ellenőrzi,
  hogy minden kulcsnak van-e angol párja, és egyeznek-e a helyettesítő jelek). A CI is ellenőrzi.
- `convert.py`: a magyar szövegeket `tr(…)` hívásba csomagolja (egyszeri átalakításhoz készült).
