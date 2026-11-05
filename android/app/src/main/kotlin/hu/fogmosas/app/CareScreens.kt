package hu.fogmosas.app

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.CareEntry
import hu.fogmosas.core.I18n
import hu.fogmosas.core.tr
import hu.fogmosas.core.CareKind
import hu.fogmosas.core.Formatting
import hu.fogmosas.core.Orthodontic
import hu.fogmosas.core.Profile
import hu.fogmosas.core.Toothpastes
import hu.fogmosas.core.WebLink
import hu.fogmosas.core.careCount
import hu.fogmosas.core.careDoneToday
import hu.fogmosas.core.careInsights
import hu.fogmosas.core.careStreak
import hu.fogmosas.core.dentistReport
import hu.fogmosas.core.dentistStatus
import hu.fogmosas.core.rewardProgress
import hu.fogmosas.core.stickers
import hu.fogmosas.shared.AppData
import hu.fogmosas.shared.AppStore
import kotlinx.coroutines.launch
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

private val careZone: ZoneId get() = ZoneId.systemDefault()

private fun AppData.extrasFor(p: Profile) = listOfNotNull(
    if (settings.isOn("floss_tracking") || p.orthodontic) CareKind.FLOSS else null,
    if (settings.isOn("interdental_tracking") || p.orthodontic) CareKind.INTERDENTAL else null,
    if (settings.isOn("mouthwash_tracking")) CareKind.MOUTHWASH else null,
    if (settings.isOn("tongue_tracking")) CareKind.TONGUE else null,
)

private val CareKind.icon get() = when (this) {
    CareKind.FLOSS -> "🧵"; CareKind.MOUTHWASH -> "🫧"; CareKind.INTERDENTAL -> "🪥"; CareKind.TONGUE -> "👅"
    CareKind.SENSITIVITY -> "⚡"; CareKind.BLEEDING -> "🩸"
}

// ------------------------------------------------------------------ check-in after brushing

