package hu.fogmosas.wear

import android.Manifest
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService
import hu.fogmosas.core.BrushRecord
import hu.fogmosas.core.CareEntry
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.Goals
import hu.fogmosas.core.ModelHeads
import hu.fogmosas.core.SonicConfig
import hu.fogmosas.core.brushProgress
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine
import hu.fogmosas.shared.WearSync
import java.time.LocalDate
import hu.fogmosas.core.tr

private val brand = Color(0xFF1E9BB8)
private val brand2 = Color(0xFF57C5B6)

class WearActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val store = AppStore.get(this)
        BrushingEngine.onFinished = { r ->
            if (r.durationS >= 5) {
                val rec = BrushRecord(profileId = "me", startMs = r.startMs, durationS = r.durationS,
                    waterRunningS = r.waterRunningS, source = "watch", brushF0 = r.brushF0)
                store.addRecord(rec)
                WearSync.sendRecord(this, rec)
                androidx.wear.tiles.TileService.getUpdater(this).requestUpdate(ProgressTileService::class.java)
            }
        }
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        setContent { MaterialTheme { androidx.compose.runtime.key(refreshTick.intValue) { WearRoot(this, store) } } }
    }

    /** Bumped on every return to the watch app: today's count is reread (e.g. the next morning). */
    val refreshTick = androidx.compose.runtime.mutableIntStateOf(0)

    override fun onResume() {
        super.onResume()
        val st = BrushingEngine.state.value
        if (!st.active && st.result == null) refreshTick.intValue++
    }

    // Watch on the brushing hand: the wrist rhythm (linear acceleration) is brushing evidence.
    private val rhythm = hu.fogmosas.core.MotionRhythm()
    private var motionListener: android.hardware.SensorEventListener? = null
    private var gravityListener: android.hardware.SensorEventListener? = null
    /** Experimental left/right balance from the wrist roll. */
    val side = hu.fogmosas.core.SideBalance()

    fun startMotion() {
        if (motionListener != null) return
        val sm = getSystemService(android.hardware.SensorManager::class.java) ?: return
        val sensor = sm.getDefaultSensor(android.hardware.Sensor.TYPE_LINEAR_ACCELERATION) ?: return
        rhythm.reset()
        var n = 0
        val l = object : android.hardware.SensorEventListener {
            override fun onSensorChanged(e: android.hardware.SensorEvent) {
                val g = 9.80665
                rhythm.add(e.values[0] / g, e.values[1] / g, e.values[2] / g)
                if (++n % 25 == 0) BrushingEngine.setMotionBrush(rhythm.score())
            }
            override fun onAccuracyChanged(s: android.hardware.Sensor?, a: Int) {}
        }
        sm.registerListener(l, sensor, 20_000)   // 50 Hz
        motionListener = l
        side.reset()
        sm.getDefaultSensor(android.hardware.Sensor.TYPE_GRAVITY)?.let { gs ->
            var last = 0L
            val gl = object : android.hardware.SensorEventListener {
                override fun onSensorChanged(e: android.hardware.SensorEvent) {
                    val dt = if (last == 0L) 0.0 else (e.timestamp - last) / 1e9
                    last = e.timestamp
                    val st = BrushingEngine.state.value
                    side.add(e.values[0] / 9.80665, dt.coerceIn(0.0, 0.5), st.phase == BrushingEngine.Phase.BRUSHING, st.elapsedS)
                }
                override fun onAccuracyChanged(s: android.hardware.Sensor?, a: Int) {}
            }
            sm.registerListener(gl, gs, 100_000)   // 10 Hz is plenty for the roll
            gravityListener = gl
        }
    }

    fun stopMotion() {
        motionListener?.let { getSystemService(android.hardware.SensorManager::class.java)?.unregisterListener(it) }
        gravityListener?.let { getSystemService(android.hardware.SensorManager::class.java)?.unregisterListener(it) }
        motionListener = null
        gravityListener = null
    }

    fun keepScreenOn(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}

