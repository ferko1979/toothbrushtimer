import Foundation

// Messenger with the linked clinic and appointments (request -> offer -> confirmed -> calendar and
// reminders). Same as android/brushcore/.../Messaging.kt (tests: MessagingTest.kt / MessagingTests.swift).
// Delivery through DentHub needs its server (docs/DENTHUB-API.md); until then app messages wait
// ("queued") and e-mail goes out right away, and every e-mail is also kept as an internal message.

/// An appointment at the clinic.
public struct Appointment: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    /// Local start time, "2026-11-10T10:30".
    public var start: String
    public var durationMin = 30
    public var reason = "checkup"
    public var clinicName: String? = nil
    public var doctor: String? = nil
    public var address: String? = nil
    public var note = ""
    /// requested / offered / confirmed / cancelled
    public var status = "confirmed"
    public var calendarAdded = false
    /// Reminders, minutes before the start.
    public var remindersMin = [24 * 60, 120]

    public init(profileId: String, start: String, durationMin: Int = 30, reason: String = "checkup", clinicName: String? = nil,
                doctor: String? = nil, address: String? = nil, note: String = "", status: String = "confirmed", calendarAdded: Bool = false) {
        self.profileId = profileId; self.start = start; self.durationMin = durationMin; self.reason = reason
        self.clinicName = clinicName; self.doctor = doctor; self.address = address; self.note = note
        self.status = status; self.calendarAdded = calendarAdded
    }

    enum CodingKeys: String, CodingKey { case id, profileId, start, durationMin, reason, clinicName, doctor, address, note, status, calendarAdded, remindersMin }

    // Offers from the clinic may leave out anything but the start.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        profileId = try c.decodeIfPresent(String.self, forKey: .profileId) ?? ""
        start = try c.decode(String.self, forKey: .start)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin) ?? 30
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? "checkup"
        clinicName = try c.decodeIfPresent(String.self, forKey: .clinicName)
        doctor = try c.decodeIfPresent(String.self, forKey: .doctor)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "confirmed"
        calendarAdded = try c.decodeIfPresent(Bool.self, forKey: .calendarAdded) ?? false
        remindersMin = try c.decodeIfPresent([Int].self, forKey: .remindersMin) ?? [24 * 60, 120]
    }
}

public enum Recipients {
    public static var all: [(String, String)] { [("doctor", tr("Orvos")), ("admin", tr("Recepció / asszisztens"))] }
    public static func title(_ id: String) -> String { all.first { $0.0 == id }?.1 ?? id }
}

public enum Messaging {
    static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    public static func startOf(_ a: Appointment) -> Date? { stamp.date(from: a.start) }
    public static func format(_ d: Date) -> String { stamp.string(from: d) }

    /// Conversation with the clinic for one profile, oldest first.
    public static func thread(_ messages: [ClinicMessage], profileId: String) -> [ClinicMessage] {
        messages.filter { $0.profileId == profileId }.sorted { $0.date < $1.date }
    }

    public static func unread(_ messages: [ClinicMessage], profileId: String) -> Int {
        messages.filter { $0.profileId == profileId && !$0.fromPatient && $0.readAt == nil }.count
    }

    /// The message icon shows once there is a conversation.
    public static func hasConversation(_ messages: [ClinicMessage], profileId: String) -> Bool { messages.contains { $0.profileId == profileId } }

    /// How a message goes out: in the app when the clinic allows it and the patient turned it on (it
    /// waits until DentHub delivers it), by e-mail when asked or when the app route is not available.
    public static func channels(clinic: ClinicInfo?, appToApp: Bool, alsoEmail: Bool) -> [String] {
        let app = clinic != nil && clinic!.allowsMessaging && appToApp
        let email = clinic?.email != nil && (alsoEmail || !app)
        return (app ? ["app"] : []) + (email ? ["email"] : [])
    }

    public static func statusAfterSend(_ via: [String]) -> String {
        via.contains("app") ? "queued" : via.contains("email") ? "emailed" : "queued"
    }

    public static func statusText(_ m: ClinicMessage) -> String {
        switch m.status {
        case "queued": return tr("⏳ kézbesítésre vár")
        case "emailed": return tr("✉️ e-mailben elküldve")
        case "delivered": return tr("✓ kézbesítve")
        case "read": return tr("✓✓ elolvasva")
        default: return ""
        }
    }

    /// Upcoming appointments (confirmed or offered), soonest first.
    public static func upcoming(_ list: [Appointment], profileId: String, now: Date) -> [Appointment] {
        list.filter { $0.profileId == profileId && ($0.status == "confirmed" || $0.status == "offered") }
            .compactMap { a in startOf(a).flatMap { $0 > now ? (a, $0) : nil } }
            .sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Local reminders for confirmed appointments that are still ahead: (time, text).
    public static func reminders(_ list: [Appointment], now: Date) -> [(Date, String)] {
        list.filter { $0.status == "confirmed" }.flatMap { a -> [(Date, String)] in
            guard let start = startOf(a) else { return [] }
            return a.remindersMin.map { m in (start.addingTimeInterval(-Double(m) * 60), reminderText(a, minutesBefore: m, start: start)) }
        }.filter { $0.0 > now }.sorted { $0.0 < $1.0 }
    }

    public static func reminderText(_ a: Appointment, minutesBefore: Int, start: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: start)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let place = a.clinicName.map { " – " + $0 } ?? ""
        return minutesBefore >= 12 * 60 ? tr("📅 Holnap {0}-kor fogorvos{1}.", time, place)
            : tr("📅 {0}-kor fogorvos{1}. Ne felejts el fogat mosni előtte!", time, place)
    }

    public static func when(_ a: Appointment) -> String {
        guard let t = startOf(a) else { return a.start }
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: t)
        return String(format: "%d.%02d.%02d. %02d:%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    public static func title(_ a: Appointment) -> String { tr("Fogorvos: {0}", VisitReasons.title(a.reason)) }
    public static func acceptText(_ a: Appointment) -> String { tr("✅ Elfogadom az időpontot: {0}", when(a)) }
    public static func declineText(_ a: Appointment) -> String { tr("❌ Ez az időpont nem jó nekem: {0}. Kérek másikat.", when(a)) }

    /// An appointment offer from the clinic (QR, link, or later the DentHub messenger):
    /// `denthub://appt?d=<base64url JSON>` with start ("2026-11-10T10:30"), durationMin, doctor,
    /// clinicName, address, reason, note.
    public static func parseOffer(_ text: String, profileId: String) -> Appointment? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("denthub://appt?d=") else { return nil }
        var b64 = String(t.dropFirst("denthub://appt?d=".count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.hasSuffix("=") { b64.removeLast() }
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64), var a = try? JSONDecoder().decode(Appointment.self, from: data),
              startOf(a) != nil, (5...480).contains(a.durationMin) else { return nil }
        a.profileId = profileId
        a.status = "offered"
        a.calendarAdded = false
        return a
    }

    public static func offerCode(_ a: Appointment) -> String {
        let data = (try? JSONEncoder().encode(a)) ?? Data()
        return "denthub://appt?d=" + data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