/** "Hogy érezted?" card on the result screen: symptoms, extras and toothpaste in one save. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun CareCheckIn(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val s = data.settings
    val extras = data.extrasFor(p)
    val symptoms = s.isOn("care_checkin")
    val paste = s.isOn("toothpaste_tracking")
    if (!symptoms && extras.isEmpty() && !paste) return
    var saved by remember { mutableStateOf(false) }
    var sens by remember { mutableIntStateOf(0) }
    var bleed by remember { mutableStateOf(false) }
    val ticked = remember { mutableStateOf(setOf<CareKind>()) }
    var tp by remember { mutableStateOf(p.toothpaste) }
    val pictures = !p.canRead

    InfoCard {
        if (saved) {
            Text(if (pictures) "✔︎ 👍" else tr("Elmentve a naplóba ✔︎"), fontWeight = FontWeight.Bold, color = C.ok)
        }
        if (!saved && symptoms) {
            Text(if (pictures) "🦷 ?" else tr("Hogy érezted a fogmosást?"), fontWeight = FontWeight.Bold)
            if (!pictures) Text(tr("Érzékeny volt a fogad?"), fontSize = 13.sp, color = C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("😀" to tr("Nem"), "😐" to tr("Kicsit"), "😣" to tr("Nagyon")).forEachIndexed { i, (emoji, label) ->
                    FilterChip(selected = sens == i, onClick = { sens = i }, label = { Text(if (pictures) emoji else "$emoji $label", fontSize = if (pictures) 26.sp else 14.sp) },
                        modifier = Modifier.semantics { contentDescription = tr("Érzékenység: {0}", label) })
                }
            }
            FilterChip(selected = bleed, onClick = { bleed = !bleed }, label = { Text(if (pictures) "🩸" else tr("🩸 Vérzett az ínyem"), fontSize = if (pictures) 26.sp else 14.sp) },
                modifier = Modifier.semantics { contentDescription = tr("Vérzett az ínyem") })
        }
        if (!saved && extras.isNotEmpty()) {
            if (!pictures) Text(tr("Ma ezt is csináltam:"), fontSize = 13.sp, color = C.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                extras.forEach { k ->
                    val on = k in ticked.value
                    FilterChip(selected = on, onClick = { ticked.value = if (on) ticked.value - k else ticked.value + k },
                        label = { Text(if (pictures) k.icon else "${k.icon} ${k.label}", fontSize = if (pictures) 26.sp else 14.sp) },
                        modifier = Modifier.semantics { contentDescription = k.label })
                }
            }
        }
        if (!saved && paste && !pictures) {
            Text(tr("Fogkrém: {0}", Toothpastes.title(tp)), fontSize = 13.sp, color = C.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Toothpastes.all.forEach { k -> FilterChip(selected = tp == k.id, onClick = { tp = k.id }, label = { Text(k.title, fontSize = 12.sp) }) }
            }
        }
        if (!saved) Button(onClick = {
            val t = ticked.value
            store.addCare(CareEntry(profileId = p.id, dateMs = System.currentTimeMillis(), sensitivity = sens, bleeding = bleed,
                floss = CareKind.FLOSS in t, mouthwash = CareKind.MOUTHWASH in t, interdental = CareKind.INTERDENTAL in t,
                tongue = CareKind.TONGUE in t, toothpaste = if (paste) tp else null))
            if (paste && tp != p.toothpaste) store.updateProfile(p.copy(toothpaste = tp))
            saved = true
        }) { Text(if (pictures) "✔︎" else tr("Mentés a naplóba")) }
    }
}

// ------------------------------------------------------------------ home cards

@Composable
fun RewardCard(store: AppStore, p: Profile) {
    val data by store.data.collectAsStateWithLifecycle()
    if (!data.settings.isOn("kid_rewards")) return
    val r = rewardProgress(data.records(p.id), p.goals, p.reward, p.rewardStickers, p.rewardSinceMs, careZone) ?: return
    InfoCard {
        Text(if (r.done) tr("🎁 {0} – megvan!", r.text) else "🎁 ${r.text}", fontWeight = FontWeight.Bold)
        LinearProgressIndicator(progress = { r.fraction.toFloat() }, modifier = Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(5.dp)), color = C.brand2, trackColor = C.track)
        Text(if (p.canRead) tr("{0} / {1} matrica", r.have, r.need) else "🟡".repeat(minOf(r.have, 14)), fontSize = 13.sp, color = C.muted)
    }
}

// ------------------------------------------------------------------ statistics

@Composable
fun CareStatsCards(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val es = data.care(p.id)
    val today = LocalDate.now()
    val extras = data.extrasFor(p)
    val ctx = LocalContext.current

    if (extras.isNotEmpty() || data.settings.isOn("care_checkin")) InfoCard {
        Text(tr("Fogápolás"), fontWeight = FontWeight.Bold)
        extras.forEach { k ->
            val streak = careStreak(es, k, today, careZone)
            Row {
                Text("${k.icon} ${k.label}", Modifier.weight(1f))
                Text(tr("{0}/7 · {1}/30 nap", careCount(es, k, today, 7, careZone), careCount(es, k, today, 30, careZone)) + if (streak > 1) " · 🔥$streak" else "", fontSize = 13.sp, color = C.muted)
            }
        }
        if (data.settings.isOn("care_checkin")) {
            for (k in listOf(CareKind.SENSITIVITY, CareKind.BLEEDING)) Row {
                Text("${k.icon} ${k.label}", Modifier.weight(1f))
                Text(tr("{0} nap / 2 hét · {1} / 30", careCount(es, k, today, 14, careZone), careCount(es, k, today, 30, careZone)), fontSize = 13.sp, color = C.muted)
            }
        }
        if (p.orthodontic) Text("🦷 ${Orthodontic.NOTE}", fontSize = 12.sp, color = C.muted)
        careInsights(es, today, careZone, data.settings.isOn("floss_tracking") || p.orthodontic).forEach { ins ->
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background((if (ins.alert) C.danger else C.brand).copy(alpha = 0.1f)).padding(10.dp)) {
                Text(ins.text, fontSize = 13.sp, color = if (ins.alert) C.danger else androidx.compose.ui.graphics.Color.Black)
            }
        }
    }

    if (data.settings.isOn("dentist_report")) InfoCard {
        Text(tr("Jelentés a fogorvosnak"), fontWeight = FontWeight.Bold)
        Text(tr("Fogmosás, fogköztisztítás, tünetek és fogkrém egy kinyomtatható PDF-ben."), fontSize = 13.sp, color = C.muted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (days in listOf(30, 90)) OutlinedButton(onClick = {
                val rep = dentistReport(p, data.records(p.id), es, today, days, careZone, data.settings.waterLocale, data.symptoms)
                ReportPdf.share(ctx, ReportPdf.write(ctx, rep))
            }) { Text(tr("PDF ({0} nap)", days)) }
        }
    }

    if (data.settings.isOn("family_overview") && !p.child && data.profiles.any { it.child }) InfoCard {
        Text(tr("Család"), fontWeight = FontWeight.Bold)
        data.profiles.filter { it.child }.forEach { k ->
            val rs = data.records(k.id)
            val (st, _) = stickers(rs, k.goals, careZone)
            Row(verticalAlignment = Alignment.CenterVertically) {
                AvatarCircle(k.avatarEmoji, 40.dp)
                Spacer(Modifier.size(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(k.name, fontWeight = FontWeight.SemiBold)
                    Text(tr("Ma {0}/{1} · 🔥 {2} nap · 🟡 {3} matrica", store.coach.todayCount(rs, today), k.goals.perDay, store.coach.perfectStreak(rs, k.goals, today), st) +
                        (if (careDoneToday(data.care(k.id), CareKind.FLOSS, today, careZone)) " · 🧵" else ""), fontSize = 12.sp, color = C.muted)
                    rewardProgress(rs, k.goals, k.reward, k.rewardStickers, k.rewardSinceMs, careZone)?.let {
                        Text("🎁 ${it.text}: ${it.have}/${it.need}", fontSize = 12.sp, color = C.muted)
                    }
                }
            }
        }
    }

    if (data.settings.isOn("web_link", "android")) WebLinkCard(activity, store)
}

@Composable
private fun WebLinkCard(activity: MainActivity, store: AppStore) {
    val scope = rememberCoroutineScope()
    var pairing by remember { mutableStateOf<WebLink.Pairing?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    InfoCard {
        Text(tr("Megnézem a weben"), fontWeight = FontWeight.Bold)
        Text(tr("Nyisd meg a DentHub-Brush weboldalát a számítógépen, és olvasd be az ott látható QR-kódot. Az adatok titkosítva mennek át, a szerver nem tárolja őket."), fontSize = 13.sp, color = C.muted)
        Button(onClick = {
            status = null
            WebShare.scan(activity) { text ->
                if (text == null) return@scan
                val pr = WebLink.parse(text)
                if (pr == null) status = tr("Ez nem a DentHub-Brush weboldal QR-kódja.") else pairing = pr
            }
        }) { Text(tr("📷 QR-kód beolvasása")) }
        status?.let { Text(it, fontSize = 13.sp, color = if (it.startsWith("✔")) C.ok else C.danger) }
    }
    pairing?.let { pr ->
        val d = store.data.value
        val who = if (d.activeProfile.child) d.activeProfile.name else d.profiles.joinToString(", ") { it.name }
        AlertDialog(
            onDismissRequest = { pairing = null },
            title = { Text(tr("Megosztod a weboldallal?")) },
            text = { Text(tr("Webcím: {0}\nProfilok: {1}\n\nCsak akkor folytasd, ha ezt a címet te nyitottad meg a saját számítógépeden.", pr.host, who)) },
            confirmButton = { TextButton(onClick = {
                pairing = null
                DeviceAuth.authenticate(activity, tr("Megosztás a weboldallal"), pr.host) { ok ->
                    if (!ok) return@authenticate
                    scope.launch {
                        val err = WebShare.send(pr, WebShare.snapshotJson(store.data.value))
                        status = err ?: tr("✔︎ Elküldve, nézd meg a böngészőben.")
                        if (err == null) store.update { it.copy(denthubLinkedMs = System.currentTimeMillis(), denthubHost = pr.host) }
                    }
                }
            }) { Text(tr("Megosztás")) } },
            dismissButton = { TextButton(onClick = { pairing = null }) { Text(tr("Mégse")) } },
        )
    }
}

// ------------------------------------------------------------------ settings

@Composable
fun ProfileCareSettings(store: AppStore, p: Profile, onGoalsChanged: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    SwitchRow(tr("Fogszabályzó"), tr("Hosszabb célidő ({0}), fogköztisztítás a naplóban.", Formatting.clock(Orthodontic.TARGET_S)), p.orthodontic) { on ->
        val g = if (on && p.goals.targetS < Orthodontic.TARGET_S) p.goals.copy(targetS = Orthodontic.TARGET_S) else p.goals
        store.updateProfile(p.copy(orthodontic = on, goals = g))
        onGoalsChanged()
    }
    if (data.settings.isOn("dentist_reminders")) {
        Text(tr("Utolsó kontroll: {0} · fogkőeltávolítás: {1}", p.lastCheckup?.let { I18n.date(LocalDate.parse(it)) } ?: "—", p.lastCleaning?.let { I18n.date(LocalDate.parse(it)) } ?: "—"), fontSize = 13.sp, color = C.muted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { store.updateProfile(p.copy(lastCheckup = LocalDate.now().toString())) }) { Text(tr("Ma kontroll")) }
            OutlinedButton(onClick = { store.updateProfile(p.copy(lastCleaning = LocalDate.now().toString())) }) { Text(tr("Ma fogkő")) }
        }
    }
    if (p.child && data.settings.isOn("kid_rewards")) {
        var text by remember(p.id) { mutableStateOf(p.reward ?: "") }
        OutlinedTextField(value = text, onValueChange = { text = it }, label = { Text(tr("Jutalom (pl. mozi, fagyi)")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Stepper(tr("Ennyi matricáért: {0}", p.rewardStickers), { store.updateProfile(p.copy(rewardStickers = maxOf(3, p.rewardStickers - 1))) },
            { store.updateProfile(p.copy(rewardStickers = minOf(60, p.rewardStickers + 1))) })
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { store.updateProfile(p.copy(reward = text.trim().ifEmpty { null }, rewardSinceMs = System.currentTimeMillis())) }) { Text(tr("Jutalom indítása")) }
            if (p.reward != null) TextButton(onClick = { text = ""; store.updateProfile(p.copy(reward = null, rewardSinceMs = null)) }) { Text(tr("Törlés")) }
        }
        Text(tr("A matricákat a jutalom indításától számoljuk (egy matrica = egy nap, amikor a napi cél teljesült)."), fontSize = 12.sp, color = C.muted)
    }
}

// ------------------------------------------------------------------ DentHub link reminder

/** Until the app has been linked to the DentHub website, remind on every start where the results live. */
@Composable
fun LinkReminderBanner(activity: MainActivity, store: AppStore, onLink: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    if (data.denthubLinkedMs != null || !activity.linkReminder.value || !data.activeProfile.canRead) return
    Box(Modifier.background(C.bg).padding(start = 16.dp, end = 16.dp, top = 12.dp)) {
        InfoCard {
            Text(tr("⚠️ Még nincs összekötve a DentHubbal"), fontWeight = FontWeight.Bold, color = C.warn)
            Text(tr("Regisztráció nélkül is használhatod, de az eredményeid most csak ezen a telefonon vannak. A DentHub oldalán akkor jelennek meg, ha összekötöd: nyisd meg a DentHub-Brush weboldalt, és olvasd be a QR-kódot."),
                fontSize = 13.sp, color = C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = {
                    if (!store.data.value.settings.isOn("web_link", "android")) store.update { it.copy(settings = it.settings.with("web_link", true)) }
                    onLink()
                }) { Text(tr("Összekötés")) }
                TextButton(onClick = { activity.linkReminder.value = false }) { Text(tr("Később")) }
            }
        }
    }
}

