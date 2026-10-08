# Adatvédelem / Privacy

## Röviden (áruházi leíráshoz)

**A fogmosásodat a telefonod vagy órád hallja, de senki más.**
A hangot az app kizárólag a készüléken, valós időben dolgozza fel. Hangfelvétel nem
készül, nem kerül mentésre, és soha nem hagyja el a készülékedet. Csak az eredményt
tároljuk: mikor mostál fogat, meddig, és folyt-e közben a csap.

**Your brushing is heard by your phone or watch, and nobody else.**
Sound is processed on the device, in real time. No audio is recorded, stored or ever
sent anywhere. Only the result is kept: when you brushed, for how long, and whether
the tap was running.

## Részletesen (fejlesztői elvek, az appokra kötelező)

1. **Nincs hangtárolás.** A mikrofonjel egy legfeljebb 3 másodperces gyűrűpufferben
   él a memóriában. Ebből számoljuk a jellemzőket (hangszín, ritmus, zúgás), utána
   a puffer felülíródik. Hangot fájlba, adatbázisba vagy naplóba írni tilos.
2. **Nincs hálózat a felismeréshez.** A modell a készüléken fut; az app a mérés
   működéséhez nem kér internetet.
3. **Csak minimális adat** kerül mentésre: kezdő időpont, időtartam, csap-idő,
   fogkefe típusa, profil. Ezek a készüléken maradnak.
4. **Megosztás csak kifejezett kérésre:** Apple Health (iOS), CSV/JSON export,
   havi összefoglaló a fogorvosnak. Felhőmentés csak a platform titkosított
   mentésén keresztül (iCloud / Google mentés), külön szerver nincs.
5. **Mikor figyel a mikrofon?** Csak amikor a felhasználó engedélyezte, és
   (a) épp fut egy mérés, vagy (b) a „mosdó mód” be van kapcsolva, amikor a
   telefon le van téve a fürdőben. A rendszer mikrofonjelzője (narancs/zöld pötty)
   ilyenkor látszik, és az app is mutatja.
6. **Gyerekprofilok:** szülői fiókhoz kötve, reklám és harmadik féltől származó
   analitika nélkül.
7. **Törlés:** az összes adat egy gombbal törölhető az appból.
