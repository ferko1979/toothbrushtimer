# Fogmosás-időzítő – Android telefon és Wear OS óra

## Letöltés

Minden feltöltés után a GitHub automatikusan megépíti mindkét appot, és kiteszi
őket a **„Android + Wear OS teszt”** kiadásba:

https://github.com/ferko1979/toothbrushtimer/releases/tag/android-latest

- `Fogmosas-telefon-Android.apk`: telefonra (Android 8.0 vagy újabb)
- `Fogmosas-ora-WearOS.apk`: Wear OS órára (Wear OS 3 vagy újabb, például Galaxy Watch 4+ vagy Pixel Watch)

## Telepítés a telefonra

1. Nyisd meg a fenti linket a telefonon, és töltsd le a `Fogmosas-telefon-Android.apk` fájlt.
2. Koppints a letöltött fájlra. Ha kéri, engedélyezd az **„Ismeretlen forrásból származó alkalmazások telepítését”** a böngészőnek vagy a fájlkezelőnek.
3. Első indításkor engedélyezd a **mikrofont** és az **értesítéseket**.

Az újabb teszt-buildek a régiek fölé települnek, az adatok megmaradnak (mindegyik ugyanazzal a tesztkulccsal van aláírva).

## Telepítés a Wear OS órára

Az órára nem lehet böngészőből telepíteni, ezért egy számítógép kell hozzá, és egyszeri beállítás:

1. Az órán: **Beállítások → Rendszer → Névjegy → Szoftververzió**, koppints 7-szer a *Build-szám* sorra (ezzel bekapcsolod a fejlesztői beállításokat).
2. **Beállítások → Fejlesztői beállítások**: kapcsold be az **ADB-hibakeresést** és a **Wi-Fi-n keresztüli hibakeresést**. Jegyezd fel az IP-címet és a portot, amit az óra kiír.
3. Telepítsd az ADB-t a számítógépre: [Android SDK Platform Tools](https://developer.android.com/tools/releases/platform-tools).
4. Futtasd a parancssorban:
   ```bash
   adb pair  <IP>:<párosító port>     # az óra mutat egy párosító kódot
   adb connect <IP>:<port>
   adb install Fogmosas-ora-WearOS.apk
   ```
5. Indítsd el az órán a **Fogmosás** appot, és engedélyezd a mikrofont.

Az órán mért fogmosások automatikusan átkerülnek a telefonos appba, a telefonon beállított cél pedig az órára. Ehhez mindkét app ugyanazt a csomagnevet és aláírást használja.

> Kényelmesebb, sok tesztelőnek is jó megoldás a **Google Play belső tesztelés**. Ehhez Google Play fejlesztői fiók kell (egyszeri 25 USD). Ott a telefonos app telepítésekor az órás változat is felkerülhet automatikusan. Ha szeretnéd, ezt is beállítom.

## Felépítés

```
android/
├── brushcore/   tiszta Kotlin: felismerés és app-logika (ugyanazok a referencia-tesztek, mint a Pythonban és Swiftben)
├── shared/      mikrofon (UNPROCESSED forrás), fogmosás-motor, előtérszolgáltatás, rezgés, tárolás, óra–telefon kapcsolat
├── app/         telefonos app (Jetpack Compose)
├── wear/        Wear OS app (Compose for Wear OS)
└── keystore/    TESZT-aláírókulcs (csak teszteléshez, éles kiadáshoz új kulcs kell)
```

Helyi build: `cd android && ./gradlew :brushcore:test :app:assembleDebug :wear:assembleDebug` (Android SDK és JDK 17 kell).

## Fogápolás, fogorvos, web

- **Tünetnapló** fogmosás után (érzékenység, ínyvérzés; gyerekeknek képekkel), fogselyem, szájvíz, fogköztisztító, nyelvtisztítás, fogkrém. Statisztika és figyelmeztetés, ha egy tünet tartós (ez nem orvosi diagnózis).
- **Fogorvosi kontroll** (félévente) és fogkőeltávolítás (évente) emlékeztető, **PDF-jelentés** a fogorvosnak (Statisztika → PDF).
- **Fogszabályzós mód**, **jutalom matricákért** a gyerekeknek, **családi áttekintés** a szülőnek.
- **Zárolás ujjlenyomattal / arcfelismeréssel**, külön **szülői zár** a beállításokra.
- **Megnézem a weben:** Statisztika → QR-kód beolvasása (a Google kódolvasóját használja, kameraengedély nem kell). Lásd [web/README.md](../web/README.md).

## Ismert korlátok (teszt-verzió)

- Az Android nem jelzi az appnak az első feloldást, ha az app nem fut. Ezért a reggeli emlékeztető az ébredés idejére van időzítve, ugyanúgy, mint iPhone-on.
- A Health Connectben nincs fogmosás-adattípus; az adatok CSV-ben exportálhatók (Statisztika → CSV).
- Az órán a fogmosás alatt bekapcsolva marad a kijelző.
- „Hamarosan” jelölésű funkciók: élő kijelzés, számlapelem (csempe), hangvezérlés, családi szinkron, adatfelajánlás.