// ------------------------------------------------------------------ watch placement

/** "Melyik kézzel mosol fogat?" and "Melyik kezeden hordod az órát?" (Wear OS cannot tell its wrist). */
@Composable
fun HandSettings(store: AppStore, p: Profile, onChanged: () -> Unit) {
    if (p.child) return
    val hands = listOf("left" to tr("Bal"), "right" to tr("Jobb"))
    Text(tr("Melyik kézzel mosol fogat?"), fontSize = 13.sp, color = C.muted)
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        hands.forEach { (id, label) -> FilterChip(selected = p.brushHand == id, onClick = { store.updateProfile(p.copy(brushHand = id)); onChanged() }, label = { Text(label) }) }
    }
    Text(tr("Melyik kezeden hordod az órát?"), fontSize = 13.sp, color = C.muted)
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        hands.forEach { (id, label) -> FilterChip(selected = p.watchWrist == id, onClick = { store.updateProfile(p.copy(watchWrist = id)); onChanged() }, label = { Text(label) }) }
    }
    Text(hu.fogmosas.core.watchListening(p.brushHand, p.watchWrist).distanceText, fontSize = 12.sp, color = C.muted)
}

// ------------------------------------------------------------------ lock

@Composable
fun LockScreen(title: String, onUnlock: () -> Unit) {
    Column(Modifier.fillMaxSize().background(C.bg).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text("🔒", fontSize = 64.sp)
        Text(title, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Button(onClick = onUnlock) { Text(tr("Feloldás")) }
    }
}

fun toast(ctx: android.content.Context, text: String) = Toast.makeText(ctx, text, Toast.LENGTH_SHORT).show()

// ------------------------------------------------------------------ measurement feedback

/** After a brushing: why it stopped, "Még mostam – folytatás", and "Pontos volt a mérés?". */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun MeasurementFeedbackCard(activity: MainActivity, store: AppStore, onResume: () -> Unit) {
    val r = hu.fogmosas.shared.BrushingEngine.state.collectAsStateWithLifecycle().value.result ?: return
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!p.canRead) return
    var answer by remember(r) { mutableStateOf<Boolean?>(null) }
    var reason by remember(r) { mutableStateOf<String?>(null) }
    var note by remember(r) { mutableStateOf("") }
    var saved by remember(r) { mutableStateOf<hu.fogmosas.core.FeedbackEntry?>(null) }
    val ctx = LocalContext.current
    val testing = data.settings.isOn("test_recording", "android")
    // Test mode: the remark is saved next to the recording as it is typed, even if never sent.
    if (testing) LaunchedEffect(answer, reason, note) {
        if (answer == null && note.isBlank()) return@LaunchedEffect
        kotlinx.coroutines.delay(500)
        val base = hu.fogmosas.shared.BrushingEngine.lastRecordingBase ?: return@LaunchedEffect
        val text = remarkText(answer, reason, note, r)
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            runCatching { hu.fogmosas.core.TestRecording.saveRemark(hu.fogmosas.shared.BrushingEngine.recordingsDir(ctx), base, text) }
        }
    }

    InfoCard {
        if (!r.manual) Text(hu.fogmosas.core.endReasonText(r.endReason), fontSize = 13.sp, color = C.muted)
        r.notes.forEach { Text(it, fontSize = 13.sp, color = C.warn) }
        r.scrubNote?.let { Text(it, fontSize = 13.sp, color = C.warn) }
        r.timerNote?.let { Text(it, fontSize = 13.sp, color = C.muted) }
        val log = hu.fogmosas.shared.BrushingEngine.state.collectAsStateWithLifecycle().value.testLog
        if (log.isNotEmpty()) {
            Text(tr("Mit észlel az app"), fontWeight = FontWeight.Bold)
            log.forEach { Text(it, fontSize = 12.sp, color = C.muted) }
        }
        if (testing) {
            if (answer != null || note.isNotBlank()) Text(tr("✓ Az észrevételt a felvétel mellé mentettem."), fontSize = 12.sp, color = C.ok)
            TestRecordingShareButton(saved?.let { s -> hu.fogmosas.core.feedbackReport(s, "android", "", p.quietExtraS) } ?: "")
        }
        if (!r.manual && r.endReason != "user" && r.durationS < p.goals.targetS) {
            OutlinedButton(onClick = {
                activity.lastRecordId?.let { store.removeRecord(it) }
                activity.lastRecordId = null
                onResume()
            }) { Text(tr("↩️ Még mostam – folytatás")) }
        }
        val s = saved
        if (s != null) {
            Text(tr("Köszönjük a visszajelzést!"), fontWeight = FontWeight.Bold, color = C.ok)
            if (!s.ok) {
                Text(tr("A következő méréseknél figyelembe veszem. A fejlesztőknek is elküldheted, hogy javíthassuk a felismerést."), fontSize = 13.sp, color = C.muted)
                OutlinedButton(onClick = {
                    val prof = store.data.value.profile(s.profileId)
                    val text = hu.fogmosas.core.feedbackReport(s, "android", ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "", prof?.quietExtraS ?: 0.0)
                    val i = android.content.Intent(android.content.Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(android.content.Intent.EXTRA_SUBJECT, "DentHub-Brush feedback").putExtra(android.content.Intent.EXTRA_TEXT, text)
                    ctx.startActivity(android.content.Intent.createChooser(i, tr("Visszajelzés küldése")))
                }) { Text(tr("Küldés a fejlesztőknek")) }
            }
        } else {
            Text(tr("Pontos volt a mérés?"), fontWeight = FontWeight.Bold)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(selected = answer == true, onClick = { answer = true }, label = { Text(tr("👍 Igen")) })
                FilterChip(selected = answer == false, onClick = { answer = false }, label = { Text(tr("👎 Nem")) })
            }
            if (answer == false) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    hu.fogmosas.core.FeedbackReasons.all.forEach { rs ->
                        FilterChip(selected = reason == rs.id, onClick = { reason = rs.id }, label = { Text(rs.title, fontSize = 13.sp) })
                    }
                }
                OutlinedTextField(value = note, onValueChange = { note = it }, label = { Text(tr("Mi történt? (nem kötelező)")) }, modifier = Modifier.fillMaxWidth())
            }
            // Test mode: a remark field even when the measurement was right.
            if (testing && answer != false) OutlinedTextField(value = note, onValueChange = { note = it },
                label = { Text(tr("Észrevétel a felvételhez")) }, modifier = Modifier.fillMaxWidth())
            if (answer != null) Button(onClick = {
                val e = hu.fogmosas.core.FeedbackEntry(dateMs = System.currentTimeMillis(), profileId = p.id, ok = answer == true,
                    reason = if (answer == true) null else reason, note = note.trim(), durationS = r.durationS, endReason = r.endReason,
                    cue = r.cue, waterRunningS = r.waterRunningS, brushType = p.brushType, targetS = p.goals.targetS)
                store.addFeedback(e)
                saved = e
            }, enabled = answer == true || reason != null) { Text(tr("Mentés")) }
        }
    }
}

