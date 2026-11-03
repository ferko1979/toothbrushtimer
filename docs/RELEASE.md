# Bolti kiadás (Google Play, App Store)

## Android – Google Play

1. **Fejlesztői fiók:** https://play.google.com/console (egyszeri 25 USD). Szervezetként kell regisztrálni,
   mert az app egészségügyi adatot kezel.
2. **Feltöltő kulcs** (egyszer, a saját gépeden):
   ```sh
   keytool -genkeypair -v -keystore upload.jks -alias denthub -keyalg RSA -keysize 4096 -validity 10000
   base64 -w0 upload.jks > upload.jks.b64
   ```
   A `upload.jks` fájlt és a jelszavakat tartsd biztonságos helyen. A Play App Signing a végleges
   kulcsot a Google-nél tárolja, ez csak feltöltéshez kell.
3. **GitHub titkok** (Settings → Secrets and variables → Actions):
   `RELEASE_KEYSTORE_BASE64` (a .b64 fájl tartalma), `RELEASE_KEYSTORE_PASSWORD`, `RELEASE_KEY_ALIAS`
   (`denthub`), `RELEASE_KEY_PASSWORD`.
4. **Build:** Actions → „Android store release” → Run workflow. Az eredmény két AAB: telefon és Wear OS.
5. **Play Console:**
   - Belső tesztelés → új kiadás → a telefonos AAB; a Wear OS AAB az „Wear OS” formátumhoz.
   - Áruházi adatlap: `docs/store/listing-hu.md`, `listing-en.md`.
   - Adatbiztonsági űrlap: `docs/PRIVACY.md` alapján (helyben tárolt egészségügyi adat; nincs
     harmadik félnek átadás; a felhasználó törölheti).
   - Egészségügyi alkalmazás nyilatkozat (Health apps declaration): kitöltendő.
   - Engedélyek indoklása: mikrofon (fogmosás felismerése), kamera (QR, fotó a panaszról),
     értesítések, pontos ébresztő nincs.
6. **Verziószám:** a `versionCode` a CI futás sorszáma; minden feltöltésnél nagyobb lesz.

## iOS – App Store

1. **Apple Developer Program:** https://developer.apple.com/programs/ (99 USD/év), szervezetként (D-U-N-S szám kell).
2. **Bundle ID-k:** `<prefix>.toothbrushtimer`, `.watchkitapp`, widgetek – a `ios/project.yml` `BUNDLE_PREFIX`
   értékét a saját prefixre kell állítani.
3. **Képességek:** HealthKit, App Groups, Push nem kell.
4. **Aláírás a CI-ban** (ha kéred, beállítom): App Store Connect API kulcs (`.p8`), Issuer ID, Key ID
   GitHub titokként; `xcodebuild archive` + `-exportArchive` → TestFlight feltöltés.
5. **App Store Connect:** adatlap (`docs/store/`), adatvédelmi címkék („Health & Fitness”, „Photos”,
   helyben, nem kötődik azonosítóhoz), egészségügyi besorolás, értékelési megjegyzés (demo útmutató).
6. **TestFlight:** belső tesztelők azonnal; külső tesztelőkhöz rövid Apple-ellenőrzés kell.

## Kiadás előtt

- [ ] Fogorvosi szakmai átnézés: `docs/MEDICAL-REVIEW.md`
- [ ] Jogi átnézés: adatkezelési tájékoztató (`docs/PRIVACY.md`), MDR-besorolás
- [ ] Valódi eszközös próba: fotó, e-mail, QR, mentés/visszaállítás, óra
- [ ] A metalquo aldomain és a DentHub API (`docs/DENTHUB-API.md`)
