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
        scope.launch {
            BrushingEngine.state.collect { s ->
                if (!s.active) {
                    stopSelf()
                    return@collect
                }
                val text = when (s.phase) {
                    BrushingEngine.Phase.BRUSHING -> "${Formatting.clock(s.elapsedS)} · fogmosás" + if (s.wasteIcon) " · 🚰 folyik a csap!" else ""
                    BrushingEngine.Phase.RINSING -> "Öblítés…"
                    BrushingEngine.Phase.WATER -> "Víz…"
                    else -> "Figyelek…"
                }
                nm.notify(ID, build(text))
            }
        }
        return START_NOT_STICKY
    }

    private fun build(text: String): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pi = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_brush)
            .setContentTitle("🪥 Fogmosás")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
            .build()
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
