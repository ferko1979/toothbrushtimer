package hu.fogmosas.app

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.CareTask
import hu.fogmosas.core.CareTaskPresets
import hu.fogmosas.core.FollowUps
import hu.fogmosas.core.I18n
import hu.fogmosas.core.SymptomFollowUp
import hu.fogmosas.core.SymptomReport
import hu.fogmosas.core.Symptoms
import hu.fogmosas.core.ToothMap
import hu.fogmosas.core.followUpAdvice
import hu.fogmosas.core.followUpDue
import hu.fogmosas.core.motorTrend
import hu.fogmosas.core.tr
import hu.fogmosas.shared.AppStore
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

// Tooth map, follow-up questions, photo timeline, care task reminders and the motor trend.

/** Adult teeth by quadrant (FDI); tap to select. */
@Composable
fun ToothMapPicker(selected: Set<String>, onChange: (Set<String>) -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Color.White).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(tr("A fogakat szemből nézve látod: a te jobb oldalad a kép bal oldalán."), fontSize = 12.sp, color = C.muted)
        ToothMap.quadrants.forEach { (label, teeth) ->
            Text(label, fontSize = 12.sp, fontWeight = FontWeight.Bold)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                teeth.forEach { t ->
                    val on = t in selected
                    OutlinedButton(onClick = { onChange(if (on) selected - t else selected + t) },
                        Modifier.weight(1f).height(44.dp).semantics { contentDescription = ToothMap.name(t); selected = on }, shape = RoundedCornerShape(10.dp),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                        border = BorderStroke(if (on) 2.dp else 1.dp, if (on) C.brand else Color(0xFFC9D6DD)),
                        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (on) C.brand else Color(0xFFF2F6F8))) {
                        Text(t, fontSize = 12.sp, color = if (on) Color.White else Color(0xFF1B2B34))
                    }
                }
            }
        }
        if (selected.isNotEmpty()) Text(selected.sorted().joinToString(", ") { ToothMap.name(it) }, fontSize = 12.sp, color = C.brand)
    }
}

/** Earlier photos of the same complaint side by side, oldest first. */
@Composable
fun PhotoTimeline(reports: List<SymptomReport>) {
    if (reports.isEmpty()) return
    val ctx = LocalContext.current
    val zone = ZoneId.systemDefault()
    Text(tr("Fotók időrendben"), fontWeight = FontWeight.Bold, fontSize = 14.sp)
    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        reports.forEach { r ->
            r.photos.forEach { name ->
                val bmp = remember(name) { ClinicFiles.thumb(ctx, name, 320) }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    if (bmp != null) Image(bmp.asImageBitmap(), null, Modifier.size(110.dp).clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Crop)
                    Text(I18n.date(Instant.ofEpochMilli(r.dateMs).atZone(zone).toLocalDate()), fontSize = 11.sp, color = C.muted)
                }
            }
        }
    }
}

