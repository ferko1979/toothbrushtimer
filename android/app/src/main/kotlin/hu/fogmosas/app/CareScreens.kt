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
                    FilterChip(selected = sens == i, onClick = { sens = i }, label = { Text(if (pictures) emoji else "$emoji $label", fontSize = if (pictures) 26.sp else 14.sp) })
                }
            }
            FilterChip(selected = bleed, onClick = { bleed = !bleed }, label = { Text(if (pictures) "🩸" else tr("🩸 Vérzett az ínyem"), fontSize = if (pictures) 26.sp else 14.sp) })
        }
        if (!saved && extras.isNotEmpty()) {
            if (!pictures) Text(tr("Ma ezt is csináltam:"), fontSize = 13.sp, color = C.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                extras.forEach { k ->
                    val on = k in ticked.value
                    FilterChip(selected = on, onClick = { ticked.value = if (on) ticked.value - k else ticked.value + k },
                        label = { Text(if (pictures) k.icon else "${k.icon} ${k.label}", fontSize = if (pictures) 26.sp else 14.sp) })
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
fun DentistHomeCard(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!data.settings.isOn("dentist_reminders") || !p.canRead) return
    val st = dentistStatus(p.lastCheckup?.let(LocalDate::parse), p.lastCleaning?.let(LocalDate::parse), LocalDate.now())
    val msg = st.message ?: if (p.lastCheckup == null) tr("Mikor voltál utoljára fogorvosnál? Add meg, és szólok, ha esedékes a kontroll.") else null
    if (msg == null) return
    InfoCard {
        Text(tr("🦷 Fogorvos"), fontWeight = FontWeight.Bold)
        Text(msg, fontSize = 13.sp, color = C.muted)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { store.updateProfile(p.copy(lastCheckup = LocalDate.now().toString())) }) { Text(tr("Ma voltam kontrollon")) }
            if (st.cleaningOverdue || p.lastCleaning == null) TextButton(onClick = { store.updateProfile(p.copy(lastCleaning = LocalDate.now().toString())) }) { Text(tr("Fogkő is")) }
        }
    }
}

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
                val rep = dentistReport(p, data.records(p.id), es, today, days, careZone, data.settings.waterLocale)
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
        Text(tr("Nyisd meg a Fogmosás weboldalát a számítógépen, és olvasd be az ott látható QR-kódot. Az adatok titkosítva mennek át, a szerver nem tárolja őket."), fontSize = 13.sp, color = C.muted)
        Button(onClick = {
            status = null
            WebShare.scan(activity) { text ->
                if (text == null) return@scan
                val pr = WebLink.parse(text)
                if (pr == null) status = tr("Ez nem a Fogmosás weboldal QR-kódja.") else pairing = pr
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
