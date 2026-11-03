package hu.fogmosas.core

import kotlin.math.PI
import kotlin.math.sin
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WatchHandTest {
    @Test
    fun placementFromHands() {
        val same = watchListening("right", "right")
        assertTrue(same.sameHand && same.useMotion)
        assertEquals(14.0, same.nearGateDb)
        val other = watchListening("right", "left")
        assertTrue(!other.sameHand && !other.useMotion)
        assertEquals(8.0, other.nearGateDb)
    }

    @Test
    fun strokeRhythmScoresHigh() {
        val m = MotionRhythm()
        // 4 Hz back-and-forth along a tilted axis, 0.15 g.
        for (i in 0 until 150) {
            val v = 0.15 * sin(2 * PI * 4.0 * i / 50.0)
            m.add(v * 0.6, v * 0.8, 0.0)
        }
        assertTrue(m.score() > 0.8, "score ${m.score()}")
    }

    @Test
    fun stillnessAndSlowMovesScoreLow() {
        val still = MotionRhythm()
        repeat(150) { still.add(0.0, 0.0, 0.0) }
        assertEquals(0.0, still.score())

        val tiny = MotionRhythm()
        val rnd = Random(1)
        repeat(150) { tiny.add(rnd.nextDouble(-0.005, 0.005), rnd.nextDouble(-0.005, 0.005), 0.0) }
        assertTrue(tiny.score() < 0.1, "tiny ${tiny.score()}")

        val slow = MotionRhythm()   // walking-arm swing ~1 Hz
        for (i in 0 until 150) slow.add(0.3 * sin(2 * PI * 1.0 * i / 50.0), 0.0, 0.0)
        assertTrue(slow.score() < 0.1, "slow ${slow.score()}")

        assertEquals(0.0, MotionRhythm().score())
    }
}
