# DentHub-Brush – webes megtekintés

A telefonos appban mért statisztika a böngészőben is megnézhető, **fiók és jelszó nélkül**:

1. Nyisd meg a weboldalt a számítógépen: megjelenik egy QR-kód.
2. A telefonon: **Statisztika → Megnézem a weben → QR-kód beolvasása**, majd hagyd jóvá Face ID-val vagy ujjlenyomattal.
3. A böngészőben megjelenik az irányítópult: fogmosási idők, fogápolási napló (fogselyem, ínyvérzés, érzékenység), megfigyelések és a fogorvosi jelentés (nyomtatható).

Az adatokat a telefon titkosítja, és csak az a böngészőlap tudja kinyitni, amelyik a QR-kódot mutatta.
A szerver csak továbbítja a titkosított csomagot (legfeljebb 2 percig tartja a memóriában), nem
tárol semmit, és nem látja a tartalmat. A lap bezárásakor az adatok eltűnnek. Részletek: [PROTOCOL.md](PROTOCOL.md).

## Futtatás

Node.js 18 vagy újabb kell, más függőség nincs.

```bash
cd web
npm start                 # http://localhost:8080
npm test                  # továbbító és titkosítás tesztjei
node test/e2e.mjs shots   # teljes párosítás valódi böngészőben (Playwright kell)
```

A telefonos appok csak **https** címet fogadnak el (helyi fejlesztéskor `http://localhost` is jó).

## Közzététel

**Legegyszerűbb: Render (ingyenes csomag).** Jelentkezz be a [render.com](https://render.com)-ra a GitHub-fiókoddal,
majd nyisd meg ezt a linket: <https://render.com/deploy?repo=https://github.com/ferko1979/toothbrushtimer>.
A Render a repó gyökerében lévő `render.yaml` alapján magától felépíti és elindítja a szolgáltatást,
https-címet ad (pl. `https://fogmosas-web.onrender.com`), és minden feltöltés után frissít.
Saját domain a Render beállításaiban köthető hozzá. (Az ingyenes csomag 15 perc tétlenség után
elalszik; az első megnyitás ilyenkor kb. fél percig tart.)

**Fly.io:** `cd web && fly launch --copy-config --no-deploy && fly deploy` (a `fly.toml` kész).

**Docker-kép:** a `main` ágra feltöltve a GitHub elkészíti a `ghcr.io/ferko1979/fogmosas-web:latest` képet.

Bármilyen Node- vagy Docker-tárhelyen fut (pl. Render, Fly.io, Railway, saját szerver), egyetlen
folyamatként; adatbázis és tárhely nem kell.

```bash
docker build -t fogmosas-web web
docker run -p 8080:8080 fogmosas-web
```

Https-t a tárhely vagy egy elé tett proxy (pl. Caddy, nginx) adja. Több példány esetén mindegyik
kérésnek ugyanarra a példányra kell érkeznie (egy példány bőven elég).

## Tesztfelvételek fogadása

Az appok teszt módja (jelszóval védve, minden verzióban benne van) a felvételeket, az idővonalat és a
tesztelő észrevételeit magától feltölti ide: `POST /api/test-upload/<fájlnév>`. Bekapcsolás a
szerveren környezeti változókkal:

| Változó | Jelentés |
|---|---|
| `TEST_UPLOAD_CODE` | a tesztelői jelszó (ugyanaz, amit az app kér). Nélküle a végpont ki van kapcsolva. |
| `TEST_UPLOAD_DIR` | ide ment (alapból `./test-uploads/<készülék>/`) |
| `GOOGLE_SERVICE_ACCOUNT` | szolgáltatásfiók JSON-kulcsa (Google Cloud → IAM → Service accounts) |
| `DRIVE_FOLDER_ID` | Google Drive mappa azonosítója egy *megosztott meghajtón*, amelynek a szolgáltatásfiók tagja |

Ha a két Google-változó meg van adva, a fájl a Drive-mappába kerül (`<készülék>_<fájlnév>`), és a
szerverről törlődik. Ingyenes Render-csomagon a lemez nem tartós, ezért ott a Drive-beállítás kell.
Az app a felvételt a Statisztikánál összekötött webcímre, annak hiányában a
`https://fogmosas-web.onrender.com` címre tölti fel.
