package hu.fogmosas.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Wet cue, quiet-water rinse rule and motor-stop watch (from real test recordings). Mirrored in SessionCuesTests.swift. */
class SessionCuesTest {
    private val cfg = SessionConfig(holdUntilS = 120.0, sonicSuppressesWater = true, runHysteresis = true,
        quietWaterRinseS = 6.0, wetCue = true, sonicStopWatch = true)

    /** Steps of 0.5 s: (seconds, water, brush, sonic, rmsDb, f0). */
    private fun run(d: SessionDetector, segs: List<List<Double>>, t0: Double = 0.0): Double {
        var t = t0
        for (s in segs) {
            val n = (s[0] / 0.5).toInt()
            repeat(n) { t += 0.5; d.update(t, s[1], s[2], s[3], 0.5, s[4], s[5]) }
        }
        return t
    }

    @Test
    fun wettingArmsAndBrushingStartsAfterToothpaste() {
        val d = SessionDetector(cfg)
        run(d, listOf(
            listOf(3.0, 0.0, 0.0, 0.0, -70.0, 0.0),
            listOf(1.5, 0.0, 0.8, 0.0, -56.0, 0.0),   // splash (scores look like brushing)
            listOf(1.5, 0.0, 0.8, 0.0, -70.0, 0.0),
            listOf(6.0, 0.0, 0.2, 0.0, -70.0, 0.0),   // toothpaste
            listOf(40.0, 0.0, 0.9, 1.0, -59.0, 256.0),
        ))
        assertTrue(d.events.any { it.second == SessionEvent.BRUSH_WET })
        val s = d.sessions.single()
        assertEquals("wet", s.cue)
        assertTrue(s.wetBefore)
        assertTrue(s.start in 11.5..12.5, "start ${s.start}")
    }

    @Test
    fun quietWaterWhileScrubbingIsNotARinseButTheLoudTapIs() {
        val d = SessionDetector(cfg)
        val t = run(d, listOf(
            listOf(130.0, 0.0, 0.9, 1.0, -59.0, 256.0),
            listOf(5.0, 0.0, 0.5, 0.0, -60.0, 0.0),    // by hand after the motor stopped
            listOf(2.0, 0.9, 0.0, 0.0, -59.5, 0.0),    // scrubbing that sounds like water
            listOf(5.0, 0.0, 0.1, 0.0, -61.0, 0.0),
        ))
        assertEquals(SessionDetector.State.BRUSHING, d.state)
        val s = d.sessions.single()
        assertNotNull(s.sonicStoppedAt)
        assertTrue(s.manualAfterSonicS >= 2.0)
        assertEquals(1, brushPowerNotes(s, emptyList()).size)
        run(d, listOf(listOf(3.0, 0.9, 0.0, 0.0, -47.0, 0.0), listOf(6.0, 0.0, 0.0, 0.0, -65.0, 0.0)), t)
        assertEquals("rinse", s.endReason)
        assertTrue(s.end in 141.5..142.5, "end ${s.end}")
    }

    @Test
    fun slowerMotorThanUsualIsReported() {
        val d = SessionDetector(cfg)
        run(d, listOf(listOf(60.0, 0.0, 0.9, 1.0, -59.0, 248.0)))
        val s = d.current!!
        assertNull(s.sonicStoppedAt)
        val notes = brushPowerNotes(s, listOf(256.0, 255.9, 256.1))
        assertEquals(1, notes.size)
        assertTrue(brushPowerNotes(s, listOf(248.0, 248.5, 247.8)).isEmpty())
    }
}