// ------------------------------------------------------------------ test recordings

/** The tester's remark as saved next to the recording. */
private fun remarkText(answer: Boolean?, reason: String?, note: String, r: hu.fogmosas.shared.BrushingEngine.Result) = buildString {
    appendLine("saved: " + java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US).format(java.util.Date()))
    appendLine("accurate: " + when (answer) { true -> "yes"; false -> "no"; null -> "-" })
    reason?.let { appendLine("reason: $it") }
    appendLine("measuredS: ${Math.round(r.durationS)}  endReason: ${r.endReason}  cue: ${r.cue}")
    (r.notes + listOfNotNull(r.scrubNote, r.timerNote)).forEach { appendLine("appNote: $it") }
    appendLine()
    append(note.trim())
}

/** "📦 Összes felvétel beküldése": every recording and remark in one ZIP through the share sheet (Drive, e-mail …). */
@Composable
fun TestRecordingsSendAllButton() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    val dir = hu.fogmosas.shared.BrushingEngine.recordingsDir(ctx)
    val count = remember(busy) { hu.fogmosas.core.TestRecording.bases(dir).size }
    OutlinedButton(enabled = !busy && count > 0, onClick = {
        busy = true
        scope.launch {
            val zip = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                File(ctx.cacheDir, "reports").listFiles { f -> f.name.endsWith(".zip") }?.forEach { it.delete() }
                val name = "denthub-brush-tests-" + java.text.SimpleDateFormat("yyyyMMdd-HHmm", java.util.Locale.US).format(java.util.Date()) + ".zip"
                runCatching { hu.fogmosas.core.TestRecording.zipAll(dir, File(File(ctx.cacheDir, "reports"), name)) }.getOrNull()
            }
            busy = false
            if (zip == null) { toast(ctx, tr("Még nincs tesztfelvétel.")); return@launch }
            val uri = androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".files", zip)
            val i = android.content.Intent(android.content.Intent.ACTION_SEND).setType("application/zip")
                .putExtra(android.content.Intent.EXTRA_STREAM, uri)
                .putExtra(android.content.Intent.EXTRA_SUBJECT, zip.nameWithoutExtension)
                .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
            ctx.startActivity(android.content.Intent.createChooser(i, tr("Felvételek beküldése (pl. Google Drive)")))
        }
    }) { Text(if (busy) tr("Csomagolás…") else tr("📦 Összes felvétel beküldése ({0})", count)) }
}