/** Home: "Hogy van most?" 1, 3 and 7 days after a complaint. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FollowUpCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!p.canRead) return
    val ctx = LocalContext.current
    val now = System.currentTimeMillis()
    val due = data.symptoms.filter { it.profileId == p.id }.sortedByDescending { it.dateMs }
        .firstNotNullOfOrNull { r -> followUpDue(r, data.followUps, now)?.let { r to it } }
    var reply by remember { mutableStateOf<Pair<String, Boolean>?>(null) }
    reply?.let { (text, contact) ->
        InfoCard {
            Text(text, fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (contact) OutlinedButton(onClick = { activity.overlay.value = "visit"; reply = null }) { Text(tr("📅 Időpontot kérek")) }
                TextButton(onClick = { reply = null }) { Text(tr("Rendben")) }
            }
        }
        return
    }
    val (r, day) = due ?: return
    InfoCard {
        Text(tr("Hogy van most?"), fontWeight = FontWeight.Bold)
        Text(tr("{0} – {1} napja jelezted.", Symptoms.kind(r.kind).title, day), fontSize = 13.sp, color = C.muted)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            FollowUps.answers.forEach { (id, label) ->
                OutlinedButton(onClick = {
                    store.addFollowUp(SymptomFollowUp(r.id, day, id, System.currentTimeMillis()))
                    if (id == "visited") store.updateProfile(p.copy(lastCheckup = LocalDate.now().toString()))
                    ReminderScheduler.reschedule(ctx)
                    reply = followUpAdvice(r, id, day)
                }) { Text(label) }
            }
        }
    }
}

/** Home: today's medicine / care tasks to tick off, and a button to add one. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CareTasksCard(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!p.canRead) return
    val ctx = LocalContext.current
    val today = LocalDate.now()
    val tasks = data.careTasks.filter { it.profileId == p.id && it.activeOn(today) }
    var add by remember { mutableStateOf(false) }
    if (tasks.isEmpty()) {
        if (add) CareTaskDialog(store, p.id) { add = false }
        return
    }
    InfoCard {
        Text(tr("💊 Mai teendők"), fontWeight = FontWeight.Bold)
        tasks.forEach { t ->
            val (done, all) = t.progress(today)
            Text(tr("{0} · {1}/{2} · még {3} nap", t.title, done, all, java.time.temporal.ChronoUnit.DAYS.between(today, t.lastDate()) + 1), fontSize = 14.sp)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                t.times.forEach { time ->
                    FilterChip(selected = t.isDone(today, time), onClick = {
                        store.putCareTask(t.toggle(today, time))
                        ReminderScheduler.reschedule(ctx)
                    }, label = { Text((if (t.isDone(today, time)) "✔︎ " else "") + time) })
                }
                TextButton(onClick = { store.removeCareTask(t.id); ReminderScheduler.reschedule(ctx) }) { Text(tr("Törlés")) }
            }
        }
        TextButton(onClick = { add = true }) { Text(tr("＋ Új emlékeztető")) }
    }
    if (add) CareTaskDialog(store, p.id) { add = false }
}

/** New medicine / care task: preset or own title, times a day, number of days. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CareTaskDialog(store: AppStore, profileId: String, onClose: () -> Unit) {
    val ctx = LocalContext.current
    var title by remember { mutableStateOf("") }
    var perDay by remember { mutableIntStateOf(2) }
    var days by remember { mutableIntStateOf(7) }
    var times by remember { mutableStateOf(CareTaskPresets.times(2)) }
    AlertDialog(onDismissRequest = onClose, title = { Text(tr("Gyógyszer / teendő emlékeztető")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    CareTaskPresets.all.forEach { pr ->
                        FilterChip(selected = title == pr.title, onClick = { title = pr.title; times = pr.times; perDay = pr.times.size; days = pr.days },
                            label = { Text(pr.title, fontSize = 12.sp) })
                    }
                }
                OutlinedTextField(title, { title = it }, label = { Text(tr("Mit kell tenni?")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Stepper(tr("Naponta {0}×: {1}", perDay, times.joinToString(", ")), {
                    perDay = (perDay - 1).coerceAtLeast(1); times = CareTaskPresets.times(perDay)
                }, { perDay = (perDay + 1).coerceAtMost(4); times = CareTaskPresets.times(perDay) })
                Stepper(tr("{0} napig", days), { days = (days - 1).coerceAtLeast(1) }, { days = (days + 1).coerceAtMost(30) })
                Text(tr("Mindig az orvos vagy a betegtájékoztató utasítása szerint szedd a gyógyszert."), fontSize = 12.sp, color = C.muted)
            }
        },
        confirmButton = {
            TextButton(enabled = title.isNotBlank(), onClick = {
                store.putCareTask(CareTask(profileId = profileId, title = title.trim(), times = times, start = LocalDate.now().toString(), days = days))
                ReminderScheduler.reschedule(ctx)
                onClose()
            }) { Text(tr("Mentés")) }
        },
        dismissButton = { TextButton(onClick = onClose) { Text(tr("Mégse")) } })
}

/** Statistics, electric brush: weekly motor frequency (battery health). */
@Composable
fun MotorTrendCard(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!p.electric || !p.canRead) return
    val zone = ZoneId.systemDefault()
    val t = remember(data.records) { motorTrend(data.records(p.id), LocalDate.now(zone), zone) }
    InfoCard {
        Text(tr("🔋 Fogkefe-akku (motor zúgása hetente)"), fontWeight = FontWeight.Bold)
        if (t.weeks.isNotEmpty()) {
            val lo = t.weeks.minOf { it.medianHz } - 3
            val hi = t.weeks.maxOf { it.medianHz } + 1
            Row(Modifier.fillMaxWidth().height(90.dp), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.Bottom) {
                t.weeks.forEach { w ->
                    val frac = ((w.medianHz - lo) / (hi - lo)).toFloat().coerceIn(0.1f, 1f)
                    Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("${w.medianHz.toInt()}", fontSize = 10.sp, color = C.muted)
                        Box(Modifier.fillMaxWidth().height((70 * frac).dp).clip(RoundedCornerShape(4.dp)).background(C.brand))
                    }
                }
            }
        }
        Text(t.text, fontSize = 13.sp, color = if ((t.changePct ?: 0.0) <= -2.0) C.warn else C.muted)
    }
}

/** Home: a quick way to add a care reminder when none is running. */
@Composable
fun AddCareTaskButton(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!p.canRead || data.careTasks.any { it.profileId == p.id && it.activeOn(LocalDate.now()) }) return
    var add by remember { mutableStateOf(false) }
    TextButton(onClick = { add = true }) { Text(tr("💊 Gyógyszer / teendő emlékeztető")) }
    if (add) CareTaskDialog(store, p.id) { add = false }
}

/** Care instructions from the clinic (denthub://care link or QR): add as a reminder after confirming. */
@Composable
fun CareLinkDialog(activity: MainActivity, store: AppStore) {
    val c = activity.pendingCare.value ?: return
    val ctx = LocalContext.current
    val p = store.data.collectAsStateWithLifecycle().value.activeProfile
    AlertDialog(onDismissRequest = { activity.pendingCare.value = null },
        title = { Text(tr("Utasítás a rendelőtől")) },
        text = {
            Text(listOfNotNull(c.clinic, c.title, tr("Naponta {0}×: {1}", c.times.size, c.times.joinToString(", ")), tr("{0} napig", c.days),
                tr("Emlékeztetőként felvesszük ide: {0}", p.name)).joinToString("\n"))
        },
        confirmButton = {
            TextButton(onClick = {
                store.putCareTask(CareTask(profileId = p.id, title = c.title, times = c.times, start = LocalDate.now().toString(), days = c.days))
                ReminderScheduler.reschedule(ctx)
                activity.pendingCare.value = null
            }) { Text(tr("Felvétel")) }
        },
        dismissButton = { TextButton(onClick = { activity.pendingCare.value = null }) { Text(tr("Mégse")) } })
}
