package hu.fogmosas.app

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import hu.fogmosas.core.CareEntry
import hu.fogmosas.core.ClinicInfo
import hu.fogmosas.core.ClinicMessage
import hu.fogmosas.core.DentistIntake
import hu.fogmosas.core.SymptomFlow
import hu.fogmosas.core.SymptomReport
import hu.fogmosas.core.Symptoms
import hu.fogmosas.core.TriageLevel
import hu.fogmosas.core.VisitReasons
import hu.fogmosas.core.VisitRequest
import hu.fogmosas.core.bookingLink
import hu.fogmosas.core.clinicEmail
import hu.fogmosas.core.dentistStatus
import hu.fogmosas.core.parseClinicLink
import hu.fogmosas.core.recentSymptomCount
import hu.fogmosas.core.symptomSummary
import hu.fogmosas.core.tr
import hu.fogmosas.core.visitText
import hu.fogmosas.shared.AppStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.util.UUID

// Complaint questions, advice, photos, sending to the doctor, visit requests and the linked clinic.

fun levelColor(l: TriageLevel) = when (l) {
    TriageLevel.SELF_CARE -> C.ok
    TriageLevel.MONITOR -> Color(0xFFC9A227)
    TriageLevel.SOON -> C.warn
    TriageLevel.URGENT, TriageLevel.EMERGENCY -> C.danger
}

object ClinicFiles {
    fun photoDir(ctx: Context) = File(ctx.filesDir, "photos").apply { mkdirs() }
    fun photo(ctx: Context, name: String) = File(photoDir(ctx), name)
    fun uri(ctx: Context, f: File): Uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", f)

    fun thumb(ctx: Context, name: String, size: Int = 240): Bitmap? = runCatching {
        val f = photo(ctx, name)
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, o)
        var s = 1
        while (o.outWidth / (s * 2) >= size && o.outHeight / (s * 2) >= size) s *= 2
        BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = s })
    }.getOrNull()

    /** Copies a picked image into the app's photo folder; returns its file name. */
    fun import(ctx: Context, uri: Uri): String? = runCatching {
        val name = "p-${UUID.randomUUID()}.jpg"
        ctx.contentResolver.openInputStream(uri)!!.use { input -> photo(ctx, name).outputStream().use { input.copyTo(it) } }
        name
    }.getOrNull()

    fun logoFile(ctx: Context) = File(ctx.filesDir, "clinic_logo.img")

    /** Downloads the clinic logo once (no image library needed). */
    suspend fun logo(ctx: Context, c: ClinicInfo): Bitmap? = withContext(Dispatchers.IO) {
        val f = logoFile(ctx)
        if (!f.exists()) c.logoUrl?.takeIf { it.startsWith("https://") }?.let { url ->
            runCatching {
                val conn = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                conn.connectTimeout = 5000; conn.readTimeout = 5000
                conn.inputStream.use { input -> f.outputStream().use { input.copyTo(it) } }
            }
        }
        runCatching { BitmapFactory.decodeFile(f.path) }.getOrNull()
    }
}

object ClinicSend {
    fun email(ctx: Context, clinic: ClinicInfo?, subject: String, body: String, photos: List<String>) {
        val uris = ArrayList(photos.map { ClinicFiles.uri(ctx, ClinicFiles.photo(ctx, it)) })
        val i = Intent(if (uris.isEmpty()) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE)
            .setType(if (uris.isEmpty()) "message/rfc822" else "image/jpeg")
            .putExtra(Intent.EXTRA_SUBJECT, subject)
            .putExtra(Intent.EXTRA_TEXT, body)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        clinic?.email?.let { i.putExtra(Intent.EXTRA_EMAIL, arrayOf(it)) }
        if (uris.isNotEmpty()) i.putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
        ctx.startActivity(Intent.createChooser(i, tr("Küldés e-mailben")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun dial(ctx: Context, number: String) =
        ctx.startActivity(Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + number.filter { it.isDigit() || it == '+' })).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

    fun open(ctx: Context, url: String) = runCatching {
        ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** Full-screen page with a top bar (back / progress / close). */
@Composable
private fun OverlayPage(title: String, progress: Float?, onBack: (() -> Unit)?, onClose: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().background(C.bg)) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { onBack?.invoke() }, enabled = onBack != null) { Text(if (onBack != null) tr("‹ Vissza") else "") }
            Text(title, Modifier.weight(1f), fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
            TextButton(onClick = onClose) { Text("✕", fontSize = 20.sp) }
        }
        if (progress != null) LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth().padding(horizontal = 16.dp), color = C.brand)
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth().verticalScroll(rememberScrollState()).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
        }
    }
}