/** "📤 Tesztfelvétel küldése": shares the newest recording (WAV + JSON timeline) through the share sheet. */
@Composable
fun TestRecordingShareButton(note: String = "") {
    val ctx = LocalContext.current
    val dir = hu.fogmosas.shared.BrushingEngine.recordingsDir(ctx)
    OutlinedButton(onClick = {
        val files = hu.fogmosas.core.TestRecording.latest(dir)
        if (files.isEmpty()) { toast(ctx, tr("Még nincs tesztfelvétel.")); return@OutlinedButton }
        val uris = ArrayList(files.map { androidx.core.content.FileProvider.getUriForFile(ctx, ctx.packageName + ".files", it) })
        val i = android.content.Intent(android.content.Intent.ACTION_SEND_MULTIPLE).setType("*/*")
            .putParcelableArrayListExtra(android.content.Intent.EXTRA_STREAM, uris)
            .putExtra(android.content.Intent.EXTRA_SUBJECT, "DentHub-Brush " + files.last().nameWithoutExtension)
            .putExtra(android.content.Intent.EXTRA_TEXT, note.ifBlank { files.last().name })
            .addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(android.content.Intent.createChooser(i, tr("Tesztfelvétel küldése")))
    }) { Text(tr("📤 Tesztfelvétel küldése")) }
}
