package hu.fogmosas.core

import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Mirrored in SymptomsTests.swift. */
class SymptomsTest {
    private fun flow(vararg steps: List<String>, recent: Int = 0): SymptomFlow {
        val f = SymptomFlow({ recent })
        steps.forEach { f.answer(it) }
        return f
    }

    @Test
    fun bleedingAsksWhereThenSelfCare() {
        val f = SymptomFlow()
        assertEquals("kind", f.next()!!.id)
        f.answer(listOf("bleeding"))
        assertEquals(listOf("jaw", "side", "bleed_when", "bleed_amount", "since"),
            generateSequence { f.next()?.also { q -> f.answer(listOf(q.options.first().id)) }?.id }.toList())
        assertNull(f.next())
        val r = f.result()
        assertEquals(TriageLevel.SELF_CARE, r.level)
        assertFalse(r.suggestBooking)
        assertTrue(r.advice.isNotEmpty())
        assertEquals(1.0, f.progress)
    }

    @Test
    fun swellingWithBreathingTroubleIsAnEmergency() {
        val f = flow(listOf("pain"), listOf("lower"), listOf("right"), listOf("back"), listOf("moderate"), listOf("chewing"), listOf("days"), listOf("yes"))
        assertEquals("fever", f.next()!!.id)
        f.answer(listOf("no")); f.answer(listOf("yes"))
        assertNull(f.next())
        val r = f.result()
        assertEquals(TriageLevel.EMERGENCY, r.level)
        assertTrue(r.suggestMessage && r.suggestBooking)
        assertNotNull(r.photo)
    }

    @Test
    fun nightPainIsUrgentAndMultiChoiceKept() {
        val f = flow(listOf("pain"), listOf("upper"), listOf("left"), listOf("back"), listOf("mild"), listOf("hot", "night"), listOf("today"), listOf("no"))
        assertEquals(listOf("hot", "night"), f.answers["trigger"])
        assertEquals(TriageLevel.URGENT, f.result().level)
    }

    @Test
    fun knockedOutPermanentToothIsAnEmergencyBabyToothIsNot() {
        assertEquals(TriageLevel.EMERGENCY, triage("knocked", mapOf("tooth_type" to listOf("permanent"))).level)
        assertEquals(TriageLevel.SOON, triage("knocked", mapOf("tooth_type" to listOf("baby"))).level)
    }

    @Test
    fun biteInjurySelfCareUnlessBleedingGoesOn() {
        val small = triage("injury", mapOf("injury_cause" to listOf("bite"), "wound_bleed" to listOf("stopped"), "wound_deep" to listOf("no"), "pain" to listOf("mild")))
        assertEquals(TriageLevel.SELF_CARE, small.level)
        assertNotNull(small.photo)
        assertFalse(small.suggestMessage)
        assertEquals(TriageLevel.URGENT, triage("injury", mapOf("injury_cause" to listOf("bite"), "wound_bleed" to listOf("not_stopping"))).level)
    }

    @Test
    fun recurringComplaintEscalates() {
        val a = mapOf("bleed_amount" to listOf("drops"), "since" to listOf("today"))
        assertEquals(TriageLevel.SELF_CARE, triage("bleeding", a, recentSameKind = 1).level)
        assertEquals(TriageLevel.SOON, triage("bleeding", a, recentSameKind = 2).level)
    }

    @Test
    fun backAndInvalidAnswers() {
        val f = flow(listOf("stuck"), listOf("upper"))
        assertTrue(f.back()); assertEquals("jaw", f.next()!!.id)
        assertTrue(f.back()); assertEquals("kind", f.next()!!.id)
        assertFalse(f.back())
        assertTrue(runCatching { f.answer(listOf("nope")) }.isFailure)
    }

    @Test
    fun summaryEmailAndVisit() {
        val f = flow(listOf("chipped"), listOf("tooth"), listOf("upper"), listOf("front"), listOf("front"), listOf("none"), listOf("yes"), listOf("yes"))
        val r = f.report("me", 1_700_000_000_000, photos = listOf("a.jpg"), note = "Diótörés")
        val lines = symptomSummary(r, ZoneOffset.UTC)
        assertTrue(lines.first().contains("🦷"))
        assertTrue(lines.any { it.startsWith("Fogsor: Felső") })
        assertTrue(lines.any { it.contains("Diótörés") })
        assertEquals(TriageLevel.SOON.id, r.level)
        val v = VisitRequest(profileId = "me", createdMs = 0, reason = "broken", timing = "week", dayParts = listOf("morning"), symptomId = r.id)
        val (subject, body) = clinicEmail("Kiss Anna", r, v)
        assertTrue(subject.contains("Kiss Anna"))
        assertTrue(body.contains("Letört fog vagy tömés") && body.contains("Délelőtt") && body.contains("Fotók: 1 db"))
        assertEquals(1, recentSymptomCount(listOf(r), "me", "chipped", r.dateMs + 1000))
        assertEquals(0, recentSymptomCount(listOf(r), "me", "chipped", r.dateMs + 31 * 86_400_000L))
    }

    @Test
    fun clinicLinkRoundTripAndBooking() {
        val c = ClinicInfo("c1", "Mosoly Fogászat", email = "info@example.com", bookingUrl = "https://example.com/book")
        assertEquals(c, parseClinicLink(clinicLinkCode(c)))
        assertEquals(c, parseClinicLink("https://denthub.example/link#" + clinicLinkCode(c).substringAfter("d=")))
        assertNull(parseClinicLink("hello"))
        assertNull(parseClinicLink("denthub://link?d=!!!"))
        val v = VisitRequest(profileId = "me", createdMs = 0, reason = "checkup", timing = "asap")
        assertEquals("https://example.com/book?reason=checkup&timing=asap", bookingLink(c, v))
        assertNull(bookingLink(c.copy(bookingUrl = null), v))
    }

    @Test
    fun anomalyAndIntake() {
        val usual = List(6) { 120.0 }
        assertNotNull(brushingAnomaly(50.0, usual, 1, 2))
        assertNotNull(brushingAnomaly(220.0, usual, 1, 2))
        assertNull(brushingAnomaly(118.0, usual, 1, 2))
        assertNotNull(brushingAnomaly(118.0, usual, 4, 2))
        assertNull(brushingAnomaly(30.0, listOf(120.0), 1, 2))
        val today = LocalDate.of(2026, 11, 3)
        assertEquals(LocalDate.of(2026, 8, 3), DentistIntake.date("lt6m", today))
        assertNull(DentistIntake.date("unknown", today))
    }
}