@Composable
private fun ChoiceButton(label: String, selected: Boolean, onClick: () -> Unit) {
    OutlinedButton(onClick = onClick, modifier = Modifier.fillMaxWidth().height(56.dp), shape = RoundedCornerShape(14.dp),
        border = BorderStroke(2.dp, if (selected) C.brand else Color(0xFFD5DEE3)),
        colors = ButtonDefaults.outlinedButtonColors(containerColor = if (selected) C.brand.copy(alpha = 0.08f) else Color.White)) {
        Text(label, Modifier.fillMaxWidth(), fontSize = 17.sp, color = Color(0xFF1B2B34))
    }
}

/** The complaint, one question after the other, then advice, photos and sending. */
@Composable
fun SymptomWizard(activity: MainActivity, store: AppStore, onClose: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val ctx = LocalContext.current
    val flow = remember { SymptomFlow({ k -> recentSymptomCount(store.data.value.symptoms, p.id, k, System.currentTimeMillis()) }, p.child) }
    var tick by remember { mutableIntStateOf(0) }
    var multi by remember { mutableStateOf(setOf<String>()) }
    val q = remember(tick) { flow.next() }

    if (q != null) {
        OverlayPage(tr("Panasz"), flow.progress.toFloat(), if (flow.kind != null) ({ flow.back(); multi = emptySet(); tick += 1 }) else null, onClose) {
            Text(q.title, fontSize = 24.sp, fontWeight = FontWeight.Bold)
            if (q.id == "kind") Text(tr("Válaszd ki, mi történt. Utána pár rövid kérdés jön, hogy pontosan leírhasd."), color = C.muted)
            if (q.id == "teeth") {
                ToothMapPicker(multi) { multi = it }
                OutlinedButton(onClick = { flow.answer(listOf("unsure")); multi = emptySet(); tick += 1 }, Modifier.fillMaxWidth()) {
                    Text(tr("Nem tudom / kihagyom"))
                }
            } else q.options.forEach { o ->
                ChoiceButton(o.label, o.id in multi) {
                    if (q.multi) {
                        multi = if (o.id in multi) multi - o.id else multi + o.id
                    } else {
                        flow.answer(listOf(o.id))
                        tick += 1
                    }
                }
            }
            if (q.multi) Button(onClick = { flow.answer(multi.toList()); multi = emptySet(); tick += 1 }, enabled = multi.isNotEmpty(),
                modifier = Modifier.fillMaxWidth().height(52.dp)) { Text(tr("Tovább")) }
        }
        return
    }
    SymptomResult(activity, store, flow, onBack = { flow.back(); tick += 1 }, onClose = onClose)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SymptomResult(activity: MainActivity, store: AppStore, flow: SymptomFlow, onBack: () -> Unit, onClose: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val clinic = data.clinic
    val ctx = LocalContext.current
    val res = remember { flow.result() }
    var photos by remember { mutableStateOf(listOf<String>()) }
    var note by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf<SymptomReport?>(null) }
    var pendingPhoto by remember { mutableStateOf<String?>(null) }

    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val name = pendingPhoto
        if (ok && name != null) photos = photos + name else name?.let { ClinicFiles.photo(ctx, it).delete() }
        pendingPhoto = null
    }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { ClinicFiles.import(ctx, it) }?.let { photos = photos + it }
    }

    fun save(sentVia: String? = null): SymptomReport {
        val base = saved ?: flow.report(p.id, System.currentTimeMillis(), photos, note).also { r ->
            // Bleeding / sensitivity also count in the care journal.
            if (r.kind == "bleeding" || r.kind == "sensitivity")
                store.addCare(CareEntry(profileId = p.id, dateMs = r.dateMs, bleeding = r.kind == "bleeding",
                    sensitivity = if (r.kind == "sensitivity") (if (r.answers["since"]?.contains("today") == true) 1 else 2) else 0))
        }
        val r = base.copy(photos = photos, note = note, sentMs = if (sentVia != null) System.currentTimeMillis() else base.sentMs,
            sentVia = sentVia ?: base.sentVia)
        store.addSymptom(r)
        saved = r
        return r
    }

    OverlayPage(tr("Tanács"), null, onBack, onClose) {
        val k = Symptoms.kind(flow.kind ?: "other")
        Text("${k.emoji} ${k.title}", color = C.muted)
        Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(levelColor(res.level).copy(alpha = 0.12f)).padding(16.dp)) {
            Text("${res.level.emoji} ${res.level.title}", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = levelColor(res.level))
        }
        if (res.level == TriageLevel.EMERGENCY || res.level == TriageLevel.URGENT) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (res.level == TriageLevel.EMERGENCY) Button(onClick = { ClinicSend.dial(ctx, "112") },
                colors = ButtonDefaults.buttonColors(containerColor = C.danger)) { Text(tr("📞 112 hívása")) }
            clinic?.phone?.let { ph -> OutlinedButton(onClick = { ClinicSend.dial(ctx, ph) }) { Text(tr("📞 Rendelő hívása")) } }
        }
        InfoCard {
            Text(tr("Mit tehetsz most?"), fontWeight = FontWeight.Bold)
            res.advice.forEach { Text("• $it", fontSize = 15.sp) }
            Text(tr("Ez általános tanács, nem orvosi diagnózis. Ha bizonytalan vagy, vagy rosszabbodik, keresd az orvosodat."), fontSize = 12.sp, color = C.muted)
        }
        InfoCard {
            Text(tr("📷 Fotó"), fontWeight = FontWeight.Bold)
            Text(res.photo ?: tr("Ha látható a gond, egy fotó sokat segíthet az orvosnak."), fontSize = 14.sp, color = if (res.photo != null) C.brand else C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    val name = "p-${UUID.randomUUID()}.jpg"
                    pendingPhoto = name
                    camera.launch(ClinicFiles.uri(ctx, ClinicFiles.photo(ctx, name)))
                }) { Text(tr("Fotó készítése")) }
                OutlinedButton(onClick = { gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Text(tr("Galéria")) }
            }
            if (photos.isNotEmpty()) Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                photos.forEach { name ->
                    val bmp = remember(name) { ClinicFiles.thumb(ctx, name) }
                    Box {
                        if (bmp != null) Image(bmp.asImageBitmap(), null, Modifier.size(96.dp).clip(RoundedCornerShape(10.dp)), contentScale = ContentScale.Crop)
                        TextButton(onClick = { photos = photos - name; ClinicFiles.photo(ctx, name).delete() }, Modifier.align(Alignment.TopEnd)) { Text("✕") }
                    }
                }
            }
        }
        OutlinedTextField(note, { note = it }, label = { Text(tr("Megjegyzés (nem kötelező)")) }, modifier = Modifier.fillMaxWidth(), minLines = 2)

        val serious = res.suggestMessage
        InfoCard {
            Text(if (serious) tr("Elküldöd az orvosodnak?") else tr("Szeretnéd mégis megmutatni az orvosodnak?"), fontWeight = FontWeight.Bold)
            Text(if (clinic != null) tr("Rendelő: {0}", clinic.name) else tr("Ha a DentHubon összekötöd a fiókod a rendelőddel, közvetlenül nekik küldheted, és az orvos a kartonodhoz mentheti."),
                fontSize = 13.sp, color = C.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (clinic != null) Button(onClick = {
                    val r = save("message")
                    store.addMessage(ClinicMessage(profileId = p.id, dateMs = System.currentTimeMillis(),
                        text = symptomSummary(r).joinToString("\n"), photos = r.photos, symptomId = r.id))
                    Toast.makeText(ctx, tr("Az üzenet a rendelő postafiókjába került."), Toast.LENGTH_LONG).show()
                }) { Text(tr("📨 Üzenet a rendelőnek")) }
                OutlinedButton(onClick = {
                    val r = save("email")
                    val (subject, body) = clinicEmail(p.name, r, null)
                    ClinicSend.email(ctx, clinic, subject, body, r.photos)
                }) { Text(tr("✉️ E-mail")) }
            }
            saved?.sentVia?.let { Text(if (it == "message") tr("✔︎ Elküldve a rendelőnek") else tr("✔︎ E-mail előkészítve"), color = C.ok, fontSize = 13.sp) }
        }
        if (res.suggestBooking || clinic != null) OutlinedButton(onClick = {
            val r = save()
            activity.overlay.value = "visit:${r.id}"
        }, Modifier.fillMaxWidth()) { Text(tr("📅 Időpontot kérek")) }
        var addTask by remember { mutableStateOf(false) }
        OutlinedButton(onClick = { addTask = true }, Modifier.fillMaxWidth()) { Text(tr("💊 Gyógyszer / teendő emlékeztető")) }
        if (addTask) CareTaskDialog(store, p.id) { addTask = false }
        Button(onClick = { save(); ReminderScheduler.reschedule(ctx); onClose() }, Modifier.fillMaxWidth().height(52.dp)) { Text(tr("Mentés a naplóba és bezárás")) }
    }
}

