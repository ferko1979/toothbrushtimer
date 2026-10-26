import XCTest
@testable import BrushCore

final class LogicTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return c
    }()
    lazy var today: Date = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 12))!

    func rec(_ dayOffset: Int, _ hour: Int, _ dur: Double = 125, water: Double = 0, minute: Int = 0) -> BrushRecord {
        let d = cal.date(byAdding: .day, value: -dayOffset, to: cal.startOfDay(for: today))!
        let t = cal.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
        return BrushRecord(profileId: "me", start: t, durationS: dur, waterRunningS: water)
    }

    func testSessionWaterCueBrushRinse() {
        let det = SessionDetector()
        var t = 0.0
        func feed(_ secs: Double, _ w: Double, _ b: Double, _ s: Double) {
            for _ in 0..<Int(secs / 0.5) { det.update(t: t + 0.25, water: w, brush: b, sonic: s, dt: 0.5); t += 0.5 }
        }
        feed(3, 0, 0, 0); feed(4, 1, 0, 0); feed(50, 0, 1, 0); feed(10, 1, 0, 0); feed(10, 0, 0, 0)
        let s = det.finish()
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].start, 7, accuracy: 0.6)
        XCTAssertEqual(s[0].end, 57, accuracy: 0.6)
        XCTAssertFalse(s[0].wastedWater)
    }

    func testSessionTapRunningIsWaste() {
        let det = SessionDetector()
        var t = 0.0
        func feed(_ secs: Double, _ w: Double, _ b: Double) {
            for _ in 0..<Int(secs / 0.5) { det.update(t: t + 0.25, water: w, brush: b, sonic: 0, dt: 0.5); t += 0.5 }
        }
        feed(3, 0, 0); feed(4, 1, 0); feed(50, 1, 1); feed(10, 1, 0); feed(20, 0, 0)
        let s = det.finish()
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].wastedWater)
        XCTAssertTrue(det.events.contains { $0.1 == .wasteIconOn })
    }

    func testCues() {
        XCTAssertEqual(cueSchedule(targetS: 120).map(\.atS), [0, 30, 60, 90, 120])
        let tr = CueTracker(targetS: 120)
        XCTAssertEqual(tr.update(elapsedS: 0).map(\.kind), [.start])
        XCTAssertEqual(tr.update(elapsedS: 65).map(\.atS), [30, 60])
        XCTAssertEqual(brushProgress(elapsedS: 75, targetS: 120).quadrant, 3)
    }

    func testCoachAndAchievements() {
        let coach = Coach(calendar: cal)
        let g = Goals()
        XCTAssertTrue(coach.sessionFeedback(durationS: 125, goals: g).contains("elérted"))
        XCTAssertTrue(coach.sessionFeedback(durationS: 40, goals: g).contains("80 másodperc hiányzott"))
        let records = (0..<7).flatMap { d in [rec(d, 7), rec(d, 21)] }
        XCTAssertEqual(coach.perfectStreak(records, goals: g, today: today), 7)
        let got = coach.earnedAchievements(records, goals: g, today: today)
        XCTAssertTrue(got.isSuperset(of: ["first_brush", "goal_reached", "perfect_day", "streak_7", "water_saver_10"]))
        XCTAssertFalse(got.contains("streak_30"))
    }

    func testWaterReport() {
        let r = WaterReport(seconds: 60, locale: .hu)
        XCTAssertEqual(r.litres, 8, accuracy: 1e-9)
        XCTAssertEqual(r.glasses, 32, accuracy: 1e-9)
        XCTAssertEqual(WaterReport(seconds: 60, locale: .us).gallons, 2.2, accuracy: 1e-9)
        XCTAssertTrue(waterMessage(brushingS: 60, waterRunningS: 50, locale: .hu).wasted)
        XCTAssertEqual(Formatting.hu(1234.56), "1 234,6")
    }

    func testReminderPlan() {
        let p = ReminderPlanner(calendar: cal)
        let morning = cal.date(bySettingHour: 6, minute: 0, second: 0, of: today)!
        let plan = p.plan(now: morning, records: [], goals: Goals(), settings: ReminderSettings(), days: 1)
        XCTAssertEqual(plan.map(\.key), ["morning", "morning_followup1", "bedtime", "bedtime_followup1"])
        let bedtime = plan.first { $0.key == "bedtime" }!.fireDate
        XCTAssertEqual(cal.component(.hour, from: bedtime), 22)
        XCTAssertEqual(cal.component(.minute, from: bedtime), 15)
        let afterMorning = p.plan(now: morning, records: [rec(0, 7)], goals: Goals(), settings: ReminderSettings(), days: 1)
        XCTAssertEqual(afterMorning.map(\.key), ["bedtime", "bedtime_followup1"])
    }

    func testListeningPolicy() {
        let p = ListeningPolicy()
        p.appOpened(t: 0)
        var t = 0.0
        while t < 3 { p.motion(t: t, gx: 0, gy: 0, gz: -1); t += 0.1 }
        XCTAssertTrue(p.placed)
        p.appBackgrounded(t: 3)
        XCTAssertTrue(p.listening)
        p.motion(t: 4, gx: 0.3, gy: -0.8, gz: -0.5)
        XCTAssertFalse(p.listening)
        let armed = ListeningPolicy()
        armed.appOpened(t: 0, fromNotification: true)
        XCTAssertEqual(armed.sessionConfig.fallbackS, 3)
    }

    func testOnboarding() throws {
        let f = OnboardingFlow(adultName: "Anna")
        for a in ["family", "Bence", "4"] { try f.answer(a) }
        XCTAssertEqual(f.nextQuestion()?.id, "child_reads")
        XCTAssertEqual(f.nextQuestion()?.defaultValue, "no")
        try f.answer("no")
        XCTAssertEqual(f.nextQuestion()?.pictureOnly, true)
        try f.answer("dino")
        try f.answer("yes")
        try f.answer("Lili"); try f.answer("10")
        XCTAssertEqual(f.nextQuestion()?.id, "child_avatar")
        XCTAssertFalse(f.nextQuestion()!.options.contains { $0.0 == "dino" })
        try f.answer("unicorn"); try f.answer("no")
        XCTAssertNil(f.nextQuestion())
        let ps = f.profiles()
        XCTAssertEqual(ps.map(\.name), ["Anna", "Bence", "Lili"])
        XCTAssertFalse(ps[1].canRead)
        XCTAssertTrue(feedback(for: ps[1], durationS: 130).speak)
        XCTAssertThrowsError(try OnboardingFlow().answer("maybe"))
    }

    func testSettingsDefaultsAndDecodingOldFile() throws {
        var s = AppSettings()
        XCTAssertTrue(s.isOn("quadrant_cues"))
        XCTAssertFalse(s.isOn("floss_tracking"))
        XCTAssertFalse(s.isOn("watch_complication", platform: .ios))
        s.set("floss_tracking", true)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), s)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"enabled":{"floss_tracking":true}}"#.utf8))
        XCTAssertTrue(old.isOn("floss_tracking"))
        XCTAssertTrue(old.isOn("quadrant_cues"))
    }

    func testHabitsAndBrushHead() {
        let g = Goals()
        let noEvening = (0..<14).map { rec($0, 7) }
        XCTAssertTrue(detectHabits(noEvening, goals: g, today: today, calendar: cal).contains { $0.id == "evening_skipped" })
        let good = (0..<14).flatMap { d in [rec(d, 7), rec(d, 21)] }
        XCTAssertTrue(detectHabits(good, goals: g, today: today, calendar: cal).isEmpty)
        let installed = cal.date(byAdding: .day, value: -92, to: today)!
        XCTAssertTrue(brushHeadStatus(installed: installed, electric: true, records: good, today: today, calendar: cal).due)
    }

    func testCalibration() throws {
        var c = BrushCalibration()
        for f in [255.9, 256.8, 255.0] { c.addSession(f0Hz: f) }
        XCTAssertEqual(c.brushF0 ?? 0, 255.9, accuracy: 1e-9)
        XCTAssertEqual(c.sonicConfig().bandLowHz, 245.9, accuracy: 1e-9)
        XCTAssertEqual(try tapFlowFromMeasurement(litres: 1, seconds: 7.5), 8, accuracy: 1e-9)
        XCTAssertThrowsError(try tapFlowFromMeasurement(litres: 1, seconds: 0.5))
    }
}
