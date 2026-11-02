package hu.fogmosas.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CareTest {
    private val zone = ZoneId.of("Europe/Budapest")
    private val today = LocalDate.of(2026, 11, 2)
    private fun ms(d: LocalDate, h: Int = 21) = d.atTime(h, 0).atZone(zone).toInstant().toEpochMilli()
    private fun e(daysAgo: Int, floss: Boolean = false, bleed: Boolean = false, sens: Int = 0, paste: String? = null) =
        CareEntry(profileId = "me", dateMs = ms(today.minusDays(daysAgo.toLong())), floss = floss, bleeding = bleed, sensitivity = sens, toothpaste = paste)

    @Test fun countsAndStreaks() {
        val es = listOf(e(0, floss = true), e(1, floss = true), e(1, floss = true), e(2, floss = true), e(4, floss = true))
        assertEquals(3, careStreak(es, CareKind.FLOSS, today, zone))
        assertEquals(4, careCount(es, CareKind.FLOSS, today, 7, zone))
        assertTrue(careDoneToday(es, CareKind.FLOSS, today, zone))
        // Not ticked today yet: streak counts up to yesterday.
        assertEquals(2, careStreak(es.drop(1), CareKind.FLOSS, today, zone))
    }

    @Test fun persistentBleedingAlert() {
        val es = listOf(0, 2, 5, 9).map { e(it, bleed = true) }
        val ins = careInsights(es, today, zone)
        assertEquals("bleeding_persistent", ins.first().id)
        assertTrue(ins.first().alert)
        // Three days only: no alert.
        assertTrue(careInsights(es.take(3), today, zone).none { it.id == "bleeding_persistent" })
    }

    @Test fun flossHelpsInsight() {
        val before = (14..27).map { e(it, bleed = it % 2 == 0) }           // 7 bleeding days, no floss
        val now = (0..13).map { e(it, floss = true, bleed = it == 3) }      // daily floss, 1 bleeding day
        val ids = careInsights(before + now, today, zone).map { it.id }
        assertTrue("floss_helps" in ids, ids.toString())
        assertFalse("floss_rare" in ids)
    }

    @Test fun toothpasteInsights() {
        val before = (14..27).map { e(it, sens = 1, paste = "fluoride") }
        val now = (0..13).map { e(it, sens = if (it < 2) 1 else 0, paste = "sensitive") }
        assertTrue(careInsights(before + now, today, zone).any { it.id == "toothpaste_helps" })
        val noSensitive = (0..13).map { e(it, sens = 1, paste = "whitening") }
        assertTrue(careInsights(noSensitive, today, zone).any { it.id == "toothpaste_try" })
    }

    @Test fun dentistReminders() {
        val s = dentistStatus(LocalDate.of(2026, 3, 1), LocalDate.of(2026, 1, 15), today)
        assertTrue(s.checkupOverdue)
        assertFalse(s.cleaningOverdue)
        assertEquals(LocalDate.of(2027, 1, 15), s.cleaningDue)
        assertEquals(today.plusDays(7), nextDentistReminder(LocalDate.of(2026, 3, 1), null, today))
        assertEquals(LocalDate.of(2027, 5, 1), nextDentistReminder(LocalDate.of(2026, 11, 1), null, today))
        assertNull(nextDentistReminder(null, null, today))
    }

    @Test fun rewardProgress() {
        val rs = (0..4).flatMap { d -> listOf(9, 20).map { h -> BrushRecord(profileId = "k", startMs = ms(today.minusDays(d.toLong()), h), durationS = 125.0) } }
        val p = rewardProgress(rs, Goals(), "Mozi", 3, null, zone)!!
        assertEquals(3, p.have); assertTrue(p.done)
        assertEquals(2, rewardProgress(rs, Goals(), "Mozi", 14, ms(today.minusDays(1), 0), zone)!!.have)
        assertNull(rewardProgress(rs, Goals(), "", 3, null, zone))
    }

    @Test fun dentistReportContents() {
        val p = Profile("me", "Anna", orthodontic = true, lastCheckup = "2026-05-10")
        val rs = (0..9).map { BrushRecord(profileId = "me", startMs = ms(today.minusDays(it.toLong()), 21), durationS = 100.0 + it * 5) }
        val es = listOf(e(0, floss = true, paste = "sensitive"), e(1, bleed = true, sens = 2))
        val r = dentistReport(p, rs, es, today, 30, zone)
        val t = r.text()
        assertTrue(t.contains("Fogmosások: 10"), t)
        assertTrue(t.contains("Fogselyem: 1 napon"))
        assertTrue(t.contains("Ínyvérzés: 1 napon"))
        assertTrue(t.contains("erős: 1"))
        assertTrue(t.contains("Érzékeny fogra (1 nap)"))
        assertTrue(t.contains("Fogszabályzó: igen"))
        assertTrue(t.contains("2026.05.10."))
    }

    @Test fun snapshotJson() {
        val p = Profile("me", "Anna")
        val rs = listOf(BrushRecord(profileId = "me", startMs = ms(today), durationS = 130.0))
        val wp = WebLink.profileSnapshot(p, rs, listOf(e(0, floss = true)), today, zone)
        assertEquals(1, wp.days.size)
        assertEquals(1, wp.days[0].goalHits)
        assertTrue(wp.days[0].floss)
        val js = Json.parseToJsonElement(WebLink.snapshotJson(WebLink.snapshot(listOf(wp), java.time.Instant.EPOCH, "hu"))).jsonObject
        assertEquals("1", js["v"]!!.jsonPrimitive.content)
    }
}

