# Szakmai átnézés – panaszok és tanácsok

A panasz-kérdéssor és a tanácsok szabály alapúak:
- Kotlin: `android/brushcore/src/main/kotlin/hu/fogmosas/core/Symptoms.kt` (`triage`).
- Swift: `ios/BrushCore/Sources/BrushCore/Logic/Symptoms.swift`.

A teljes szöveglista angol fordítással: `i18n/strings.json`.

## Fogorvosnak átnézendő
- [ ] **Panasztípusok.** A 14 típus elég-e, kimaradt-e valami (pl. fogsor nyomja, implantátum, foghúzás után)?
- [ ] **Kérdések panaszonként.** Lásd `questionsFor`: helyes-e a sorrend, és nem túl sok-e?
- [ ] **Sürgősségi szintek.** Otthon / figyeld / pár nap / ma / azonnal (112):
  - [ ] Duzzanat + nyelési vagy légzési nehézség → azonnal.
  - [ ] Láz + duzzanat → ma.
  - [ ] Magától vagy éjjel fájó fog → ma.
  - [ ] Kiesett maradó fog → azonnal (30–60 perc).
  - [ ] Mozgó fog ütés után → ma.
  - [ ] 15 perc nyomásra sem csillapodó vérzés vagy mély seb → ma.
  - [ ] 2 hétnél régebbi seb → pár napon belül.
  - [ ] Visszatérő panasz (3× / 30 nap) → legalább pár napon belül.
- [ ] **Elsősegély-szövegek.** Hideg borogatás, sós víz, tej a kiesett foghoz, fogszabályzó-viasz, fájdalomcsillapító-figyelmeztetés.
- [ ] **Gyógyszer-minták.** Az emlékeztető-minták (klórhexidin, antibiotikum, fájdalomcsillapító) időpontjai.
- [ ] **Gyerekek.** Tejfog, fogváltás.
- [ ] **Kontrollkérdések.** Az 1., 3. és 7. nap jó-e, és mikor javasoljon orvost.

## Szabályozás
Az EU MDR (2017/745) szerint a betegségre vonatkozó tanácsot adó szoftver orvostechnikai eszköz lehet
(11. szabály). Lehetőségek:
- a tanácsokat „általános egészségügyi tájékoztatásnak” szűkíteni (nincs egyedi besorolás); vagy
- I/IIa osztályú tanúsítás.

Javaslat: jogi vélemény a kiadás előtt.
