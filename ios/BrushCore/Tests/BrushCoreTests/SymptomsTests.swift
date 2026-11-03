import XCTest
@testable import BrushCore

/// Mirrors android/brushcore/src/test/kotlin/hu/fogmosas/core/SymptomsTest.kt.
final class SymptomsTests: XCTestCase {
    private func flow(_ steps: [[String]], recent: Int = 0) throws -> SymptomFlow {
        let f = SymptomFlow(recentSameKind: { _ in recent })
        for s in steps { try f.answer(s) }
        return f
    }

    private func a(_ pairs: [(String, [String])]) -> [SymptomAnswer] { pairs.map { SymptomAnswer(question: $0.0, options: $0.1) } }

    func testBleedingAsksWhereThenSelfCare() throws {
        let f = SymptomFlow()
        XCTAssertEqual(f.next()?.id, "kind")
        try f.answer(["bleeding"])
        var asked: [String] = []
        while let q = f.next() { asked.append(q.id); try f.answer([q.options[0].id]) }
        XCTAssertEqual(asked, ["jaw", "side", "bleed_when", "bleed_amount", "since"])
        let r = f.result()
        XCTAssertEqual(r.level, .selfCare)
        XCTAssertFalse(r.suggestBooking)
        XCTAssertFalse(r.advice.isEmpty)
        XCTAssertEqual(f.progress, 1)
    }

    func testSwellingWithBreathingTroubleIsAnEmergency() throws {
        let f = try flow([["pain"], ["lower"], ["right"], ["back"], ["46", "47"], ["moderate"], ["chewing"], ["days"], ["yes"]])
        XCTAssertEqual(f.next()?.id, "fever")
        try f.answer(["no"]); try f.answer(["yes"])
        XCTAssertNil(f.next())
        let r = f.result()
        XCTAssertEqual(r.level, .emergency)
        XCTAssertTrue(r.suggestMessage && r.suggestBooking)
        XCTAssertNotNil(r.photo)
    }

    func testNightPainIsUrgentAndMultiChoiceKept() throws {
        let f = try flow([["pain"], ["upper"], ["left"], ["back"], ["unsure"], ["mild"], ["hot", "night"], ["today"], ["no"]])
        XCTAssertEqual(f.answers.first { $0.question == "trigger" }?.options, ["hot", "night"])
        XCTAssertEqual(f.result().level, .urgent)
    }

    func testKnockedOutPermanentToothIsAnEmergencyBabyToothIsNot() {
        XCTAssertEqual(triage("knocked", a([("tooth_type", ["permanent"])])).level, .emergency)
        XCTAssertEqual(triage("knocked", a([("tooth_type", ["baby"])])).level, .soon)
    }

    func testBiteInjurySelfCareUnlessBleedingGoesOn() {
        let small = triage("injury", a([("injury_cause", ["bite"]), ("wound_bleed", ["stopped"]), ("wound_deep", ["no"]), ("pain", ["mild"])]))
        XCTAssertEqual(small.level, .selfCare)
        XCTAssertNotNil(small.photo)
        XCTAssertFalse(small.suggestMessage)
        XCTAssertEqual(triage("injury", a([("injury_cause", ["bite"]), ("wound_bleed", ["not_stopping"])])).level, .urgent)
    }

    func testRecurringComplaintEscalates() {
        let x = a([("bleed_amount", ["drops"]), ("since", ["today"])])
        XCTAssertEqual(triage("bleeding", x, recentSameKind: 1).level, .selfCare)
        XCTAssertEqual(triage("bleeding", x, recentSameKind: 2).level, .soon)
    }

    func testBackAndInvalidAnswers() throws {
        let f = try flow([["stuck"], ["upper"]])
        XCTAssertTrue(f.back()); XCTAssertEqual(f.next()?.id, "jaw")
        XCTAssertTrue(f.back()); XCTAssertEqual(f.next()?.id, "kind")
        XCTAssertFalse(f.back())
        XCTAssertThrowsError(try f.answer(["nope"]))
    }

    func testSummaryEmailAndVisit() throws {
        let f = try flow([["chipped"], ["tooth"], ["upper"], ["front"], ["front"], ["11"], ["none"], ["yes"], ["yes"]])
        let r = f.report(profileId: "me", now: Date(timeIntervalSince1970: 1_700_000_000), photos: ["a.jpg"], note: "Diótörés")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let lines = symptomSummary(r, calendar: utc)
        XCTAssertTrue(lines[0].contains("🦷"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("Fogsor: Felső") })
        XCTAssertTrue(lines.contains { $0.contains("Diótörés") })
        XCTAssertTrue(lines.contains { $0.hasPrefix("Fog (FDI): 11 (jobb felső középső metszőfog)") })
        XCTAssertEqual(r.level, TriageLevel.soon.rawValue)
        let v = VisitRequest(profileId: "me", created: Date(), reason: "broken", timing: "week", dayParts: ["morning"], symptomId: r.id)
        let mail = clinicEmail(patientName: "Kiss Anna", symptom: r, visit: v)
        XCTAssertTrue(mail.subject.contains("Kiss Anna"))
        XCTAssertTrue(mail.body.contains("Letört fog vagy tömés") && mail.body.contains("Délelőtt") && mail.body.contains("Fotók: 1 db"))
        XCTAssertEqual(recentSymptomCount([r], profileId: "me", kind: "chipped", now: r.date.addingTimeInterval(1)), 1)
        XCTAssertEqual(recentSymptomCount([r], profileId: "me", kind: "chipped", now: r.date.addingTimeInterval(31 * 86_400)), 0)
    }

    func testClinicLinkRoundTripAndBooking() {
        let c = ClinicInfo(id: "c1", name: "Mosoly Fogászat", email: "info@example.com", bookingUrl: "https://example.com/book")
        XCTAssertEqual(parseClinicLink(clinicLinkCode(c)), c)
        let payload = clinicLinkCode(c).components(separatedBy: "d=")[1]
        XCTAssertEqual(parseClinicLink("https://denthub.example/link#" + payload), c)
        XCTAssertNil(parseClinicLink("hello"))
        XCTAssertNil(parseClinicLink("denthub://link?d=!!!"))
        let v = VisitRequest(profileId: "me", created: Date(), reason: "checkup", timing: "asap")
        XCTAssertEqual(bookingLink(c, v), "https://example.com/book?reason=checkup&timing=asap")
        var noBooking = c
        noBooking.bookingUrl = nil
        XCTAssertNil(bookingLink(noBooking, v))
    }

    func testAnomalyAndIntake() {
        let usual = Array(repeating: 120.0, count: 6)
        XCTAssertNotNil(brushingAnomaly(durationS: 50, recentDurations: usual, todayCount: 1, perDay: 2))
        XCTAssertNotNil(brushingAnomaly(durationS: 220, recentDurations: usual, todayCount: 1, perDay: 2))
        XCTAssertNil(brushingAnomaly(durationS: 118, recentDurations: usual, todayCount: 1, perDay: 2))
        XCTAssertNotNil(brushingAnomaly(durationS: 118, recentDurations: usual, todayCount: 4, perDay: 2))
        XCTAssertNil(brushingAnomaly(durationS: 30, recentDurations: [120], todayCount: 1, perDay: 2))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        XCTAssertEqual(DentistIntake.date("lt6m", today: today, calendar: cal), cal.date(from: DateComponents(year: 2026, month: 8, day: 3)))
        XCTAssertNil(DentistIntake.date("unknown", today: today))
    }
}
