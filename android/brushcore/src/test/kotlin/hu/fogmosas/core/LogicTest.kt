package hu.fogmosas.core

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class LogicTest {
    private val zone = ZoneId.of("Europe/Budapest")
    private val today = LocalDate.of(2026, 10, 31)

    private fun rec(dayOffset: Int, hour: Int, dur: Double = 125.0, water: Double = 0.0, minute: Int = 0) =
        BrushRecord(profileId = "me", startMs = today.minusDays(dayOffset.toLong()).atTime(hour, minute).atZone(zone).toInstant().toEpochMilli(),
            durationS = dur, waterRunningS = water)

    private fun feed(det: SessionDetector, t0: Double, parts: List<List<Double>>): Double {
        var t = t0
        for (p in parts) repeat((p[0] / 0.5).toInt()) { det.update(t + 0.25, p[1], p[2], p[3], 0.5); t += 0.5 }
        return t
    }

    @Test fun sessionWaterCueBrushRinse() {
        val det = SessionDetector()
        feed(det, 0.0, listOf(listOf(3.0, 0.0, 0.0, 0.0), listOf(4.0, 1.0, 0.0, 0.0), listOf(50.0, 0.0, 1.0, 0.0), listOf(10.0, 1.0, 0.0, 0.0), listOf(10.0, 0.0, 0.0, 0.0)))
        val s = det.finish()
        assertEquals(1, s.size)
        assertTrue(kotlin.math.abs(s[0].start - 7) < 0.6 && kotlin.math.abs(s[0].end - 57) < 0.6)
        assertFalse(s[0].wastedWater)
    }

    @Test fun sessionTapRunningIsWaste() {
        val det = SessionDetector()
        feed(det, 0.0, listOf(listOf(3.0, 0.0, 0.0, 0.0), listOf(4.0, 1.0, 0.0, 0.0), listOf(50.0, 1.0, 1.0, 0.0), listOf(10.0, 1.0, 0.0, 0.0), listOf(20.0, 0.0, 0.0, 0.0)))
        val s = det.finish()
        assertTrue(s.single().wastedWater)
        assertTrue(det.events.any { it.second == SessionEvent.WASTE_ICON_ON })
    }

    @Test fun cuesAndCoach() {
        assertEquals(listOf(0.0, 30.0, 60.0, 90.0, 120.0), cueSchedule(120.0).map { it.atS })
        val tr = CueTracker(120.0)
        assertEquals(listOf("start"), tr.update(0.0).map { it.kind })
        assertEquals(listOf(30.0, 60.0), tr.update(65.0).map { it.atS })
        val coach = Coach(zone)
        assertTrue(coach.sessionFeedback(125.0, Goals()).contains("elérted"))
        assertTrue(coach.sessionFeedback(40.0, Goals()).contains("80 másodperc hiányzott"))
        val rs = (0 until 7).flatMap { listOf(rec(it, 7), rec(it, 21)) }
        assertEquals(7, coach.perfectStreak(rs, Goals(), today))
        assertTrue(coach.earnedAchievements(rs, Goals(), today).containsAll(listOf("first_brush", "goal_reached", "streak_7", "water_saver_10")))
    }

    @Test fun waterAndFormatting() {
        val r = WaterReport(60.0)
        assertEquals(8.0, r.litres, 1e-9)
        assertEquals(2.2, WaterReport(60.0, WaterLocale.US).gallons, 1e-9)
        assertEquals("1 234,6", Formatting.hu(1234.56))
        assertEquals("30 703", Formatting.grouped(30703))
        assertTrue(waterMessage(60.0, 50.0, WaterLocale.HU).wasted)
    }

    @Test fun reminderPlan() {
        val now = today.atTime(6, 0)
        val plan = ReminderPlanner.plan(now, emptyList(), Goals(), ReminderSettings(), zone, 1)
        assertEquals(listOf("morning", "morning_followup1", "bedtime", "bedtime_followup1"), plan.map { it.key })
        assertEquals(LocalDateTime.of(2026, 10, 31, 22, 15), plan.first { it.key == "bedtime" }.fireAt)
        assertEquals(listOf("bedtime", "bedtime_followup1"), ReminderPlanner.plan(now, listOf(rec(0, 7)), Goals(), ReminderSettings(), zone, 1).map { it.key })
    }

    @Test fun listeningPolicy() {
        val p = ListeningPolicy()
        p.appOpened(0.0)
        var t = 0.0
        while (t < 3) { p.motion(t, 0.0, 0.0, -1.0); t += 0.1 }
        assertTrue(p.placed)
        p.appBackgrounded(3.0)
        assertTrue(p.listening)
        p.motion(4.0, 0.3, -0.8, -0.5)
        assertFalse(p.listening)
        val armed = ListeningPolicy().apply { appOpened(0.0, true) }
        assertEquals(3.0, armed.sessionConfig.fallbackS)
    }

    @Test fun onboarding() {
        val f = OnboardingFlow("Anna")
        listOf("family", "Bence", "4").forEach { f.answer(it) }
        assertEquals("child_reads", f.nextQuestion()!!.id)
        assertEquals("no", f.nextQuestion()!!.defaultValue)
        f.answer("no")
        assertTrue(f.nextQuestion()!!.pictureOnly)
        f.answer("dino"); f.answer("yes"); f.answer("Lili"); f.answer("10")
        assertFalse(f.nextQuestion()!!.options.any { it.first == "dino" })
        f.answer("unicorn"); f.answer("no")
        assertNull(f.nextQuestion())
        val ps = f.profiles()
        assertEquals(listOf("Anna", "Bence", "Lili"), ps.map { it.name })
        assertTrue(feedbackFor(ps[1], 130.0).speak)
        assertFailsWith<IllegalArgumentException> { OnboardingFlow().answer("maybe") }
    }

    @Test fun settingsHabitsCalibration() {
        val s = AppSettings()
        assertTrue(s.isOn("quadrant_cues")); assertFalse(s.isOn("floss_tracking"))
        assertTrue(s.with("floss_tracking", true).isOn("floss_tracking"))
        assertFalse(s.isOn("health_sync", "android"))
        assertTrue(detectHabits((0 until 14).map { rec(it, 7) }, Goals(), today, zone).any { it.id == "evening_skipped" })
        assertTrue(detectHabits((0 until 14).flatMap { listOf(rec(it, 7), rec(it, 21)) }, Goals(), today, zone).isEmpty())
        var c = BrushCalibration()
        listOf(255.9, 256.8, 255.0).forEach { c = c.add(it) }
        assertEquals(255.9, c.brushF0!!, 1e-9)
        assertEquals(8.0, tapFlowFromMeasurement(1.0, 7.5), 1e-9)
        assertTrue(brushHeadStatus(today.minusDays(92), true, emptyList(), today, zone).due)
    }
}
