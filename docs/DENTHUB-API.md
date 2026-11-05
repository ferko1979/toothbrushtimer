# DentHub ↔ DentHub-Brush API (javaslat)

A DentHub rendelői rendszer és a DentHub-Brush app közötti kapcsolat javasolt felülete.

Az app oldalon már kész:
- az adatformátumok (`Symptoms.kt` / `Symptoms.swift`, `Followup.*`, `Backup.*`);
- az összekötő és utasítás linkek;
- a küldésre váró üzenetek sora.

Hiányzik: a DentHub szerver végpontjai. Ez a leírás a DentHub fejlesztőinek szól, hogy mindkét oldal
ugyanazt a felületet valósítsa meg.

## 1. Összekötés (páciens ↔ rendelő)

A rendelő a DentHubon generál egy egyszer használható kódot a pácienshez, és QR-ként vagy linkként adja át.

```
denthub://link?d=<base64url(JSON)>
```

```json
{
  "id": "clinic-123",
  "name": "Mosoly Fogászat",
  "logoUrl": "https://…/logo.png",
  "email": "info@…",
  "phone": "+36…",
  "bookingUrl": "https://…/foglalas",
  "address": "…",
  "linkToken": "egyszer-hasznalatos-token",
  "messaging": true
}
```

A `messaging` mező jelzi, hogy a rendelő fogad-e üzenetet az appból (app–app, app–web). Ha `false`
vagy hiányzik, az app e-mailt küld, de minden üzenetet a saját üzenetlistájában is megőriz. A páciens
oldalon a „Üzenetek a rendelővel az appban” kapcsoló dönt; mindkettőnek engedélyeznie kell.

A `linkToken` mező javaslat: a mostani app még figyelmen kívül hagyja (a kód így is beolvasható).
Az API bekötésekor tároljuk, és visszaküldjük az alábbi hívásban.

Az app a megerősítés után:

```http
POST /api/brush/v1/link
{ "linkToken": "…", "device": { "platform": "android|ios", "pushToken": "…" } }
```

```http
200 { "accessToken": "…", "refreshToken": "…", "patient": { "id": "…", "name": "…" } }
```

A további hívások `Authorization: Bearer <accessToken>` fejléccel mennek.

## 2. Panasz és üzenet küldése

```http
POST /api/brush/v1/messages
{
  "id": "uuid",
  "sentAt": "2026-11-03T14:02:00Z",
  "text": "Panasz összefoglaló…",
  "symptom": {
    "id": "uuid",
    "kind": "pain",
    "level": "urgent",
    "answers": {
      "jaw": ["lower"],
      "side": ["right"],
      "teeth": ["46", "47"],
      "pain": ["severe"],
      "trigger": ["hot", "night"]
    },
    "note": "Tegnap este óta lüktet",
    "followUps": [ { "day": 1, "answer": "same", "at": "…" } ]
  },
  "visit": { "reason": "pain", "timing": "asap", "dayParts": ["morning"], "note": "" },
  "brushingSummary": { "days": 30, "avgS": 112, "goalDays": 24, "bleedingDays": 3 }
}
```

```http
201 { "id": "uuid", "status": "delivered" }
```

A fotók külön mennek, utána csatolva:

```http
POST /api/brush/v1/messages/{id}/photos
Content-Type: image/jpeg
```

Megjegyzések:
- A panaszkódok és válaszkódok listája: `Symptoms.question()`.
- A fogak FDI számozásúak.
- Az app az üzenetet `queued` állapotban tárolja, amíg a küldés sikeres nem lesz; ezért az `id` alapján idempotensnek kell lennie.

Az üzenetek címzettje: `"to": "doctor"` (orvos) vagy `"admin"` (recepció / asszisztens, pl. időpontkérés).
Az app jelenleg így tárolja (`ClinicMessage`): `id`, `text`, `photos`, `to`, `via` (`["app"]`,
`["email"]`, vagy mindkettő), `status` (`queued` → `delivered` → `read`; e-mailnél `emailed`),
`appointmentId`. A szerver a `status`-t a 3. pont válaszaiban frissítheti
(`{ "id": "…", "status": "read" }`).

## 3. Válaszok és időpont-ajánlat a rendelőtől

```http
GET /api/brush/v1/messages?since=<ISO>
```