private fun reasonFor(kind: String?) = when (kind) {
    "pain", "sensitivity", "swelling", "jaw" -> "pain"
    "bleeding" -> "bleeding"
    "chipped", "knocked", "loose" -> "broken"
    "braces" -> "braces"
    null -> "checkup"
    else -> "other"
}

/** "Időpontot kérek": only a check-up, or a reason; when; then booking, message, e-mail or a call. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun VisitRequestScreen(store: AppStore, symptomId: String?, onClose: () -> Unit) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val clinic = data.clinic
    val ctx = LocalContext.current
    val symptom = data.symptoms.firstOrNull { it.id == symptomId }
    var reason by remember { mutableStateOf(reasonFor(symptom?.kind)) }
    var timing by remember { mutableStateOf(if (symptom != null && TriageLevel.byId(symptom.level).rank >= TriageLevel.URGENT.rank) "asap" else "any") }
    var parts by remember { mutableStateOf(setOf<String>()) }
    var note by remember { mutableStateOf("") }
    var sent by remember { mutableStateOf<String?>(null) }

    fun request(via: String?): VisitRequest {
        val v = VisitRequest(profileId = p.id, createdMs = System.currentTimeMillis(), reason = reason, note = note, timing = timing,
            dayParts = parts.toList(), symptomId = symptom?.id, sentMs = via?.let { System.currentTimeMillis() }, sentVia = via)
        store.addVisit(v)
        sent = via
        return v
    }

    OverlayPage(tr("Időpontkérés"), null, null, onClose) {
        clinic?.let { Text("🏥 ${it.name}", fontWeight = FontWeight.Bold) }
        Text(tr("Csak kontrollra mennél, vagy van oka?"), fontSize = 20.sp, fontWeight = FontWeight.Bold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VisitReasons.all.forEach { (id, label) -> FilterChip(selected = reason == id, onClick = { reason = id }, label = { Text(label) }) }
        }
        if (reason != "checkup" && reason != "cleaning" && symptom == null) {
            Text(tr("Tipp: ha panaszod van, a „Panaszom van” kérdései alapján az orvos pontosabb képet kap."), fontSize = 13.sp, color = C.muted)
        }
        if (symptom != null) InfoCard { symptomSummary(symptom).forEach { Text(it, fontSize = 13.sp) } }
        Text(tr("Mikor lenne jó?"), fontWeight = FontWeight.Bold)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VisitReasons.timings.forEach { (id, label) -> FilterChip(selected = timing == id, onClick = { timing = id }, label = { Text(label) }) }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            VisitReasons.dayParts.forEach { (id, label) ->
                FilterChip(selected = id in parts, onClick = { parts = if (id in parts) parts - id else parts + id }, label = { Text(label) })
            }
        }
        OutlinedTextField(note, { note = it }, label = { Text(tr("Megjegyzés (nem kötelező)")) }, modifier = Modifier.fillMaxWidth(), minLines = 2)

        val booking = clinic?.let { bookingLink(it, null) }
        if (booking != null) Button(onClick = { ClinicSend.open(ctx, bookingLink(clinic!!, request("booking"))!!) }, Modifier.fillMaxWidth().height(52.dp)) {
            Text(tr("📅 Online foglalás a rendelőnél"))
        }
        if (clinic != null) OutlinedButton(onClick = {
            val v = request("message")
            store.addMessage(ClinicMessage(profileId = p.id, dateMs = System.currentTimeMillis(), text = visitText(v, p.name, symptom),
                photos = symptom?.photos.orEmpty(), symptomId = symptom?.id, visitId = v.id))
            Toast.makeText(ctx, tr("Az időpontkérés a rendelő postafiókjába került."), Toast.LENGTH_LONG).show()
        }, Modifier.fillMaxWidth()) { Text(tr("📨 Kérés üzenetben")) }
        OutlinedButton(onClick = {
            val v = request("email")
            val (subject, body) = clinicEmail(p.name, symptom, v)
            ClinicSend.email(ctx, clinic, subject, body, symptom?.photos.orEmpty())
        }, Modifier.fillMaxWidth()) { Text(tr("✉️ Kérés e-mailben")) }
        clinic?.phone?.let { ph -> OutlinedButton(onClick = { request("phone"); ClinicSend.dial(ctx, ph) }, Modifier.fillMaxWidth()) { Text(tr("📞 Hívás: {0}", ph)) } }
        if (clinic == null) Text(tr("Ha a DentHubon összekötöd a fiókod a rendelőddel, innen közvetlenül foglalhatsz időpontot."), fontSize = 13.sp, color = C.muted)
        sent?.let { Text(tr("✔︎ Elmentve – a rendelő visszaigazolja az időpontot."), color = C.ok) }
    }
}

/** Home: dentist status, "Panaszom van", "Időpontot kérek" and the last check-up if unknown. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun DentistCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (!data.settings.isOn("dentist_reminders") || !p.canRead) return
    val st = dentistStatus(p.lastCheckup?.let(LocalDate::parse), p.lastCleaning?.let(LocalDate::parse), LocalDate.now())
    InfoCard {
        Text(data.clinic?.let { "🦷 ${it.name}" } ?: tr("🦷 Fogorvos"), fontWeight = FontWeight.Bold)
        st.message?.let { Text(it, fontSize = 13.sp, color = C.muted) }
        if (p.lastCheckup == null) {
            Text(tr("Mikor voltál utoljára fogorvosi kontrollon?"), fontSize = 13.sp, color = C.muted)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                DentistIntake.options.filter { it.first != "unknown" }.forEach { (id, label) ->
                    FilterChip(selected = false, onClick = {
                        DentistIntake.date(id, LocalDate.now())?.let { store.updateProfile(p.copy(lastCheckup = it.toString())) }
                    }, label = { Text(label, fontSize = 12.sp) })
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(onClick = { activity.overlay.value = "symptom" }) { Text(tr("🩺 Panaszom van")) }
            OutlinedButton(onClick = { activity.overlay.value = "visit" }) { Text(tr("📅 Időpontot kérek")) }
            if (st.checkupOverdue) TextButton(onClick = { store.updateProfile(p.copy(lastCheckup = LocalDate.now().toString())) }) { Text(tr("Ma voltam kontrollon")) }
        }
    }
}

/** Statistics: recorded complaints and visit requests. */
@Composable
fun SymptomHistoryCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    val list = data.symptoms.filter { it.profileId == p.id }.sortedByDescending { it.dateMs }
    var open by remember { mutableStateOf<SymptomReport?>(null) }
    InfoCard {
        Text(tr("Panaszok"), fontWeight = FontWeight.Bold)
        if (list.isEmpty()) Text(tr("Még nincs rögzített panasz."), fontSize = 13.sp, color = C.muted)
        list.take(8).forEach { r ->
            TextButton(onClick = { open = r }) {
                Text("${TriageLevel.byId(r.level).emoji} ${symptomSummary(r).first()}" + (r.sentVia?.let { " ✉︎" } ?: ""),
                    Modifier.fillMaxWidth(), fontSize = 14.sp, color = Color(0xFF1B2B34))
            }
        }
        OutlinedButton(onClick = { activity.overlay.value = "symptom" }) { Text(tr("🩺 Új panasz")) }
    }
    open?.let { r ->
        val ctx = LocalContext.current
        AlertDialog(onDismissRequest = { open = null }, title = { Text(Symptoms.kind(r.kind).title) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    symptomSummary(r).drop(1).forEach { Text(it, fontSize = 14.sp) }
                    data.followUps.filter { it.reportId == r.id }.forEach { f ->
                        Text(tr("{0}. nap: {1}", f.day, hu.fogmosas.core.FollowUps.title(f.answer)), fontSize = 13.sp, color = C.muted)
                    }
                    PhotoTimeline(hu.fogmosas.core.photoTimeline(data.symptoms, p.id, r.kind))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    val (subject, body) = clinicEmail(p.name, r, null)
                    ClinicSend.email(ctx, data.clinic, subject, body, r.photos)
                    store.addSymptom(r.copy(sentMs = System.currentTimeMillis(), sentVia = "email"))
                    open = null
                }) { Text(tr("✉️ Küldés")) }
            },
            dismissButton = { TextButton(onClick = { open = null }) { Text(tr("Bezárás")) } })
    }
}

