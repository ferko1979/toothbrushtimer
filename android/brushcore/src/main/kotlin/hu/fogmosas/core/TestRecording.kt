package hu.fogmosas.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.io.File
import java.io.RandomAccessFile
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Test builds only ("Tesztfelvétel" switch): saves the microphone audio as a 16 kHz mono WAV and the
 * detector's timeline (scores every 0.5 s, events, result) as JSON, so a tester can send both to the
 * developers. Same format as ios/BrushCore/.../TestRecording.swift. Not thread-safe across threads
 * except through the synchronized methods.
 */
class TestRecording(dir: File, private val meta: Map<String, Any?>) {
    companion object {
        const val MAX_SECONDS = 8 * 60
        private const val RATE = 16000

        /** Newest recording (wav + json) in the folder, if any. */
        fun latest(dir: File): List<File> {
            val json = dir.listFiles { f -> f.name.endsWith(".json") }?.maxByOrNull { it.name } ?: return emptyList()
            val wav = File(dir, json.name.removeSuffix(".json") + ".wav")
            return listOfNotNull(wav.takeIf { it.exists() }, json)
        }

        /** Keeps the newest few recordings. */
        fun prune(dir: File, keep: Int = 5) {
            val jsons = dir.listFiles { f -> f.name.endsWith(".json") }?.sortedByDescending { it.name } ?: return
            for (j in jsons.drop(keep)) { j.delete(); File(dir, j.name.removeSuffix(".json") + ".wav").delete() }
        }
    }

    val base: String = "denthub-brush-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
    val wavFile = File(dir.apply { mkdirs() }, "$base.wav")
    val jsonFile = File(dir, "$base.json")
    private val raf = RandomAccessFile(wavFile, "rw").apply { setLength(0); write(ByteArray(44)) }
    private var samples = 0L
    private val rows = ArrayList<JsonArray>()
    private val events = ArrayList<JsonArray>()
    private var closed = false
    private val buf = ByteArray(2 * 4096)

    @Synchronized fun append(x: FloatArray, n: Int) {
        if (closed || samples >= MAX_SECONDS.toLong() * RATE) return
        var i = 0
        while (i < n) {
            val m = minOf(n - i, 4096)
            for (k in 0 until m) {
                val v = (x[i + k].coerceIn(-1f, 1f) * 32767f).toInt()
                buf[2 * k] = (v and 0xff).toByte(); buf[2 * k + 1] = ((v shr 8) and 0xff).toByte()
            }
            raf.write(buf, 0, 2 * m)
            i += m
        }
        samples += n
    }

    private fun num(d: Double) = JsonPrimitive(Math.round(d * 1000) / 1000.0)

    @Synchronized fun row(r: ScoreRow, state: String, rmsDb: Double = -120.0) {
        if (!closed) rows += JsonArray(listOf(num(r.t), num(r.brush), num(r.water), num(r.sonic), num(r.sonicF0), JsonPrimitive(state), num(rmsDb)))
    }

    @Synchronized fun event(t: Double, name: String) {
        if (!closed) events += JsonArray(listOf(num(t), JsonPrimitive(name)))
    }

    /** Finalises the WAV header and writes the JSON. result: durationS, endReason, cue, waterRunningS (or empty). */
    @Synchronized fun finish(result: Map<String, Any?>): List<File> {
        if (closed) return listOf(wavFile, jsonFile)
        closed = true
        val dataBytes = samples * 2
        raf.seek(0)
        raf.write(wavHeader(dataBytes))
        raf.close()
        fun js(v: Any?): kotlinx.serialization.json.JsonElement = when (v) {
            null -> kotlinx.serialization.json.JsonNull
            is Number -> JsonPrimitive(v)
            is Boolean -> JsonPrimitive(v)
            is Map<*, *> -> JsonObject(v.entries.associate { it.key.toString() to js(it.value) })
            else -> JsonPrimitive(v.toString())
        }
        val obj = JsonObject(mapOf(
            "format" to JsonPrimitive("denthub-brush-test-1"),
            "wav" to JsonPrimitive(wavFile.name),
            "sampleRate" to JsonPrimitive(RATE),
            "audioSeconds" to JsonPrimitive(samples.toDouble() / RATE),
            "meta" to js(meta),
            "result" to js(result),
            "rowColumns" to JsonArray(listOf("t", "brush", "water", "sonic", "sonicF0", "state", "rmsDb").map { JsonPrimitive(it) }),
            "rows" to JsonArray(rows),
            "events" to JsonArray(events),
        ))
        jsonFile.writeText(obj.toString())
        return listOf(wavFile, jsonFile)
    }

    private fun wavHeader(dataBytes: Long): ByteArray {
        val b = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()); b.putInt((36 + dataBytes).toInt()); b.put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()); b.putInt(16); b.putShort(1); b.putShort(1); b.putInt(RATE); b.putInt(RATE * 2)
        b.putShort(2); b.putShort(16)
        b.put("data".toByteArray()); b.putInt(dataBytes.toInt())
        return b.array()
    }
}
