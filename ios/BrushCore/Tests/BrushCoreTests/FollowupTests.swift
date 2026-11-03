import XCTest
@testable import BrushCore

/// Mirrors android/brushcore/src/test/kotlin/hu/fogmosas/core/FollowupTest.kt.
final class FollowupTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let day = 86_400.0
    private var t0: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9))! }
    private var r: SymptomReport { SymptomReport(profileId: "me", date: t0, kind: "pain", answers: [], level: "soon") }

    func testToothMapAndNames() throws {
        XCTAssertEqual(ToothMap.all.count, 32)
        XCTAssertEqual(ToothMap.all.first, "18")
        XCTAssertEqual(ToothMap.name("46"), "46 (jobb alsó első nagyőrlő)")
        let f = SymptomFlow()
        for a in ["pain", "lower", "right", "back"] { try f.answer([a]) }
        XCTAssertEqual(f.next()?.id, "teeth")
        XCTAssertEqual(f.next()?.multi, true)
        let kid = SymptomFlow(child: true)
        for a in ["pain", "lower", "right", "back"] { try kid.answer([a]) }
        XCTAssertEqual(kid.next()?.id, "pain")
    }

    func testFollowUpDays() {
        let r = self.r
        XCTAssertNil(followUpDue(r, [], now: t0.addingTimeInterval(3600), calendar: cal))
        XCTAssertEqual(followUpDue(r, [], now: t0.addingTimeInterval(day), calendar: cal), 1)
        let ups = [SymptomFollowUp(reportId: r.id, day: 1, answer: "same", date: t0.addingTimeInterval(day))]
        XCTAssertNil(followUpDue(r, ups, now: t0.addingTimeInterval(2 * day), calendar: cal))
        XCTAssertEqual(followUpDue(r, ups, now: t0.addingTimeInterval(4 * day), calendar: cal), 3)
        XCTAssertEqual(followUpDue(r, ups, now: t0.addingTimeInterval(8 * day), calendar: cal), 7)
        XCTAssertNil(followUpDue(r, ups + [SymptomFollowUp(reportId: r.id, day: 3, answer: "gone", date: t0)], now: t0.addingTimeInterval(8 * day), calendar: cal))
        XCTAssertNil(followUpDue(r, ups, now: t0.addingTimeInterval(20 * day), calendar: cal))
        XCTAssertTrue(followUpAdvice(r, answer: "worse", day: 1).contact)
        XCTAssertTrue(followUpAdvice(r, answer: "same", day: 7).contact)
        XCTAssertFalse(followUpAdvice(r, answer: "better", day: 3).contact)
        let plan = plannedFollowUps([r], ups, now: t0.addingTimeInterval(3600), calendar: cal)
        XCTAssertEqual(plan.map(\.0), [cal.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 18))!,
                                       cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 18))!])
    }

    func testCareTasks() {
        let start = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        let t = CareTask(profileId: "me", title: "Szájöblítés", times: ["08:00", "20:00"], start: start, days: 3)
        XCTAssertTrue(t.activeOn(start.addingTimeInterval(2 * day), calendar: cal))
        XCTAssertFalse(t.activeOn(start.addingTimeInterval(3 * day), calendar: cal))
        let done = t.toggled(start, "08:00", calendar: cal)
        XCTAssertTrue(done.isDone(start, "08:00", calendar: cal))
        XCTAssertTrue(done.progress(today: start, calendar: cal) == (1, 2))
        XCTAssertTrue(done.progress(today: start.addingTimeInterval(6 * day), calendar: cal) == (1, 6))
        let plan = plannedCareTasks([done], now: start.addingTimeInterval(9 * 3600), calendar: cal)
        XCTAssertEqual(plan.count, 5)
        XCTAssertEqual(plan.first?.0, start.addingTimeInterval(20 * 3600))
        XCTAssertEqual(CareTaskPresets.times(3), ["08:00", "14:00", "20:00"])
    }

    func testMotorTrendAndPhotos() {
        let today = cal.date(from: DateComponents(year: 2026, month: 11, day: 3))!
        func rec(_ daysAgo: Int, _ f0: Double) -> BrushRecord {
            BrushRecord(profileId: "me", start: today.addingTimeInterval(-Double(daysAgo) * day + 8 * 3600), durationS: 120, brushF0: f0)
        }
        let ok = motorTrend((0...30).map { rec($0, 256) }, today: today, calendar: cal)
        XCTAssertGreaterThanOrEqual(ok.weeks.count, 4)
        XCTAssertEqual(ok.changePct ?? 99, 0, accuracy: 0.01)
        let slowing = (8...30).map { rec($0, 256) } + (0...6).map { rec($0, 248) }
        XCTAssertLessThan(motorTrend(slowing, today: today, calendar: cal).changePct ?? 0, -2)
        XCTAssertNil(motorTrend([rec(0, 256)], today: today, calendar: cal).changePct)
        var a = r; a.photos = ["1.jpg"]
        var b = r; b.date = t0.addingTimeInterval(day); b.photos = ["2.jpg"]
        XCTAssertEqual(photoTimeline([b, a, r], profileId: "me", kind: "pain").map(\.id), [a.id, b.id])
    }
}