/** Settings: link code from the clinic (QR / pasted), or the linked clinic. */
@Composable
fun ClinicLinkCard(activity: MainActivity, store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val ctx = LocalContext.current
    var code by remember { mutableStateOf("") }
    var error by remember { mutableStateOf(false) }
    InfoCard {
        Text(tr("🏥 Rendelőm"), fontWeight = FontWeight.Bold)
        val c = data.clinic
        if (c != null) {
            Text(c.name, fontSize = 17.sp)
            listOfNotNull(c.address, c.phone, c.email).forEach { Text(it, fontSize = 13.sp, color = C.muted) }
            val queued = data.messages.count { it.status == "queued" }
            if (queued > 0) Text(tr("{0} üzenet vár kézbesítésre a DentHubon keresztül.", queued), fontSize = 13.sp, color = C.muted)
            TextButton(onClick = { store.setClinic(null); ClinicFiles.logoFile(ctx).delete() }) { Text(tr("Összekötés megszüntetése")) }
        } else {
            Text(tr("A rendelőd a DentHubon ad egy összekötő QR-kódot vagy linket. Ezzel a rendelő logója megjelenik indításkor, és nekik küldheted a panaszaidat és időpontkéréseidet."),
                fontSize = 13.sp, color = C.muted)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = {
                    WebShare.scan(activity) { raw ->
                        val found = raw?.let { parseClinicLink(it) }
                        val care = raw?.let { hu.fogmosas.core.parseCareLink(it) }
                        if (found != null) {
                            activity.pendingClinic.value = found
                        } else if (care != null) {
                            activity.pendingCare.value = care
                        } else if (raw != null) {
                            error = true
                        }
                    }
                }) { Text(tr("QR-kód beolvasása")) }
            }
            OutlinedTextField(code, { code = it; error = false }, label = { Text(tr("…vagy illeszd be a linket")) }, modifier = Modifier.fillMaxWidth(), singleLine = true)
            if (error) Text(tr("Ez nem érvényes DentHub összekötő kód."), color = C.danger, fontSize = 13.sp)
            if (code.isNotBlank()) Button(onClick = {
                val found = parseClinicLink(code)
                if (found != null) {
                    activity.pendingClinic.value = found
                    code = ""
                } else {
                    error = true
                }
            }) { Text(tr("Összekötés")) }
        }
    }
}

