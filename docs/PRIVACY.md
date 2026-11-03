# Adatkezelési tájékoztató – DentHub-Brush (tervezet)

> Tervezet jogi átnézésre. A [szögletes zárójeles] részeket ki kell tölteni.

**Adatkezelő:** [cégnév, cím, e-mail]. **Adatvédelmi kapcsolattartó:** [név, e-mail].

## Milyen adatokat kezel az app?
- Fogmosások ideje és hossza, a csap használata, fogkefe típusa.
- Napló: fogselyem, szájvíz, érzékenység, ínyvérzés.
- Panaszok (kérdésekre adott válaszok), a hozzájuk készített **fotók**, kontrollválaszok, emlékeztetők.
- Profilok (név, gyerekeknél életkor), célok, beállítások.
- A **mikrofon hangját** csak a telefon memóriájában dolgozza fel; hangfelvétel nem készül.
  Kivétel a felhasználó által bekapcsolt teszt mód, ahol a felvétel a telefonon marad, amíg el nem küldi.

Ezek **egészségügyi adatok** (GDPR 9. cikk). Kezelésük jogalapja a felhasználó **kifejezett hozzájárulása**,
amelyet az app első indításkor kér, és amely bármikor visszavonható (adatok törlése).

## Hol tárolódnak?
- Kizárólag a felhasználó telefonján (Android: az app privát tárhelye; iOS: fájlvédelemmel titkosított tárhely).
- A webes megtekintés végponttól végpontig titkosított; a közvetítő szerver nem tudja elolvasni,
  és rövid idő után törli.
- Mentés: a felhasználó által választott helyre, jelszóval (AES-256-GCM, PBKDF2) titkosítva.

## Kinek kerül adat?
- A rendelőnek csak akkor, ha a felhasználó elküldi (üzenet, e-mail, PDF-jelentés).
- Harmadik félnek, hirdetőnek nem. Analitika és reklám nincs.

## A felhasználó jogai
Hozzáférés és hordozhatóság (titkosított mentés), helyesbítés (az appban), törlés („Minden adatom törlése”),
a hozzájárulás visszavonása, panasz a NAIH-nál (naih.hu).

## Gyerekek
A gyerekprofilokat a szülő hozza létre és kezeli; 16 év alatt a szülő hozzájárulása szükséges.

## Orvosi jelleg
A tanácsok általános tájékoztatások, nem orvosi diagnózis. [Az MDR-besorolás eredménye.]
