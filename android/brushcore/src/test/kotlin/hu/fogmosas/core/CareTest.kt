package hu.fogmosas.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.ZoneId
import java.io.File
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

class I18nTest {
    @Test fun englishAndPlurals() {
        try {
            I18n.setLanguage("en")
            assertEquals("Floss: 1 day", tr("Fogselyem: {0} napon", 1))
            assertEquals("Floss: 3 days", tr("Fogselyem: {0} napon", 3))
            assertEquals("Upper right".lowercase(), Quadrants.names[0])
            assertEquals("1,234.5", Formatting.hu(1234.5))
            assertEquals(11, Tour.pages("android").size)
            assertTrue(Tour.pages("android").first().title.startsWith("Times"))
            assertTrue(Feature.byId("care_checkin")!!.title == "Symptom journal")
            assertEquals("Unknown text {0}", tr("Unknown text {0}"))
            assertEquals("May 10, 2026", I18n.date(LocalDate.of(2026, 5, 10)))
        } finally {
            I18n.setLanguage("hu")
        }
        assertEquals("Fogselyem: 3 napon", tr("Fogselyem: {0} napon", 3))
        assertEquals("1 234,5", Formatting.hu(1234.5))
    }
}

class HoldUntilGoalTest {
    /** Brush 30 s, then 20 s with no brushing sound, then brush again: with the goal hold it is one session. */
    private fun run(cfg: SessionConfig): List<BrushingSession> {
        val det = SessionDetector(cfg)
        var t = 0.0
        fun feed(secs: Double, w: Double, b: Double) { repeat((secs / 0.5).toInt()) { det.update(t + 0.25, w, b, 0.0, 0.5); t += 0.5 } }
        feed(2.0, 0.0, 0.0); feed(3.0, 1.0, 0.0); feed(30.0, 0.0, 1.0); feed(20.0, 0.0, 0.0); feed(60.0, 0.0, 1.0); feed(20.0, 0.0, 0.0)
        return det.finish()
    }

    @Test fun defaultStopsOnSilence() {
        val s = run(SessionConfig())
        assertEquals("quiet", s.first().endReason)
        assertTrue(s.first().durationS < 40)
    }

    @Test fun holdUntilGoalKeepsGoing() {
        val s = run(SessionConfig(holdUntilS = 120.0))
        assertEquals(1, s.size)
        assertTrue(s.first().durationS > 100, "duration ${s.first().durationS}")
        assertEquals("quiet", s.first().endReason)   // the final 20 s silence after the goal ends it
    }

    @Test fun feedbackTunesTolerance() {
        assertEquals(10.0, adjustedQuietExtra(0.0, "too_early"))
        assertEquals(45.0, adjustedQuietExtra(40.0, "too_early"))
        assertEquals(5.0, adjustedQuietExtra(10.0, "too_late"))
        assertEquals(0.0, adjustedQuietExtra(0.0, "too_late"))
    }
}

class SonicHumTest {
    /** Electric brush: water flickers and short silences in the brush signal while the hum is clear. */
    private fun run(cfg: SessionConfig): List<BrushingSession> {
        val det = SessionDetector(cfg)
        var t = 0.0
        fun feed(secs: Double, w: Double, b: Double, s: Double) { repeat((secs / 0.5).toInt()) { det.update(t + 0.25, w, b, s, 0.5); t += 0.5 } }
        feed(2.0, 0.0, 0.0, 0.0); feed(3.0, 1.0, 0.0, 0.0)            // water cue
        feed(20.0, 0.0, 0.2, 0.9)                                    // brushing, hum
        feed(8.0, 0.9, 0.1, 0.9)                                     // hum + "water" (false positive)
        feed(100.0, 0.0, 0.1, 0.9)                                   // hum continues
        feed(6.0, 1.0, 0.0, 0.0); feed(10.0, 0.0, 0.0, 0.0)          // brush off, real rinse
        return det.finish()
    }

    @Test fun humIgnoresWaterAndKeepsGoing() {
        val s = run(SessionConfig(holdUntilS = 120.0, sonicSuppressesWater = true))
        assertEquals(1, s.size)
        assertEquals("rinse", s.first().endReason)
        assertTrue(s.first().durationS > 120, "duration ${s.first().durationS}")
        assertTrue(s.first().waterRunningS < 1.0, "water ${s.first().waterRunningS}")
    }

    @Test fun withoutTheFlagFalseWaterCountsAsWaste() {
        val s = run(SessionConfig())
        assertTrue(s.first().waterRunningS > 5, "water ${s.first().waterRunningS}")
    }
}

class TestRecordingTest {
    @Test fun writesReadableWavAndJson() {
        val dir = kotlin.io.path.createTempDirectory("rec").toFile()
        val rec = TestRecording(dir, mapOf("platform" to "test", "targetS" to 120.0))
        val x = FloatArray(16000) { (kotlin.math.sin(it * 0.1) * 0.5).toFloat() }
        rec.append(x, x.size)
        rec.row(ScoreRow(0.5, 0.1, 0.9, 0.0, 0.0), "WATER")
        rec.event(1.0, "water_start")
        val files = rec.finish(mapOf("durationS" to 0.0, "endReason" to "user"))
        val (samples, rate) = WavReader.read(files[0].readBytes())
        assertEquals(16000, rate)
        assertEquals(16000, samples.size)
        val js = Json.parseToJsonElement(files[1].readText()).jsonObject
        assertEquals("denthub-brush-test-1", js["format"]!!.jsonPrimitive.content)
        assertEquals(listOf(files[0], files[1]), TestRecording.latest(dir))
        TestRecording.saveRemark(dir, rec.base, "a víz az elején hiányzott")
        assertEquals(3, TestRecording.latest(dir).size)
        val zip = TestRecording.zipAll(dir, File(dir, "out/all.zip"))!!
        val names = java.util.zip.ZipFile(zip).use { z -> z.entries().toList().map { it.name } }
        assertEquals(listOf("${rec.base}.wav", "${rec.base}.json", "${rec.base}-remark.txt"), names)
        TestRecording.prune(dir, maxBytes = 0)
        assertTrue(TestRecording.all(dir).isEmpty())
    }
}

class SonicLockOnTest {
    /** A 256 Hz tone with a weak harmonic: plain detection flickers, lock-on keeps it after one strong window. */
    @Test fun lockOnKeepsAWeakHarmonicTone() {
        val sr = SAMPLE_RATE
        val rnd = java.util.Random(1)
        val secs = 30
        val x = DoubleArray(secs * sr) { i ->
            val t = i.toDouble() / sr
            val strongHarmonic = t < 9.0           // the first seconds have a clear 2x harmonic
            val tone = if (t >= 3.0) 0.05 * kotlin.math.sin(2 * Math.PI * 256 * t) + (if (strongHarmonic) 0.02 else 0.0005) * kotlin.math.sin(2 * Math.PI * 512 * t) else 0.0
            tone + 0.01 * rnd.nextGaussian()
        }
        fun hits(cfg: SonicConfig): Int {
            val d = SonicDetector(cfg)
            var n = 0
            var off = 0
            while (off + SonicDetector.WINDOW_SAMPLES <= x.size) {
                val r = d.process(x, off)
                if (off >= 12 * sr && r.score >= 0.5) n++
                off += SonicDetector.HOP_SAMPLES
            }
            return n
        }
        val plain = hits(SonicConfig())
        val locked = hits(SonicConfig(lockOn = true))
        assertTrue(locked > plain, "plain=$plain locked=$locked")
        assertTrue(locked >= 25, "locked=$locked")
    }
}
