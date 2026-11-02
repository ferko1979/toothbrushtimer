package hu.fogmosas.app

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.Achievements
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.Goals
import hu.fogmosas.core.OnboardingFlow
import hu.fogmosas.core.OnboardingQuestion
import hu.fogmosas.core.SonicDetector
import hu.fogmosas.core.WaterReport
import hu.fogmosas.core.achievementTitle
import hu.fogmosas.core.brushHeadStatus
import hu.fogmosas.core.brushProgress
import hu.fogmosas.core.detectHabits
import hu.fogmosas.core.extrasDoneToday
import hu.fogmosas.core.feedbackFor
import hu.fogmosas.core.monthlyReportText
import hu.fogmosas.core.recordsCsv
import hu.fogmosas.core.stickers
import hu.fogmosas.core.waterMessage
import hu.fogmosas.shared.AppStore
import hu.fogmosas.shared.BrushingEngine
import hu.fogmosas.shared.WearSync
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val zone: ZoneId get() = ZoneId.systemDefault()

// ------------------------------------------------------------------ onboarding

@Composable
fun QuestionFlow(flow: OnboardingFlow, stopAtMore: Boolean = false, onFinish: () -> Unit) {
    var version by remember { mutableIntStateOf(0) }
    val q: OnboardingQuestion? = remember(version) { flow.nextQuestion() }
    var selected by remember(version) { mutableStateOf(q?.defaultValue) }
    var text by remember(version) { mutableStateOf("") }
    var age by remember(version) { mutableIntStateOf(5) }
    var error by remember(version) { mutableStateOf<String?>(null) }
    if (q == null || (stopAtMore && q.id == "more")) {
        LaunchedEffect(version) { onFinish() }
        return
    }

    Column(
        Modifier.fillMaxSize().let { if (q.pictureOnly) it.background(kidBrush) else it }.padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (q.text.isNotEmpty()) Text(q.text, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        when (q.kind) {
            "choice" -> q.options.forEach { (id, label) ->
                OutlinedButton(onClick = { selected = id }, modifier = Modifier.fillMaxWidth(),
                    border = androidx.compose.foundation.BorderStroke(2.dp, if (selected == id) C.brand else Color.LightGray)) {
                    Text(label, fontSize = 17.sp)
                }
            }
            "text" -> OutlinedTextField(text, { text = it }, label = { Text("Név") }, modifier = Modifier.fillMaxWidth())
            "number" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedButton(onClick = { if (age > 1) age-- }) { Text("–", fontSize = 22.sp) }
                Text("$age éves", fontSize = 26.sp, fontWeight = FontWeight.Bold)
                OutlinedButton(onClick = { if (age < 17) age++ }) { Text("+", fontSize = 22.sp) }
            }
            "avatar" -> LazyVerticalGrid(GridCells.Fixed(3), Modifier.height(380.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                items(q.options.size) { i ->
                    val (id, emoji) = q.options[i]
                    Box(contentAlignment = Alignment.Center) { AvatarCircle(emoji, 80.dp, selected == id) { selected = id } }
                }
            }
        }
        error?.let { Text(it, color = C.danger) }
        Spacer(Modifier.weight(1f))
        Button(
            onClick = {
                val v = when (q.kind) { "text" -> text; "number" -> age.toString(); else -> selected ?: "" }
                try { flow.answer(v); version++ } catch (e: Exception) { error = "Kérlek, ellenőrizd a választ." }
            },
            enabled = !(q.kind == "choice" || q.kind == "avatar") || selected != null,
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) { Text(if (q.pictureOnly) "✔︎" else "Tovább", fontSize = 18.sp) }
    }
}

@Composable
fun OnboardingScreen(activity: MainActivity, store: AppStore) {
    var step by remember { mutableIntStateOf(0) }
    var name by remember { mutableStateOf("") }
    var flow by remember { mutableStateOf(OnboardingFlow()) }
    var electric by remember { mutableStateOf(false) }
    var goals by remember { mutableStateOf(Goals()) }

    when (step) {
        0 -> Column(Modifier.fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Spacer(Modifier.weight(1f))
            Text("🪥", fontSize = 70.sp)
            Text("Üdv!", fontSize = 32.sp, fontWeight = FontWeight.Bold)
            Text("Az app a hang alapján méri a fogmosásod idejét: a víz elzárásától az öblítésig. Hangfelvétel nem készül, minden a telefonodon marad.",
                textAlign = TextAlign.Center, color = C.muted)
            OutlinedTextField(name, { name = it }, label = { Text("Hogy szólíthatunk?") }, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.weight(1f))
            Button(onClick = { flow = OnboardingFlow(name.trim().ifEmpty { "Én" }); step = 1 }, Modifier.fillMaxWidth().height(52.dp)) { Text("Tovább") }
        }
        1 -> QuestionFlow(flow) { step = 2 }
        2 -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Milyen fogkefét használsz?", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(!electric, { electric = false }, SegmentedButtonDefaults.itemShape(0, 2)) { Text("Kézi") }
                SegmentedButton(electric, { electric = true }, SegmentedButtonDefaults.itemShape(1, 2)) { Text("Elektromos") }
            }
            Text(if (electric) "Elektromos fogkefénél a motor zúgását is figyeljük, és az első 3 fogmosásból megtanuljuk a fogkeféd hangját."
                 else "Kézi fogkefénél a súrolás ritmusát figyeljük. Más zúgását figyelmen kívül hagyjuk.", color = C.muted)
            Spacer(Modifier.weight(1f))
            Button(onClick = { step = 3 }, Modifier.fillMaxWidth().height(52.dp)) { Text("Tovább") }
        }
        3 -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Mi a célod?", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            Text("A fogorvosok naponta kétszer 2 percet javasolnak.", color = C.muted)
            Stepper("Naponta ${goals.perDay}×", { goals = goals.copy(perDay = goals.perDay - 1).clamped() }, { goals = goals.copy(perDay = goals.perDay + 1).clamped() })
            Stepper("Célidő: ${Formatting.clock(goals.targetS)}", { goals = goals.copy(targetS = goals.targetS - 15).clamped() }, { goals = goals.copy(targetS = goals.targetS + 15).clamped() })
            goals.warnings.forEach { Text(it, color = C.warn, fontSize = 13.sp) }
            Spacer(Modifier.weight(1f))
            Button(onClick = { step = 4 }, Modifier.fillMaxWidth().height(52.dp)) { Text("Tovább") }
        }
        else -> Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Text("Engedélyek", fontSize = 22.sp, fontWeight = FontWeight.Bold)
            InfoCard {
                Text("🎙️ Mikrofon és 🔔 értesítések", fontWeight = FontWeight.Bold)
                Text("A mikrofon a fogmosás felismeréséhez kell; a hang csak a telefonon, a memóriában dolgozódik fel. Az értesítések: reggel ébredés után és 15 perccel lefekvés előtt.",
                    color = C.muted, fontSize = 14.sp)
                OutlinedButton(onClick = { activity.requestPermissions() }) { Text("Engedélyezés") }
            }
            Spacer(Modifier.weight(1f))
            Button(onClick = {
                val ps = flow.profiles().toMutableList()
                ps[0] = ps[0].copy(brushType = if (electric) "electric" else "manual", goals = goals)
                store.update { it.copy(profiles = ps, activeProfileId = "me", onboarded = true) }
                ReminderScheduler.reschedule(activity)
                WearSync.pushGoals(activity, goals)
            }, Modifier.fillMaxWidth().height(52.dp)) { Text("Kezdjük!") }
        }
    }
}

