# Fogmosás-időzítő

Hang alapján méri a fogmosás idejét: a víz elzárásától az öblítésig. Felismeri
a kézi súrolást és az elektromos (szónikus) fogkefe zúgását, figyelmeztet a
vízpazarlásra, és célokkal, kitüntetésekkel, emlékeztetőkkel segít.
Hangfelvétel nem készül, minden a készüléken marad ([PRIVACY.md](PRIVACY.md)).

| Mappa | Tartalom |
|---|---|
| [`ios/`](ios/README.md) | **iPhone + Apple Watch app** (SwiftUI). Letöltés (Sideloadly): [ios-latest kiadás](https://github.com/ferko1979/toothbrushtimer/releases/tag/ios-latest) · Mac: `cd ios && ./bootstrap.sh` |
| [`android/`](android/README.md) | **Android telefon + Wear OS óra** (Jetpack Compose). Letöltés: [android-latest kiadás](https://github.com/ferko1979/toothbrushtimer/releases/tag/android-latest) |
| [`analysis/`](analysis/README.md) | Python prototípus és referencia: felismerés, tanítás, app-logika, tesztek |
| [`docs/PORTING.md`](docs/PORTING.md) | Pontos algoritmus-specifikáció a Swift- és Kotlin-portokhoz |
| [`docs/design/`](docs/design/mockups.html) | Látványterv: iPhone, Apple Watch, Android, Wear OS |

Minden feltöltés után a GitHub Actions lefordítja és teszteli mind a négy appot
(`.github/workflows/`). Az Android-APK-k és az aláíratlan iPhone+Watch IPA automatikusan letölthetők;
az iPhone- és órás app TestFlightra is kerülhet, ha az Apple-fejlesztői adatok be vannak állítva.