/** Confirmation for a clinic link code opened from a QR code or a link. */
@Composable
fun ClinicLinkDialog(activity: MainActivity, store: AppStore) {
    val c = activity.pendingClinic.value ?: return
    val ctx = LocalContext.current
    AlertDialog(onDismissRequest = { activity.pendingClinic.value = null },
        title = { Text(tr("Összekötöd a rendelőddel?")) },
        text = { Text(tr("{0}\nA rendelő logója megjelenik indításkor, és nekik küldheted a panaszaidat, fotóidat és időpontkéréseidet.", c.name)) },
        confirmButton = {
            TextButton(onClick = {
                ClinicFiles.logoFile(ctx).delete()
                store.setClinic(c)
                activity.pendingClinic.value = null
            }) { Text(tr("Összekötés")) }
        },
        dismissButton = { TextButton(onClick = { activity.pendingClinic.value = null }) { Text(tr("Mégse")) } })
}

/** Start screen with the DentHub-Brush and the linked clinic's logo. */
@Composable
fun ClinicSplash(clinic: ClinicInfo, onDone: () -> Unit) {
    val ctx = LocalContext.current
    var logo by remember { mutableStateOf<Bitmap?>(null) }
    LaunchedEffect(clinic.id) {
        logo = ClinicFiles.logo(ctx, clinic)
        delay(1400)
        onDone()
    }
    Box(Modifier.fillMaxSize().background(Color.White), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            Text("🪥", fontSize = 64.sp)
            Text("DentHub-Brush", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = C.brand)
            Text("×", fontSize = 22.sp, color = C.muted)
            val l = logo
            if (l != null) Image(l.asImageBitmap(), clinic.name, Modifier.size(140.dp), contentScale = ContentScale.Fit)
            Text(clinic.name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.height(12.dp))
        }
    }
}

