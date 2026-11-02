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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
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
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.Goals
import hu.fogmosas.core.ModelHeads
import hu.fogmosas.core.SonicConfig
import hu.fogmosas.core.brushProgress
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine
import hu.fogmosas.shared.WearSync
import java.time.LocalDate

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
            }
        }
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1)
        setContent { MaterialTheme { WearRoot(this, store) } }
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
    LaunchedEffect(s.active) { activity.keepScreenOn(s.active) }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        val r = s.result
        when {
            r != null -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(if (r.durationS >= goals.targetS) "🎉" else "💪", fontSize = 30.sp)
                Text(Formatting.clock(r.durationS), fontSize = 22.sp, fontWeight = FontWeight.Bold)
                Text(if (r.durationS >= goals.targetS) "Cél elérve" else "Még ${(goals.targetS - r.durationS).toInt()} s hiányzott",
                    fontSize = 12.sp, color = Color.LightGray)
                Text(if (r.waterRunningS >= 5) "🚰 folyt a csap" else "💧 elzárt csap", fontSize = 12.sp)
                Button(onClick = { BrushingEngine.reset() }, colors = ButtonDefaults.secondaryButtonColors()) { Text("OK") }
            }
            s.phase == BrushingEngine.Phase.BRUSHING || s.phase == BrushingEngine.Phase.RINSING -> {
                val p = brushProgress(s.elapsedS, goals.targetS)
                CircularProgressIndicator(progress = p.fraction.toFloat(), modifier = Modifier.fillMaxSize().padding(4.dp),
                    indicatorColor = if (s.wasteIcon) Color(0xFFE8833A) else brand2, strokeWidth = 8.dp)
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(p.quadrantName, fontSize = 12.sp, color = Color.LightGray)
                    Text(Formatting.clock(s.elapsedS), fontSize = 32.sp, fontWeight = FontWeight.Bold)
                    if (s.wasteIcon) Text("🚰 Folyik a csap!", fontSize = 11.sp, color = Color(0xFFE8833A))
                    Button(onClick = { BrushingEngine.stop() }, colors = ButtonDefaults.secondaryButtonColors()) { Text("Kész", fontSize = 12.sp) }
                }
            }
            s.active -> Column(Modifier.padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(if (s.phase == BrushingEngine.Phase.WATER) "🚰" else "🚰 → 🪥", fontSize = 24.sp)
                Text("Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted.", fontSize = 12.sp, textAlign = TextAlign.Center, color = Color.LightGray)
                Button(onClick = { BrushingEngine.startManual(activity) }, colors = ButtonDefaults.secondaryButtonColors()) { Text("⏱", fontSize = 14.sp) }
            }
            else -> Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("🪥", fontSize = 34.sp)
                val rs = data.records("me")
                Text("Ma ${store.coach.todayCount(rs, LocalDate.now())}/${goals.perDay} · 🔥 ${store.coach.perfectStreak(rs, goals, LocalDate.now())}",
                    fontSize = 12.sp, color = Color.LightGray)
                Button(onClick = {
                    BrushingEngine.start(activity, BrushingEngine.Config(
                        heads = heads, autoDetect = true, armed = false, sonicConfig = SonicConfig(), useSonic = true,
                        batterySaver = true, targetS = goals.targetS, cues = true, keepListeningWhenPlaced = false))
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
            store.data.value.profile("me")?.let { store.updateProfile(it.copy(goals = g)) }
        }
    }
}
