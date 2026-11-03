package hu.fogmosas.core

import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Mirrored in FollowupTests.swift. */
class FollowupTest {
    private val z = ZoneOffset.UTC
    private val day = 86_400_000L
    private val t0 = LocalDate.of(2026, 11, 3).atTime(9, 0).toInstant(z).toEpochMilli()
    private val r = SymptomReport(profileId = "me", dateMs = t0, kind = "pain", level = "soon")

    @Test
    fun toothMapAndNames() {
        assertEquals(32, ToothMap.all.size)
        assertEquals("18", ToothMap.all.first())
        assertEquals("46 (jobb alsó első nagyőrlő)", ToothMap.name("46"))
        val f = SymptomFlow()
        f.answer(listOf("pain")); f.answer(listOf("lower")); f.answer(listOf("right")); f.answer(listOf("back"))
        assertEquals("teeth", f.next()!!.id)
        assertTrue(f.next()!!.multi)
        val kid = SymptomFlow(child = true)
        kid.answer(listOf("pain")); kid.answer(listOf("lower")); kid.answer(listOf("right")); kid.answer(listOf("back"))
        assertEquals("pain", kid.next()!!.id)
    }

    @Test
    fun followUpDays() {
        assertNull(followUpDue(r, emptyList(), t0 + 3_600_000, z))
        assertEquals(1, followUpDue(r, emptyList(), t0 + day, z))
        val ups = listOf(SymptomFollowUp(r.id, 1, "same", t0 + day))
        assertNull(followUpDue(r, ups, t0 + 2 * day, z))
        assertEquals(3, followUpDue(r, ups, t0 + 4 * day, z))
        assertEquals(7, followUpDue(r, ups, t0 + 8 * day, z))
        assertNull(followUpDue(r, ups + SymptomFollowUp(r.id, 3, "gone", t0), t0 + 8 * day, z))
        assertNull(followUpDue(r, ups, t0 + 20 * day, z))
        assertTrue(followUpAdvice(r, "worse", 1).second)
        assertTrue(followUpAdvice(r, "same", 7).second)
        assertFalse(followUpAdvice(r, "better", 3).second)
        val plan = plannedFollowUps(listOf(r), ups, LocalDateTime.of(2026, 11, 3, 10, 0), z)
        assertEquals(listOf(LocalDateTime.of(2026, 11, 6, 18, 0), LocalDateTime.of(2026, 11, 10, 18, 0)), plan.map { it.first })
    }

    @Test
    fun careTasks() {
        val t = CareTask(profileId = "me", title = "Szájöblítés", times = listOf("08:00", "20:00"), start = "2026-11-03", days = 3)
        assertTrue(t.activeOn(LocalDate.of(2026, 11, 5)))
        assertFalse(t.activeOn(LocalDate.of(2026, 11, 6)))
        val done = t.toggle(LocalDate.of(2026, 11, 3), "08:00")
        assertTrue(done.isDone(LocalDate.of(2026, 11, 3), "08:00"))
        assertEquals(1 to 2, done.progress(LocalDate.of(2026, 11, 3)))
        assertEquals(1 to 6, done.progress(LocalDate.of(2026, 11, 9)))
        val plan = plannedCareTasks(listOf(done), LocalDateTime.of(2026, 11, 3, 9, 0))
        assertEquals(5, plan.size)
        assertEquals(LocalDateTime.of(2026, 11, 3, 20, 0), plan.first().first)
        assertEquals(listOf("08:00", "14:00", "20:00"), CareTaskPresets.times(3))
    }

    @Test
    fun motorTrendAndPhotos() {
        val today = LocalDate.of(2026, 11, 3)
        fun rec(daysAgo: Long, f0: Double) = BrushRecord(profileId = "me", startMs = today.minusDays(daysAgo).atTime(8, 0).toInstant(z).toEpochMilli(), durationS = 120.0, brushF0 = f0)
        val healthy = (0L..30L).map { rec(it, 256.0) }
        val ok = motorTrend(healthy, today, z)
        assertTrue(ok.weeks.size >= 4)
        assertEquals(0.0, ok.changePct!!, 0.01)
        val slowing = (8L..30L).map { rec(it, 256.0) } + (0L..6L).map { rec(it, 248.0) }
        assertTrue(motorTrend(slowing, today, z).changePct!! < -2.0)
        assertNull(motorTrend(listOf(rec(0, 256.0)), today, z).changePct)
        val a = r.copy(id = "a", photos = listOf("1.jpg"))
        val b = r.copy(id = "b", dateMs = t0 + day, photos = listOf("2.jpg"))
        assertEquals(listOf("a", "b"), photoTimeline(listOf(b, a, r), "me", "pain").map { it.id })
    }
}