@Composable
fun Stepper(label: String, minus: () -> Unit, plus: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 17.sp)
        OutlinedButton(onClick = minus) { Text("–") }
        Spacer(Modifier.size(8.dp))
        OutlinedButton(onClick = plus) { Text("+") }
    }
}

// ------------------------------------------------------------------ home

@Composable
fun HomeScreen(store: AppStore, onStart: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val rs = data.records(p.id)
    val today = LocalDate.now()
    val coach = store.coach
    Column(Modifier.fillMaxSize().background(C.bg).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        val h = java.time.LocalTime.now().hour
        val part = if (h < 10) "Jó reggelt" else if (h < 18) "Szia" else "Jó estét"
        Text(if (p.canRead) "$part, ${p.name}!" else p.avatarEmoji, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        if (data.profiles.size > 1) {
            Text("Ki mos most fogat?", color = C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                data.profiles.forEach { pr ->
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        AvatarCircle(pr.avatarEmoji, 56.dp, pr.id == p.id) { store.update { it.copy(activeProfileId = pr.id) } }
                        Text(if (pr.canRead) pr.name else " ", fontSize = 11.sp, color = C.muted)
                    }
                }
            }
        }
        BigButton("🪥  Fogmosás indítása", onStart)
        InfoCard {
            Row(Modifier.fillMaxWidth()) {
                Column(Modifier.weight(1f)) {
                    Text("Ma", color = C.muted)
                    Text("${coach.todayCount(rs, today)} / ${p.goals.perDay}", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                }
                if (data.settings.isOn("achievements")) Column(horizontalAlignment = Alignment.End) {
                    Text("Sorozat", color = C.muted)
                    Text("🔥 ${coach.perfectStreak(rs, p.goals, today)} nap", fontSize = 28.sp, fontWeight = FontWeight.Bold)
                }
            }
            if (p.canRead) Text(coach.dailySummary(rs, p.goals, today), fontSize = 12.sp, color = C.muted)
        }
        if (data.settings.isOn("habit_tips")) detectHabits(rs, p.goals, today, zone).firstOrNull()?.let { tip ->
            InfoCard { Text("Tipp", fontWeight = FontWeight.Bold); Text(tip.message, color = C.muted, fontSize = 14.sp) }
        }
        if (data.settings.isOn("brush_head_reminder")) {
            val st = brushHeadStatus(LocalDate.parse(p.brushHeadInstalled), p.electric, rs, today, zone)
            InfoCard {
                Text("🪥 ${if (p.electric) "Fogkefefej" else "Fogkefe"}: ${st.ageDays} napos" + if (st.due) " – csere!" else "")
                if (st.due || st.soon) Text(st.message, fontSize = 12.sp, color = C.muted)
            }
        }
        if (data.settings.isOn("floss_tracking")) {
            val done = extrasDoneToday(data.extras(p.id), "floss", today, zone)
            InfoCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (done) "🧵 Fogselyem: ma kipipálva ✔︎" else "🧵 Fogselyem: ma még nem volt", Modifier.weight(1f))
                    if (!done) TextButton(onClick = { store.addExtra("floss") }) { Text("Kész") }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ brushing + result

@Composable
fun BrushingScreen(activity: MainActivity, store: AppStore, onClose: () -> Unit) {
    val s by BrushingEngine.state.collectAsStateWithLifecycle()
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val r = s.result
    if (r != null && r.durationS >= 5) {
        ResultScreen(activity, store, r.durationS, r.waterRunningS, onClose)
        return
    }
    Column(
        Modifier.fillMaxSize().let { if (p.child) it.background(kidBrush) else it.background(Color.White) }.padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        when {
            s.phase == BrushingEngine.Phase.BRUSHING && s.wasteIcon && data.settings.isOn("water_warnings") -> Banner("🚰 Folyik a csap! Zárd el, amíg fogat mosol.", C.danger)
            s.phase == BrushingEngine.Phase.BRUSHING && s.manual -> Banner("⏱️ Kézi időzítő", C.brand)
            s.phase == BrushingEngine.Phase.BRUSHING -> Banner("✅ Fogmosás észlelve · a víz elzárásától mérve", C.ok)
            s.phase == BrushingEngine.Phase.RINSING -> Banner("💧 Öblítés…", C.brand)
            s.phase == BrushingEngine.Phase.WATER -> Banner("🚰 Víz", C.brand)
            s.armed -> Banner("🔔 Emlékeztetőből indítva: várom a fogmosást", C.brand)
        }
        when (s.phase) {
            BrushingEngine.Phase.BRUSHING, BrushingEngine.Phase.RINSING -> {
                val pr = brushProgress(s.elapsedS, p.goals.targetS)
                if (p.child) AvatarCircle(p.avatarEmoji, 70.dp)
                ProgressRing(pr.fraction, Formatting.clock(s.elapsedS), "cél: ${Formatting.clock(p.goals.targetS)}",
                    if (s.wasteIcon) C.warn else C.brand)
                if (p.canRead) Text("Most: ${pr.quadrantName} negyed", fontWeight = FontWeight.Bold)
                QuadrantGrid(pr.quadrant, p.canRead)
                val f0 = s.liveF0
                if (p.electric && f0 != null && p.canRead) Text("🔊 " + SonicDetector.describe(f0), fontSize = 13.sp, color = C.muted)
                if (s.wasteIcon && data.settings.isOn("water_warnings")) InfoCard {
                    Text("Eddig elfolyt", color = C.muted)
                    Text("≈ ${Formatting.hu(WaterReport(s.waterRunningS, data.settings.waterLocale).litres)} l", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = C.danger)
                }
            }
            BrushingEngine.Phase.FAILED -> {
                Text(s.error ?: "Hiba", textAlign = TextAlign.Center, color = C.muted)
                Button(onClick = { BrushingEngine.startManual(activity) }) { Text("Kézi indítás (időzítő)") }
            }
            else -> {
                Spacer(Modifier.weight(1f))
                Text(if (p.child) "🚰 → 🪥" else "🪥", fontSize = 64.sp)
                if (p.canRead) Text(when (s.phase) {
                    BrushingEngine.Phase.WATER -> "Folyik a víz… Nedvesítsd a fogkefét, majd zárd el a csapot."
                    BrushingEngine.Phase.ARMED -> "Várom a fogmosást…"
                    else -> if (s.placed) "Figyelek. A telefon maradhat letéve, a képernyő lezárása után is mérek."
                            else "Figyelek. Nedvesítsd a fogkefét, zárd el a csapot, és kezdheted."
                }, textAlign = TextAlign.Center, color = C.muted)
                s.stopNote?.let { Text("Leállt: $it", color = C.warn, fontSize = 13.sp) }
                if (r != null && r.durationS < 5) Text("Túl rövid volt, nem mentettem.", color = C.warn)
                if (s.active) OutlinedButton(onClick = { BrushingEngine.startManual(activity) }) { Text("Kézi indítás (időzítő)") }
            }
        }
        Spacer(Modifier.weight(1f))
        if (s.active) OutlinedButton(onClick = { BrushingEngine.stop() }, Modifier.fillMaxWidth().height(52.dp)) { Text("Kész", fontSize = 18.sp) }
        else Button(onClick = onClose, Modifier.fillMaxWidth().height(52.dp)) { Text("Bezárás") }
    }
}

@Composable
fun ResultScreen(activity: MainActivity, store: AppStore, durationS: Double, waterS: Double, onClose: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val fb = remember(durationS) { feedbackFor(p, durationS, store.coach) }
    val speak = fb.speak && data.settings.isOn("spoken_feedback")
    LaunchedEffect(durationS) { if (speak) activity.speaker.say(fb.text) }
    val achievements = activity.newAchievements.value
    Column(
        Modifier.fillMaxSize().let { if (p.child) it.background(kidBrush) else it.background(C.bg) }.verticalScroll(rememberScrollState()).padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        if (p.child) {
            AvatarCircle(p.avatarEmoji, 110.dp)
            Text(fb.icons, fontSize = 44.sp)
            val (st, figs) = stickers(data.records(p.id), p.goals, zone)
            InfoCard {
                Text("🟡".repeat(st % 7) + "⚪".repeat(7 - st % 7), fontSize = 24.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                if (p.canRead) Text("Figurák: $figs", fontSize = 12.sp, modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
            }
            if (p.canRead) Text(fb.text, textAlign = TextAlign.Center) else TextButton(onClick = { activity.speaker.say(fb.text) }) { Text("🔊", fontSize = 40.sp) }
        } else {
            Text(if (durationS >= p.goals.targetS) "🎉" else "💪", fontSize = 54.sp)
            Text(Formatting.clock(durationS), fontSize = 36.sp, fontWeight = FontWeight.Bold)
            Text(fb.text, textAlign = TextAlign.Center, color = C.muted)
        }
        if (data.settings.isOn("water_warnings") && p.canRead) {
            val m = waterMessage(durationS, waterS, data.settings.waterLocale)
            InfoCard {
                Text(m.title, fontWeight = FontWeight.Bold, color = if (m.wasted) C.danger else C.ok)
                m.lines.forEach { Text(it, fontSize = 14.sp, color = C.muted) }
            }
        }
        if (data.settings.isOn("achievements")) achievements.forEach { id ->
            InfoCard {
                Text("🏅 Új kitüntetés: ${achievementTitle(id, p)}", fontWeight = FontWeight.Bold)
                if (p.canRead) Text(Achievements.byId(id)?.description ?: "", fontSize = 14.sp, color = C.muted)
            }
        }
        val today = LocalDate.now()
        if (data.settings.isOn("floss_tracking") || data.settings.isOn("mouthwash_tracking")) InfoCard {
            Text("Kiegészítők ma", fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for ((kind, label) in listOf("floss" to "🧵 Fogselyem", "mouthwash" to "🫧 Szájvíz")) {
                    if (!data.settings.isOn(if (kind == "floss") "floss_tracking" else "mouthwash_tracking")) continue
                    val done = extrasDoneToday(data.extras(p.id), kind, today, zone)
                    OutlinedButton(onClick = { store.addExtra(kind) }, enabled = !done) { Text(if (done) "$label ✔︎" else label) }
                }
            }
        }
        Button(onClick = onClose, Modifier.fillMaxWidth().height(52.dp)) { Text("Kész") }
    }
}

// ------------------------------------------------------------------ stats, achievements

@Composable
fun StatsScreen(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val rs = data.records(p.id)
    val today = LocalDate.now()
    val fmt = DateTimeFormatter.ofPattern("MM.dd. HH:mm")
    LazyColumn(Modifier.fillMaxSize().background(C.bg).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Text("Statisztika", fontSize = 28.sp, fontWeight = FontWeight.Bold) }
        item {
            InfoCard {
                Text(store.coach.weeklyProgress(rs, p.goals, today), fontSize = 14.sp)
                Row(Modifier.fillMaxWidth().height(110.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (i in 6 downTo 0) {
                        val d = today.minusDays(i.toLong())
                        val day = rs.filter { store.coach.day(it) == d }
                        val avg = if (day.isEmpty()) 0.0 else day.map { it.durationS }.average()
                        Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                            val hgt = (80 * (avg / maxOf(p.goals.targetS * 1.2, 1.0))).coerceIn(4.0, 90.0)
                            Box(Modifier.fillMaxWidth().height(hgt.dp).clip(RoundedCornerShape(6.dp))
                                .background(if (avg >= p.goals.targetS) C.brand else if (avg > 0) C.warn else C.track))
                            Text(d.dayOfWeek.getDisplayName(java.time.format.TextStyle.NARROW, java.util.Locale("hu")), fontSize = 10.sp, color = C.muted)
                        }
                    }
                }
            }
        }
        if (data.settings.isOn("monthly_report")) item {
            val text = monthlyReportText(rs, p.goals, today.year, today.monthValue, data.settings.waterLocale, zone, p.name)
            InfoCard {
                Text("Havi összefoglaló", fontWeight = FontWeight.Bold)
                Text(text, fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { share(activity, text) }) { Text("Megosztás") }
                    OutlinedButton(onClick = { share(activity, recordsCsv(rs)) }) { Text("CSV") }
                }
            }
        }
        item { Text("Legutóbbiak", fontWeight = FontWeight.Bold) }
        if (rs.isEmpty()) item { Text("Még nincs mért fogmosás.", color = C.muted) }
        items(rs.sortedByDescending { it.startMs }.take(30)) { r ->
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White).padding(12.dp)) {
                Text(Instant.ofEpochMilli(r.startMs).atZone(zone).format(fmt), Modifier.weight(1f))
                if (!r.tapOff) Text("🚰 ")
                if (r.source == "watch") Text("⌚ ")
                Text(Formatting.clock(r.durationS), color = if (r.durationS >= p.goals.targetS) C.ok else C.warn, fontWeight = FontWeight.Bold)
            }
        }
    }
}

private fun share(activity: MainActivity, text: String) {
    val i = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    activity.startActivity(Intent.createChooser(i, "Megosztás"))
}

@Composable
fun AchievementsScreen(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val rs = data.records(p.id)
    val earned = store.coach.earnedAchievements(rs, p.goals, LocalDate.now())
    LazyColumn(Modifier.fillMaxSize().background(C.bg).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item { Text("Kitüntetések", fontSize = 28.sp, fontWeight = FontWeight.Bold) }
        if (p.child) item {
            val (st, figs) = stickers(rs, p.goals, zone)
            InfoCard { Text("🟡 $st matrica · 🦖 $figs figura", fontWeight = FontWeight.Bold); Text("Minden tökéletes nap egy matrica, 7 matrica egy figura.", fontSize = 12.sp, color = C.muted) }
        }
        items(Achievements.all) { a ->
            val on = a.id in earned
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Color.White).padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (on) "🏅" else "🔒", fontSize = 26.sp)
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(achievementTitle(a.id, p), fontWeight = FontWeight.Bold, color = if (on) Color.Black else Color.Gray)
                    Text(a.description, fontSize = 12.sp, color = C.muted)
                }
            }
        }
    }
}
