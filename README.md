# Fogmosás-időzítő

Hang alapján méri a fogmosás idejét: a víz elzárásától az öblítésig. Felismeri
a kézi súrolást és az elektromos (szónikus) fogkefe zúgását, figyelmeztet a
vízpazarlásra, és célokkal, kitüntetésekkel, emlékeztetőkkel segít.
Hangfelvétel nem készül, minden a készüléken marad ([PRIVACY.md](PRIVACY.md)).

| Mappa | Tartalom |
|---|---|
| [`ios/`](ios/README.md) | **iPhone + Apple Watch app** (SwiftUI). Indítás: `cd ios && ./bootstrap.sh` |
| [`analysis/`](analysis/README.md) | Python prototípus és referencia: felismerés, tanítás, app-logika, tesztek |
| [`docs/PORTING.md`](docs/PORTING.md) | Pontos algoritmus-specifikáció a Swift- és Kotlin-portokhoz |
| [`docs/design/`](docs/design/mockups.html) | Látványterv: iPhone, Apple Watch, Android, Wear OS |

Android és Wear OS: tervezve, a látványterv és a specifikáció kész; a kód a következő lépés.