```http
200 [
  {
    "id": "…",
    "replyTo": "uuid",
    "from": "clinic",
    "text": "Holnap 10:30?",
    "offer": { "slotId": "…", "start": "…", "doctor": "Dr. …" },
    "savedToRecord": true
  }
]
```

### Push értesítés

Új rendelői üzenetnél, időpont-ajánlatnál és -visszaigazolásnál a szerver push értesítést küld a
`pushToken` alapján (Android: FCM HTTP v1, iOS: APNs, token alapú hitelesítés). Tartalom: csak
általános szöveg, egészségügyi adat nélkül:

```json
{
  "title": "Mosoly Fogászat",
  "body": "Új üzeneted érkezett",
  "data": { "type": "message|offer|confirmed|cancelled", "messageId": "…" }
}
```

Az app a push hatására lekéri a `GET /api/brush/v1/messages?since=` végpontot, és megnyitja az
Üzenetek képernyőt. A `pushToken` frissítése: `PUT /api/brush/v1/device { "pushToken": "…" }`.
(Az apphoz ehhez Firebase-projekt és APNs-kulcs kell; a mostani verzió push nélkül, a megnyitáskor
frissít.)

## 4. Időpontfoglalás

Folyamat: a páciens kér (üzenet `to: "admin"`) → a rendelő ajánl (`offer`) → a páciens elfogadja vagy
másikat kér → visszaigazolt időpont. Elfogadáskor az app felveszi a telefon naptárába (Android:
naptár-alkalmazás, iOS: Naptár), és helyi emlékeztetőt ad egy nappal és két órával előtte.

Amíg az API nincs kész, az ajánlat QR-ként vagy linkként is átadható (az app már kezeli):

```
denthub://appt?d=<base64url({"id":"uuid","start":"2026-11-10T10:30","durationMin":30,"doctor":"Dr. Kiss","clinicName":"Mosoly Fogászat","address":"…","reason":"pain","note":""})>
```

A `start` helyi idő. A páciens a telefonon vagy a recepción kapott időpontot kézzel is felveheti
(„Időpontot kaptam”).

```http
GET /api/brush/v1/slots?reason=pain&from=…&to=…
```

```http
200 [ { "id": "…", "start": "…", "end": "…", "doctor": "…" } ]
```

```http
POST /api/brush/v1/bookings
{ "slotId": "…", "messageId": "uuid|null", "note": "…" }
```

```http
201 { "id": "…", "start": "…" }
```

```http
DELETE /api/brush/v1/bookings/{id}
```

## 5. Kezelés utáni utasítások

A rendelő QR-ként vagy linkként adja (az app már kezeli), vagy üzenetben küldi:

```
denthub://care?d=<base64url({"title":"Szájöblítés klórhexidinnel","times":["08:00","20:00"],"days":7,"clinic":"Mosoly Fogászat"})>
```

## 6. Orvosi oldal (DentHub web)

- **Üzenetküldő (messenger):** beszélgetésenként a páciens üzenetei, fotói, panaszai; válasz az orvos vagy
  a recepció nevében; „Időpont ajánlása” gomb (naptárból választott szabad idő → `offer`). Minden
  e-mailben érkezett üzenet is ide kerül.
- **Karton és ügyféllap:** a páciens adatai, panaszai, kontrollválaszai, fotói, időpontjai és a
  fogmosási összefoglaló egy helyen; „Mentés a kartonhoz” bármely üzenetből.
- **Időpontok:** kérések listája → ajánlat → visszaigazolás → a rendelő naptárába kerül.

- **Beérkező lista:** sürgősség szerint rendezve (`level`); szűrők: panasz, dátum, megválaszolatlan.
- **Részletek:** válaszok, fogtérkép, fotók, kontrollválaszok, 30 napos fogmosási összefoglaló.
- **Gombok:** „Mentés a kartonhoz”, „Válasz”, „Időpont ajánlása”, „Visszahívás”.
- **Rendelői összesítő** (a páciens hozzájárulásával): esedékes kontrollok, romló fogmosási szokás,
  visszatérő panaszok.

A felületről grafikai terv: https://claude.ai/artifact/Bij8XN9ucFcPgEjmiPQzpj

## Biztonság

- HTTPS, rövid élettartamú tokenek.
- A fotók titkosítva tárolódnak.
- Hozzáférési napló.
- A páciens bármikor megszüntetheti az összekötést; ilyenkor a tokenek visszavonódnak.