@Composable
fun WearRoot(activity: WearActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val s by BrushingEngine.state.collectAsStateWithLifecycle()
    val heads = remember { runCatching { ModelHeads.bundled() }.getOrNull() }
    val goals = data.activeProfile.goals
    val placement = remember(data.activeProfile.brushHand, data.activeProfile.watchWrist) {
        hu.fogmosas.core.watchListening(data.activeProfile.brushHand, data.activeProfile.watchWrist)
    }
    LaunchedEffect(s.active) {
        activity.keepScreenOn(s.active)
        if (s.active && placement.useMotion) activity.startMotion() else activity.stopMotion()
    }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        val r = s.result
        when {
            r != null -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(vertical = 24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (r.durationS >= goals.targetS) "🎉" else "💪", fontSize = 30.sp)
                Text(Formatting.clock(r.durationS), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(if (r.durationS >= goals.targetS) tr("Cél elérve") else tr("Még {0} s hiányzott", (goals.targetS - r.durationS).toInt()),
                    fontSize = 12.sp, color = Color.LightGray)
                Text(if (r.waterRunningS >= 5) tr("🚰 folyt a csap") else tr("💧 elzárt csap"), fontSize = 12.sp)
                if (placement.useMotion) activity.side.note()?.let { Text(it, fontSize = 11.sp, color = Color.LightGray, textAlign = TextAlign.Center) }
                (r.notes.firstOrNull() ?: r.timerNote)?.let { Text(it, fontSize = 11.sp, color = Color(0xFFE8833A), textAlign = TextAlign.Center) }
                // Quick journal: floss, bleeding gums, sensitivity (saved on the phone).
                var floss by remember(r) { mutableStateOf(false) }
                var bleed by remember(r) { mutableStateOf(false) }
                var sens by remember(r) { mutableStateOf(false) }
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for ((label, on, flip) in listOf(
                        Triple("🧵", floss) { floss = !floss }, Triple("🩸", bleed) { bleed = !bleed }, Triple("⚡", sens) { sens = !sens })) {
                        val desc = when (label) { "🧵" -> tr("Fogselyem"); "🩸" -> tr("Vérzett az íny"); else -> tr("Érzékeny fog") }
                        Button(onClick = flip, modifier = Modifier.size(36.dp).semantics { contentDescription = desc; selected = on },
                            colors = if (on) ButtonDefaults.buttonColors(backgroundColor = brand) else ButtonDefaults.secondaryButtonColors()) { Text(label, fontSize = 14.sp) }
                    }
                }
                Button(onClick = {
                    if (floss || bleed || sens) {
                        val e = CareEntry(profileId = "me", dateMs = System.currentTimeMillis(), floss = floss, bleeding = bleed, sensitivity = if (sens) 1 else 0)
                        store.addCare(e)
                        WearSync.sendCare(activity, e)
                    }
                    BrushingEngine.reset()
                }, colors = ButtonDefaults.secondaryButtonColors()) { Text("OK") }
            }
            s.phase == BrushingEngine.Phase.BRUSHING || s.phase == BrushingEngine.Phase.RINSING -> {
                val p = brushProgress(s.elapsedS, goals.targetS)
                CircularProgressIndicator(progress = p.fraction.toFloat(), modifier = Modifier.fillMaxSize().padding(4.dp),
                    indicatorColor = if (s.wasteIcon) Color(0xFFE8833A) else brand2, strokeWidth = 8.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(p.quadrantName, fontSize = 12.sp, color = Color.LightGray)
                    Text(Formatting.clock(s.elapsedS), fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    if (s.wasteIcon) Text(tr("🚰 Folyik a csap!"), fontSize = 11.sp, color = Color(0xFFE8833A))
                    Button(onClick = { BrushingEngine.stop() }, colors = ButtonDefaults.secondaryButtonColors()) { Text(tr("Kész"), fontSize = 12.sp) }
                }
            }
            s.active -> Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (s.phase == BrushingEngine.Phase.WATER) "🚰" else "🚰 → 🪥", fontSize = 24.sp)
                Text(tr("Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted."), fontSize = 12.sp, textAlign = TextAlign.Center, color = Color.LightGray)
                Button(onClick = { BrushingEngine.startManual(activity) }, colors = ButtonDefaults.secondaryButtonColors()) { Text("⏱", fontSize = 14.sp) }
            }
            else -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("🪥", fontSize = 34.sp)
                val rs = data.records("me")
                Text(tr("Ma {0}/{1} · 🔥 {2}", store.coach.todayCount(rs, LocalDate.now()), goals.perDay, store.coach.perfectStreak(rs, goals, LocalDate.now())),
                    fontSize = 12.sp, color = Color.LightGray)
                Button(onClick = {
                    BrushingEngine.start(activity, BrushingEngine.Config(
                        heads = heads, autoDetect = true, armed = false, sonicConfig = SonicConfig(bandLowHz = 60.0, lockOn = true), useSonic = true,
                        batterySaver = true, targetS = goals.targetS, cues = true, keepListeningWhenPlaced = false,
                        nearGateDb = placement.nearGateDb))
                }, colors = ButtonDefaults.buttonColors(backgroundColor = brand)) { Text("▶", fontSize = 20.sp) }
            }
        }
        if (s.phase == BrushingEngine.Phase.FAILED) Text(s.error ?: "", fontSize = 11.sp, color = Color.Red)
    }
}

/** Goals pushed from the phone app. */
class WearListenerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        for (e in events) {
            if (e.type != DataEvent.TYPE_CHANGED || e.dataItem.uri.path != WearSync.PATH_GOALS) continue
            val map = DataMapItem.fromDataItem(e.dataItem).dataMap
            val g = Goals(map.getInt("perDay", 2), map.getDouble("targetS", 120.0)).clamped()
            val store = AppStore.get(this)
            store.data.value.profile("me")?.let {
                store.updateProfile(it.copy(goals = g, brushHand = map.getString("brushHand", "right"), watchWrist = map.getString("watchWrist", "left")))
            }
            androidx.wear.tiles.TileService.getUpdater(this).requestUpdate(ProgressTileService::class.java)
        }
    }
}