/** After a brushing: "Minden rendben?" when it was unusual, and "+ Egyéb információ" always. */
@Composable
fun BrushingExtrasRow(activity: MainActivity, anomaly: String?) {
    var ok by remember(anomaly) { mutableStateOf(false) }
    val ask = anomaly != null && !ok
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (ask) Text(anomaly!!, fontWeight = FontWeight.Bold)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (ask) OutlinedButton(onClick = { ok = true }) { Text(tr("Minden rendben")) }
            OutlinedButton(onClick = { activity.overlay.value = "symptom" }) { Text(if (ask) tr("Valami gond van") else tr("＋ Egyéb információ, panasz")) }
        }
    }
}

/** Home: the brush's battery was running low last time — charge it. */
@Composable
fun ChargeReminderCard(store: AppStore) {
    val data by store.data.collectAsStateWithLifecycle()
    val p = data.activeProfile
    if (p.chargeReminderMs == null || !p.electric) return
    InfoCard {
        Text(tr("🔋 Tedd töltőre a fogkefédet!"), fontWeight = FontWeight.Bold, color = C.warn)
        Text(tr("A legutóbbi fogmosásnál lemerülőben volt az akkumulátora. Töltsd fel a következő mosás előtt."), fontSize = 13.sp, color = C.muted)
        OutlinedButton(onClick = { store.updateProfile(p.copy(chargeReminderMs = null)) }) { Text(tr("Feltöltöttem")) }
    }
}
