package hu.fogmosas.core

import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MessagingTest {
    private val clinic = ClinicInfo(id = "c1", name = "Mosoly", email = "info@mosoly.hu", messaging = true)

    @Test fun channelsFollowBothSides() {
        assertEquals(listOf("app"), Messaging.channels(clinic, appToApp = true, alsoEmail = false))
        assertEquals(listOf("app", "email"), Messaging.channels(clinic, appToApp = true, alsoEmail = true))
        assertEquals(listOf("email"), Messaging.channels(clinic, appToApp = false, alsoEmail = false))
        assertEquals(listOf("email"), Messaging.channels(clinic.copy(messaging = false), appToApp = true, alsoEmail = false))
        assertEquals(emptyList(), Messaging.channels(clinic.copy(messaging = false, email = null), appToApp = true, alsoEmail = true))
        assertEquals("queued", Messaging.statusAfterSend(listOf("app", "email")))
        assertEquals("emailed", Messaging.statusAfterSend(listOf("email")))
    }

    @Test fun threadAndUnread() {
        val m = listOf(
            ClinicMessage(profileId = "me", dateMs = 2, text = "b", fromPatient = false, status = "received"),
            ClinicMessage(profileId = "me", dateMs = 1, text = "a"),
            ClinicMessage(profileId = "kid", dateMs = 3, text = "c"),
        )
        assertEquals(listOf("a", "b"), Messaging.thread(m, "me").map { it.text })
        assertEquals(1, Messaging.unread(m, "me"))
        assertTrue(Messaging.hasConversation(m, "kid"))
    }

    @Test fun offerLinkRoundTripAndReminders() {
        val a = Appointment(profileId = "x", start = "2026-11-10T10:30", doctor = "Dr. Kiss", clinicName = "Mosoly", reason = "pain")
        val got = assertNotNull(Messaging.parseOffer(Messaging.offerCode(a), "me"))
        assertEquals("offered", got.status)
        assertEquals("Dr. Kiss", got.doctor)
        // Without a profile in the link it takes the given one.
        val raw = "denthub://appt?d=" + java.util.Base64.getUrlEncoder().withoutPadding().encodeToString("""{"start":"2026-11-10T09:00"}""".toByteArray())
        assertEquals("me", Messaging.parseOffer(raw, "me")?.profileId)
        assertNull(Messaging.parseOffer("denthub://appt?d=xyz", "me"))

        val now = LocalDateTime.of(2026, 11, 9, 9, 0)
        assertTrue(Messaging.reminders(listOf(got), now).isEmpty(), "offers have no reminders")
        val r = Messaging.reminders(listOf(got.copy(status = "confirmed")), now)
        assertEquals(listOf(LocalDateTime.of(2026, 11, 9, 10, 30), LocalDateTime.of(2026, 11, 10, 8, 30)), r.map { it.first })
        assertEquals(1, Messaging.reminders(listOf(got.copy(status = "confirmed")), LocalDateTime.of(2026, 11, 9, 12, 0)).size)
        assertEquals(listOf(got), Messaging.upcoming(listOf(got, got.copy(id = "old", start = "2026-11-01T10:00")), "me", now))
    }
}
