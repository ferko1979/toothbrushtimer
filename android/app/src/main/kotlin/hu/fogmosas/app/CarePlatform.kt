package hu.fogmosas.app

import android.content.Context
import android.content.Intent
import android.graphics.Color as AColor
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricManager.Authenticators.BIOMETRIC_WEAK
import androidx.biometric.BiometricManager.Authenticators.DEVICE_CREDENTIAL
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.fragment.app.FragmentActivity
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import hu.fogmosas.core.DentistReport
import hu.fogmosas.core.WebLink
import hu.fogmosas.shared.AppData
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import hu.fogmosas.core.tr

/** Face / fingerprint / screen-lock check (androidx.biometric). */
object DeviceAuth {
    private const val AUTH = BIOMETRIC_WEAK or DEVICE_CREDENTIAL

    fun available(ctx: Context) = BiometricManager.from(ctx).canAuthenticate(AUTH) == BiometricManager.BIOMETRIC_SUCCESS

    /** Calls back with true when the owner was verified, or when the device has no screen lock at all. */
    fun authenticate(activity: FragmentActivity, title: String, subtitle: String? = null, onResult: (Boolean) -> Unit) {
        if (!available(activity)) { onResult(true); return }
        val prompt = BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(true)
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = onResult(false)
        })
        val info = BiometricPrompt.PromptInfo.Builder().setTitle(title).apply { subtitle?.let { setSubtitle(it) } }
            .setAllowedAuthenticators(AUTH).build()
        prompt.authenticate(info)
    }
}

/** Dentist report as a printable A4 PDF, shared with the system share sheet. */
object ReportPdf {
    fun write(ctx: Context, report: DentistReport): File {
        val doc = PdfDocument()
        val w = 595; val h = 842; val margin = 48
        val title = TextPaint().apply { isAntiAlias = true; textSize = 20f; typeface = Typeface.DEFAULT_BOLD; color = AColor.BLACK }
        val head = TextPaint().apply { isAntiAlias = true; textSize = 14f; typeface = Typeface.DEFAULT_BOLD; color = AColor.rgb(30, 155, 184) }
        val body = TextPaint().apply { isAntiAlias = true; textSize = 11f; color = AColor.rgb(30, 30, 30) }
        val muted = TextPaint(body).apply { color = AColor.rgb(91, 109, 121) }
        var pageNo = 0
        var page: PdfDocument.Page? = null
        var y = 0f
        fun newPage() {
            page?.let { doc.finishPage(it) }
            pageNo++
            page = doc.startPage(PdfDocument.PageInfo.Builder(w, h, pageNo).create())
            y = margin.toFloat()
        }
        fun draw(text: String, paint: TextPaint, indent: Int = 0, after: Float = 4f) {
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, w - 2 * margin - indent)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
            if (y + layout.height > h - margin) newPage()
            val c = page!!.canvas
            c.save(); c.translate((margin + indent).toFloat(), y); layout.draw(c); c.restore()
            y += layout.height + after
        }
        newPage()
        draw(report.title, title)
        draw(report.subtitle, muted, after = 16f)
        for (s in report.sections) {
            draw(s.title, head, after = 6f)
            for (l in s.lines) draw("•  $l", body, indent = 8)
            y += 10f
        }
        draw(tr("Készült a DentHub-Brush appal. A tünetek a felhasználó saját jelölései, nem orvosi diagnózis."), muted)
        page?.let { doc.finishPage(it) }
        val dir = File(ctx.cacheDir, "reports").apply { mkdirs() }
        val f = File(dir, "fogapolasi-jelentes.pdf")
        f.outputStream().use { doc.writeTo(it) }
        doc.close()
        return f
    }

    fun share(ctx: Context, file: File) {
        val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".files", file)
        val i = Intent(Intent.ACTION_SEND).setType("application/pdf").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(Intent.createChooser(i, tr("Jelentés megosztása")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** "Megnézem a weben": scan the QR code on the web page, encrypt a snapshot, post it to the relay. */
object WebShare {
    fun scan(activity: FragmentActivity, onResult: (String?) -> Unit) {
        val opts = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
        GmsBarcodeScanning.getClient(activity, opts).startScan()
            .addOnSuccessListener { onResult(it.rawValue) }
            .addOnCanceledListener { onResult(null) }
            .addOnFailureListener { onResult(null) }
    }

    /** Adult profile: the whole family; a child: only that child. */
    fun snapshotJson(d: AppData, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): String {
        val active = d.activeProfile
        val profiles = if (active.child) listOf(active) else d.profiles
        val today = LocalDate.now(zone)
        val snaps = profiles.map {
            WebLink.profileSnapshot(it, d.records(it.id), d.care(it.id), today, zone, d.settings.isOn("floss_tracking"))
        }
        return WebLink.snapshotJson(WebLink.snapshot(snaps, now, d.settings.locale))
    }

    /** Returns null on success, or a message for the user. */
    suspend fun send(pairing: WebLink.Pairing, json: String): String? = withContext(Dispatchers.IO) {
        try {
            val env = WebLink.b64(WebLink.seal(pairing.webPublicKey, pairing.sid, json.toByteArray()))
            val c = URL(pairing.uploadUrl).openConnection() as HttpURLConnection
            c.requestMethod = "POST"
            c.connectTimeout = 15_000
            c.readTimeout = 15_000
            c.doOutput = true
            c.setRequestProperty("Content-Type", "text/plain")
            c.outputStream.use { it.write(env.toByteArray()) }
            val code = c.responseCode
            c.disconnect()
            when (code) {
                204, 200 -> null
                409 -> tr("Ezt a kódot már felhasználtad. Kérj új kódot a weboldalon.")
                else -> tr("A szerver hibát jelzett ({0}).", code)
            }
        } catch (e: Exception) {
            tr("Nem sikerült elérni a weboldalt. Ellenőrizd az internetkapcsolatot.")
        }
    }
}
