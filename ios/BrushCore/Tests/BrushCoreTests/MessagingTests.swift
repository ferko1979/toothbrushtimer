import XCTest
@testable import BrushCore

final class MessagingTests: XCTestCase {
    let clinic = ClinicInfo(id: "c1", name: "Mosoly", email: "info@mosoly.hu", messaging: true)

    func testChannelsFollowBothSides() {
        XCTAssertEqual(Messaging.channels(clinic: clinic, appToApp: true, alsoEmail: false), ["app"])
        XCTAssertEqual(Messaging.channels(clinic: clinic, appToApp: true, alsoEmail: true), ["app", "email"])
        XCTAssertEqual(Messaging.channels(clinic: clinic, appToApp: false, alsoEmail: false), ["email"])
        var noApp = clinic
        noApp.messaging = nil
        XCTAssertEqual(Messaging.channels(clinic: noApp, appToApp: true, alsoEmail: false), ["email"])
        XCTAssertEqual(Messaging.statusAfterSend(["email"]), "emailed")
    }

    func testThreadAndUnread() {
        let m = [ClinicMessage(profileId: "me", date: Date(timeIntervalSince1970: 2), text: "b", fromPatient: false, status: "received"),
                 ClinicMessage(profileId: "me", date: Date(timeIntervalSince1970: 1), text: "a")]
        XCTAssertEqual(Messaging.thread(m, profileId: "me").map(\.text), ["a", "b"])
        XCTAssertEqual(Messaging.unread(m, profileId: "me"), 1)
        // Older stored clinic data without the new keys still decodes.
        let old = #"{"id":"c","name":"X"}"#
        XCTAssertEqual(try JSONDecoder().decode(ClinicInfo.self, from: Data(old.utf8)).allowsMessaging, false)
    }

    func testOfferLinkAndReminders() throws {
        let a = Appointment(profileId: "x", start: "2026-11-10T10:30", reason: "pain", clinicName: "Mosoly", doctor: "Dr. Kiss")
        let got = try XCTUnwrap(Messaging.parseOffer(Messaging.offerCode(a), profileId: "me"))
        XCTAssertEqual(got.status, "offered")
        XCTAssertEqual(got.profileId, "me")
        let raw = "denthub://appt?d=" + Data(#"{"start":"2026-11-10T09:00"}"#.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(Messaging.parseOffer(raw, profileId: "me")?.durationMin, 30)
        let now = Messaging.stamp.date(from: "2026-11-09T09:00")!
        XCTAssertTrue(Messaging.reminders([got], now: now).isEmpty)
        var ok = got
        ok.status = "confirmed"
        XCTAssertEqual(Messaging.reminders([ok], now: now).map { Messaging.format($0.0) }, ["2026-11-09T10:30", "2026-11-10T08:30"])
    }
}