class WebLinkTest {
    private val v = Json.parseToJsonElement(String(WebLinkTest::class.java.getResourceAsStream("/golden/weblink_vector.json")!!.readBytes())).jsonObject
    private fun s(k: String) = v[k]!!.jsonPrimitive.content
    private fun b(k: String) = WebLink.unb64(s(k))

    @Test fun parsesQr() {
        val p = WebLink.parse(s("qr"))
        assertNotNull(p)
        assertEquals("https://fogmosas.example", p.base)
        assertEquals("https://fogmosas.example/api/relay/${s("sid")}", p.uploadUrl)
        assertContentEquals(b("webPublic"), p.webPublicKey)
        assertEquals("https://x.hu/app", WebLink.parse("https://x.hu/app/l#${s("sid")}.${s("webPublic")}")!!.base)
        assertNull(WebLink.parse("http://evil.example/l#${s("sid")}.${s("webPublic")}"))
        assertNotNull(WebLink.parse("http://localhost:8080/l#${s("sid")}.${s("webPublic")}"))
        assertNull(WebLink.parse("https://x.hu/l#short.${s("webPublic")}"))
        assertNull(WebLink.parse("hello"))
    }

    @Test fun hkdfMatchesNode() {
        val key = WebLink.hkdf(b("sharedSecret"), s("sid").toByteArray(), WebLink.INFO.toByteArray())
        assertContentEquals(b("key"), key)
    }

    @Test fun envelopeMatchesNode() {
        val kp = WebLink.keyPair(b("phonePrivate"), b("phonePublic"))
        val env = WebLink.seal(b("webPublic"), s("sid"), s("plaintext").toByteArray(), kp, b("nonce"))
        assertEquals(s("envelope"), WebLink.b64(env))
        // Random ephemeral key: still well-formed.
        assertEquals(65 + 12 + s("plaintext").toByteArray().size + 16, WebLink.seal(b("webPublic"), s("sid"), s("plaintext").toByteArray()).size)
    }
}

class TourTest {
    @Test fun pagesArePlatformSpecificAndComplete() {
        for (pf in listOf("ios", "android")) {
            val ps = Tour.pages(pf)
            assertEquals(11, ps.size)
            assertTrue(ps.none { it.text.contains("{") || it.title.isBlank() })
        }
        assertTrue(Tour.pages("ios").any { "Face ID" in it.text })
        assertTrue(Tour.pages("android").any { "csempe" in it.text })
    }
}
