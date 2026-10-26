# Fogmosás-időzítő – iPhone és Apple Watch

## Futtatás (Macen)

Kell hozzá:
- **Xcode 15 vagy újabb** (App Store),
- **Homebrew** (https://brew.sh); a szkript ezzel telepíti az XcodeGen-t.

```bash
git clone <a repó címe> && cd toothbrushtimer/ios
git checkout claude/relaxed-cori-ezyw1b
./bootstrap.sh
```

A szkript a következőket csinálja:
1. megkérdez egy bundle ID előtagot (például `hu.sajatnev`), ennek egyedinek kell lennie,
2. legenerálja a `ToothbrushTimer.xcodeproj` projektet,
3. megnyitja Xcode-ban.

Xcode-ban ezután:
1. **Signing & Capabilities** fül, mindkét targetnél (*ToothbrushTimer* és *ToothbrushTimerWatch*): **Team** = az Apple ID-d. Ingyenes fiókkal is működik.
2. Felül válaszd ki a **ToothbrushTimer** sémát és az **iPhone-odat**, majd **Run (⌘R)**. A watch app az iPhone-appal együtt kerül az órára. Külön is futtatható a *ToothbrushTimerWatch* sémával, ha az órát választod célként.
3. Első futtatáskor az iPhone-on: **Beállítások → Általános → VPN és eszközkezelés → fejlesztői app engedélyezése**. Ugyanitt be kell kapcsolni a **Fejlesztői módot** (Adatvédelem és biztonság → Fejlesztői mód).

> A mikrofon a szimulátorban is működik, de a valódi méréshez valódi iPhone kell.

### A Swift-port gyors ellenőrzése (szimulátor nélkül)

```bash
cd BrushCore && swift test
```

Ez összeveti a Swift jelfeldolgozást a Python-referenciával (`analysis/golden/`): log-mel értékek, jellemzők, valószínűségek, szónikus pontszám, munkamenet és események. Ha valami eltér, a hibaüzenet megmondja, hol és mennyivel.

## Felépítés

```
ios/
├── project.yml        XcodeGen projektleírás (ebből lesz az .xcodeproj)
├── bootstrap.sh       projekt generálása és megnyitása
├── BrushCore/         Swift Package: a teljes logika, platformfüggetlen, tesztelhető
│   ├── DSP/           FFT, log-mel, WAV-olvasó
│   ├── Detection/     jellemzők, modell, szónikus detektor, munkamenet, valós idejű detektor
│   ├── Logic/         célok, kitüntetések, jelzések, víz, emlékeztetők, figyelési szabály,
│   │                  beállítások, profilok, kezdő kérdéssor, szokások, havi jelentés, kalibráció
│   ├── Resources/     brush_model.json (a valódi felvételeken tanított modell)
│   └── Tests/         referencia- és logikai tesztek
├── Shared/            iPhone + óra: mikrofon (16 kHz), fogmosás-vezérlő, rezgés, óra–telefon kapcsolat
├── App/               iPhone-app (SwiftUI): kezdő kérdéssor, főoldal, fogmosás, eredmény,
│                      statisztika, kitüntetések, beállítások, értesítések, Egészség app, Siri
└── Watch/             Apple Watch-app (SwiftUI): indítás, gyűrű, rezgés, eredmény → telefon
```

## Ami működik

| Funkció | iPhone | Apple Watch |
|---|---|---|
| Automatikus felismerés: víz → fogmosás → öblítés | ✅ | ✅ |
| Szónikus fogkefe felismerése (+ kalibráció) | ✅ | ✅ |
| Figyelés letett telefonnal, lezárt képernyővel is | ✅ (vízszintes, nyugalmi helyzet) | ✅ (önápolási munkamenet) |
| Rezgés a negyedeknél, gyűrű | ✅ | ✅ |
| Vízpazarlás-ikon és jelentés | ✅ | ✅ (rövid) |
| Kézi időzítő (ha a felismerés nem megy) | ✅ | ✅ |
| Emlékeztetők: reggel, 15 perccel lefekvés előtt, ismétlés; a megnyitás fogmosásra vár | ✅ | (a telefon értesítései az órán is megjelennek) |
| Családi profilok, képes avatar, felolvasás | ✅ | – (az óra a saját profilodat méri) |
| Kitüntetések, sorozat, szokás-tippek, fogkefecsere | ✅ | sorozat |
| Havi összefoglaló, CSV-export | ✅ | – |
| Apple Health (Fogmosás) | ✅ (bekapcsolható) | a telefon menti |
| Siri / Parancsok: „Start brushing with Fogmosás” | ✅ | – |
| Fogselyem, szájvíz | ✅ (bekapcsolható) | – |

**Még nincs kész** (a beállításokban „hamarosan” felirattal szerepel):
- élő kijelzés a lezárt képernyőn és a Dynamic Islanden (külön widget-bővítmény kell hozzá),
- számlapelem az órán,
- családi szinkron,
- adatfelajánlás.

## Ha valami nem fordul le

Ezt a kódot Linuxos felhőkörnyezetben írtam, ahol nincs Swift-fordító, ezért **még egyszer sem fordult le**. Valószínű, hogy az első fordításnál lesz néhány apró hiba. Ilyenkor:
- másold be nekem az Xcode hibaüzeneteit (Issue navigator, ⌘5), vagy
- futtasd a `swift test` parancsot a `BrushCore` mappában, és küldd el a kimenetét.

Kijavítom, és újra feltöltöm.
