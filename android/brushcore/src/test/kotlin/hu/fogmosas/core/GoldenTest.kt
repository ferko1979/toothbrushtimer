package hu.fogmosas.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The Kotlin port must reproduce the Python reference (analysis/export_golden.py). */
class GoldenTest {
    private fun res(name: String) = GoldenTest::class.java.getResourceAsStream("/golden/$name")!!.readBytes()
    private val exp: JsonObject = Json.parseToJsonElement(String(res("golden_expected.json"))).jsonObject
    private val x = WavReader.read(res("golden_audio.wav")).first
    private val heads = ModelHeads.fromJson(String(res("golden_model.json")))
    private fun tol(k: String) = exp["tolerance"]!!.jsonObject[k]!!.jsonPrimitive.double
    private fun arr(e: kotlinx.serialization.json.JsonElement) = e.jsonArray.map { it.jsonPrimitive.double }

    private fun assertClose(a: List<Double>, b: List<Double>, tol: Double, what: String) {
        assertEquals(b.size, a.size, "$what: length")
        var worst = 0.0
        var at = -1
        for (i in a.indices) if (abs(a[i] - b[i]) > worst) { worst = abs(a[i] - b[i]); at = i }
        assertTrue(worst <= tol, "$what: max diff $worst at $at")
    }

    @Test fun logMel() {
        val frames = LogMelExtractor().frames(x)
        val m = exp["log_mel"]!!.jsonObject
        assertEquals(arr(m["shape"]!!).map { it.toInt() }, listOf(frames.size, frames[0].size))
        m["first_frames"]!!.jsonArray.forEachIndexed { i, row -> assertClose(frames[i].toList(), arr(row), tol("log_mel"), "frame $i") }
        assertClose(frames[400].toList(), arr(m["frame_400"]!!), tol("log_mel"), "frame 400")
    }

    @Test fun windowFeatures() {
        val frames = LogMelExtractor().frames(x)
        for ((key, win) in listOf("brush_windows" to WindowFeatureExtractor.BRUSH_WINDOW, "water_windows" to WindowFeatureExtractor.WATER_WINDOW)) {
            val (t, f) = WindowFeatureExtractor.allWindows(frames, win)
            val e = exp[key]!!.jsonObject
            assertClose(t, arr(e["t"]!!), 1e-6, "$key times")
            val ef = e["features"]!!.jsonArray
            assertEquals(ef.size, f.size)
            for (i in f.indices) assertClose(f[i].toList(), arr(ef[i]), tol("features"), "$key $i")
        }
    }

    @Test fun streamingScoresAndSession() {
        val det = StreamingDetector(heads)
        val rows = ArrayList<ScoreRow>()
        det.onRow = { rows += it }
        val chunks = intArrayOf(1600, 4096, 777, 16000, 3200)
        var i = 0
        var c = 0
        while (i < x.size) {
            val n = minOf(chunks[c % chunks.size], x.size - i)
            det.append(FloatArray(n) { x[i + it].toFloat() })
            i += n; c++
        }
        val sessions = det.finish()
        val s = exp["scores"]!!.jsonObject
        assertClose(rows.map { it.t }, arr(s["t"]!!), 1e-6, "t")
        assertClose(rows.map { it.water }, arr(s["water"]!!), tol("probabilities"), "water")
        assertClose(rows.map { it.brush }, arr(s["brush"]!!), tol("probabilities"), "brush")
        assertClose(rows.map { it.sonic }, arr(s["sonic"]!!), tol("sonic_score"), "sonic")
        val es = exp["sessions"]!!.jsonArray
        assertEquals(es.size, sessions.size)
        for ((a, e) in sessions.zip(es)) {
            assertTrue(abs(a.start - e.jsonObject["start"]!!.jsonPrimitive.double) <= tol("session_s"))
            assertTrue(abs(a.end - e.jsonObject["end"]!!.jsonPrimitive.double) <= tol("session_s"))
        }
        val events = exp["events"]!!.jsonArray.map { (it as JsonArray)[1].jsonPrimitive.content }
        assertEquals(events, det.session.events.map { it.second.id })
    }

    @Test fun bundledModel() {
        val h = ModelHeads.bundled()
        assertEquals(WindowFeatureExtractor.FEATURE_COUNT, h.brush.coef.size)
    }
}
