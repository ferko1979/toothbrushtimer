package hu.fogmosas.app

import android.content.Context
import androidx.compose.runtime.mutableStateOf
import hu.fogmosas.core.TestAccess
import hu.fogmosas.core.tr
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Test mode: every recording, timeline and remark goes up to the DentHub-Brush server on its own
 * (web/testupload.mjs; from there to Google Drive). What is up is listed in recordings/.uploaded
 * ("name:size"), so a remark edited later goes up again. Without network it waits for the next try
 * (after a recording, a remark, opening the app, or "Feltöltés most").
 */
object TestUploader {
    val status = mutableStateOf("")
    private val running = AtomicBoolean(false)

    fun uploadPending(ctx: Context) {
        val app = ctx.applicationContext
        val d = AppStore.get(app).data.value
        val code = d.testerCode ?: return
        if (!d.settings.isOn("test_recording", "android") || !running.compareAndSet(false, true)) return
        Thread {
            try {
                val dir = BrushingEngine.recordingsDir(app)
                val list = File(dir, ".uploaded")
                val done = (if (list.exists()) list.readLines() else emptyList()).toMutableSet()
                val todo = TestAccess.pending(dir, done)
                if (todo.isEmpty()) { status.value = tr("✓ Minden felvétel feltöltve."); return@Thread }
                val host = (d.denthubHost ?: TestAccess.DEFAULT_HOST).trimEnd('/')
                var ok = 0
                for (f in todo) {
                    status.value = tr("Feltöltés: {0} / {1}…", ok + 1, todo.size)
                    val c = (URL("$host/api/test-upload/${f.name}").openConnection() as HttpURLConnection).apply {
                        requestMethod = "POST"; doOutput = true; connectTimeout = 15_000; readTimeout = 60_000
                        setFixedLengthStreamingMode(f.length())
                        setRequestProperty("X-Tester-Code", code)
                        setRequestProperty("X-Tester-Device", device(dir))
                        setRequestProperty("Content-Type", "application/octet-stream")
                    }
                    f.inputStream().use { input -> c.outputStream.use { input.copyTo(it) } }
                    val rc = c.responseCode
                    c.disconnect()
                    if (rc == 401) { status.value = tr("A szerver nem fogadta el a tesztelői jelszót."); return@Thread }
                    if (rc !in 200..299) { status.value = tr("Feltöltés sikertelen ({0}), később újra próbálom.", rc); return@Thread }
                    done += TestAccess.key(f)
                    list.writeText(done.joinToString("\n"))
                    ok++
                }
                status.value = tr("✓ {0} fájl feltöltve.", ok)
            } catch (e: Exception) {
                status.value = tr("Nincs kapcsolat a szerverrel, később újra próbálom.")
            } finally {
                running.set(false)
            }
        }.start()
    }

    /** A random id per install, so the recordings of one phone stay together. */
    private fun device(dir: File): String {
        val f = File(dir, ".device")
        if (!f.exists()) f.writeText("android-" + java.util.UUID.randomUUID().toString().take(8))
        return f.readText().trim()
    }
}
