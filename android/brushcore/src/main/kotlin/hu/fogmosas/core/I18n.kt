package hu.fogmosas.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * UI language. Source strings are Hungarian; English comes from /i18n/en.json
 * (shared with iOS and the web, generated from i18n/strings.json).
 * Placeholders: {0}, {1}… An English entry may be {"one": …, "other": …},
 * chosen by the first numeric argument.
 */
object I18n {
    @Volatile var lang: String = "hu"
        private set

    private val en: JsonObject by lazy {
        val text = I18n::class.java.getResourceAsStream("/i18n/en.json")?.readBytes()?.toString(Charsets.UTF_8) ?: "{}"
        Json.parseToJsonElement(text) as JsonObject
    }

    /** pref: "hu", "en", or "" / null for the device language. */
    fun resolve(pref: String?): String = when (pref) {
        "hu", "en" -> pref
        else -> if (Locale.getDefault().language == "hu") "hu" else "en"
    }

    fun setLanguage(pref: String?) { lang = resolve(pref) }

    val locale: Locale get() = if (lang == "hu") Locale("hu", "HU") else Locale.US

    fun has(key: String) = en.containsKey(key)

    fun t(key: String, args: Array<out Any?>): String {
        var s = key
        if (lang != "hu") {
            when (val v = en[key]) {
                is JsonPrimitive -> s = v.content
                is JsonObject -> {
                    val n = args.firstOrNull { it is Number } as Number?
                    val form = if (n != null && n.toDouble() == 1.0) "one" else "other"
                    s = (v[form] ?: v["other"])?.jsonPrimitive?.content ?: key
                }
                else -> {}
            }
        }
        args.forEachIndexed { i, a -> s = s.replace("{$i}", a.toString()) }
        return s
    }

    /** 2026.05.10. / May 10, 2026 */
    fun date(d: LocalDate): String =
        if (lang == "hu") d.format(DateTimeFormatter.ofPattern("yyyy.MM.dd.")) else d.format(DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US))
}

fun tr(key: String, vararg args: Any?): String = I18n.t(key, args)
