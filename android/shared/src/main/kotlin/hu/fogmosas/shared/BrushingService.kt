package hu.fogmosas.shared

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import hu.fogmosas.core.Formatting
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Foreground service (type microphone): keeps listening while the screen is off
 * and shows the ongoing brushing as a notification. Feeds the gravity sensor to
 * the listening policy (is the phone lying flat?).
 */
class BrushingService : Service(), SensorEventListener {
    companion object {
        const val EXTRA_KEEP_LISTENING = "keep_listening"
        private const val CHANNEL = "brushing"
        private const val ID = 42
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var sensors: SensorManager? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(NotificationChannel(CHANNEL, "Fogmosás folyamatban", NotificationManager.IMPORTANCE_LOW))
        }
        val type = if (Build.VERSION.SDK_INT >= 30) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
        ServiceCompat.startForeground(this, ID, build("Figyelek…"), type)
        if (intent?.getBooleanExtra(EXTRA_KEEP_LISTENING, false) == true && sensors == null) {
            sensors = getSystemService(SensorManager::class.java)?.also { sm ->
                sm.getDefaultSensor(Sensor.TYPE_GRAVITY)?.let { sm.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
            }
        }
        val live = AppStore.get(this).data.value.settings.isOn("live_activity", "android")
        scope.launch {
            var lastKey = ""
            BrushingEngine.state.collect { s ->
                if (!s.active) {
                    stopSelf()
                    return@collect
                }
                val brushing = s.phase == BrushingEngine.Phase.BRUSHING || s.phase == BrushingEngine.Phase.RINSING
                val text = when (s.phase) {
                    BrushingEngine.Phase.BRUSHING -> (if (live) "Fogmosás" else "${Formatting.clock(s.elapsedS)} · fogmosás") + if (s.wasteIcon) " · 🚰 folyik a csap!" else ""
                    BrushingEngine.Phase.RINSING -> "Öblítés…"
                    BrushingEngine.Phase.WATER -> "Folyik a víz… Nedvesítsd a fogkefét, majd zárd el a csapot."
                    BrushingEngine.Phase.ARMED -> "Várom a fogmosást…"
                    else -> "Figyelek…"
                }
                // Live mode: the system chronometer counts; refresh only on change and once a second for the bar.
                val key = "${s.phase}|${s.wasteIcon}|${if (live && brushing) s.elapsedS.toInt() else if (live) 0 else (s.elapsedS * 2).toInt()}"
                if (key == lastKey) return@collect
                lastKey = key
                nm.notify(ID, build(text, if (live && brushing) s.elapsedS else null))
            }
        }
        return START_NOT_STICKY
    }

    /** elapsedS != null: live mode with a running chronometer and a progress bar towards the goal. */
    private fun build(text: String, elapsedS: Double? = null): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        val b = NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_brush)
            .setContentTitle("🪥 Fogmosás")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .setContentIntent(pi)
        if (elapsedS != null) {
            val target = BrushingEngine.currentTargetS
            b.setUsesChronometer(true)
                .setWhen(System.currentTimeMillis() - (elapsedS * 1000).toLong())
                .setShowWhen(true)
                .setProgress(target.toInt(), minOf(elapsedS, target).toInt(), false)
                .setSubText("cél ${Formatting.clock(target)}")
        }
        return b.build()
    }

    override fun onSensorChanged(event: SensorEvent) {
        val g = 9.80665
        BrushingEngine.motion(event.values[0] / g, event.values[1] / g, event.values[2] / g)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onDestroy() {
        sensors?.unregisterListener(this)
        scope.cancel()
        super.onDestroy()
    }
}
