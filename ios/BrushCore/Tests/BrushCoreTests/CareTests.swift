import XCTest
@testable import BrushCore
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Mirrors android/brushcore/src/test/kotlin/hu/fogmosas/core/CareTest.kt.
final class CareTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return c
    }()
    lazy var today: Date = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
    lazy var coach = Coach(calendar: cal)

    func at(_ daysAgo: Int, _ hour: Int = 21) -> Date {
        let d = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: today))!
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: d)!
    }
    func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }

    func e(_ daysAgo: Int, floss: Bool = false, bleed: Bool = false, sens: Int = 0, paste: String? = nil) -> CareEntry {
        CareEntry(profileId: "me", date: at(daysAgo), sensitivity: sens, bleeding: bleed, floss: floss, toothpaste: paste)
    }

    func testCountsAndStreaks() {
        let es = [e(0, floss: true), e(1, floss: true), e(1, floss: true), e(2, floss: true), e(4, floss: true)]
        XCTAssertEqual(careStreak(es, .floss, today: today, calendar: cal), 3)
        XCTAssertEqual(careCount(es, .floss, today: today, days: 7, calendar: cal), 4)
        XCTAssertTrue(careDoneToday(es, .floss, today: today, calendar: cal))
        XCTAssertEqual(careStreak(Array(es.dropFirst()), .floss, today: today, calendar: cal), 2)
    }

    func testPersistentBleedingAlert() {
        let es = [0, 2, 5, 9].map { e($0, bleed: true) }
        let ins = careInsights(es, today: today, calendar: cal)
        XCTAssertEqual(ins.first?.id, "bleeding_persistent")
        XCTAssertEqual(ins.first?.alert, true)
        XCTAssertFalse(careInsights(Array(es.prefix(3)), today: today, calendar: cal).contains { $0.id == "bleeding_persistent" })
    }

    func testFlossHelpsInsight() {
        let before = (14...27).map { e($0, bleed: $0 % 2 == 0) }
        let now = (0...13).map { e($0, floss: true, bleed: $0 == 3) }
        let ids = careInsights(before + now, today: today, calendar: cal).map(\.id)
        XCTAssertTrue(ids.contains("floss_helps"), "\(ids)")
        XCTAssertFalse(ids.contains("floss_rare"))
    }

    func testToothpasteInsights() {
        let before = (14...27).map { e($0, sens: 1, paste: "fluoride") }
        let now = (0...13).map { e($0, sens: $0 < 2 ? 1 : 0, paste: "sensitive") }
        XCTAssertTrue(careInsights(before + now, today: today, calendar: cal).contains { $0.id == "toothpaste_helps" })
        let noSensitive = (0...13).map { e($0, sens: 1, paste: "whitening") }
        XCTAssertTrue(careInsights(noSensitive, today: today, calendar: cal).contains { $0.id == "toothpaste_try" })
    }

    func testDentistReminders() {
        let s = dentistStatus(lastCheckup: day(2026, 3, 1), lastCleaning: day(2026, 1, 15), today: today, calendar: cal)
        XCTAssertTrue(s.checkupOverdue)
        XCTAssertFalse(s.cleaningOverdue)
        XCTAssertEqual(s.cleaningDue, day(2027, 1, 15))
        XCTAssertEqual(nextDentistReminder(lastCheckup: day(2026, 3, 1), lastCleaning: nil, today: today, calendar: cal), day(2026, 11, 9))
        XCTAssertEqual(nextDentistReminder(lastCheckup: day(2026, 11, 1), lastCleaning: nil, today: today, calendar: cal), day(2027, 5, 1))
        XCTAssertNil(nextDentistReminder(lastCheckup: nil, lastCleaning: nil, today: today, calendar: cal))
    }

    func testRewardProgress() {
        let rs = (0...4).flatMap { d in [9, 20].map { h in BrushRecord(profileId: "k", start: at(d, h), durationS: 125) } }
        let p = rewardProgress(rs, goals: Goals(), reward: "Mozi", need: 3, since: nil, coach: coach)!
        XCTAssertEqual(p.have, 3); XCTAssertTrue(p.done)
        XCTAssertEqual(rewardProgress(rs, goals: Goals(), reward: "Mozi", need: 14, since: at(1, 0), coach: coach)!.have, 2)
        XCTAssertNil(rewardProgress(rs, goals: Goals(), reward: "", need: 3, since: nil, coach: coach))
    }

    func testDentistReportContents() {
        var p = Profile(id: "me", name: "Anna")
        p.orthodontic = true
        p.lastCheckup = day(2026, 5, 10)
        let rs = (0...9).map { BrushRecord(profileId: "me", start: at($0, 21), durationS: 100 + Double($0) * 5) }
        let es = [e(0, floss: true, paste: "sensitive"), e(1, bleed: true, sens: 2)]
        let t = dentistReport(profile: p, records: rs, entries: es, today: today, days: 30, coach: coach).text
        for s in ["Fogmosások: 10", "Fogselyem: 1 napon", "Ínyvérzés: 1 napon", "erős: 1", "Érzékeny fogra (1 nap)", "Fogszabályzó: igen", "2026.05.10."] {
            XCTAssertTrue(t.contains(s), "missing \(s) in \(t)")
        }
    }

    func testSnapshot() throws {
        let p = Profile(id: "me", name: "Anna")
        let rs = [BrushRecord(profileId: "me", start: at(0), durationS: 130)]
        let wp = WebLink.profileSnapshot(p, records: rs, care: [e(0, floss: true)], today: today, coach: coach)
        XCTAssertEqual(wp.days.count, 1)
        XCTAssertEqual(wp.days[0].d, "2026-11-02")
        XCTAssertEqual(wp.days[0].goalHits, 1)
        XCTAssertTrue(wp.days[0].floss)
        let js = try JSONSerialization.jsonObject(with: WebLink.snapshotJSON(WebLink.snapshot([wp], now: Date(timeIntervalSince1970: 0), locale: "hu"))) as! [String: Any]
        XCTAssertEqual(js["v"] as? Int, 1)
    }

    func testOldProfileJSONStillDecodes() throws {
        let old = #"{"id":"me","name":"Én","child":false,"goals":{"perDay":2,"targetS":120},"brushType":"manual","canRead":true,"brushHeadInstalled":0}"#
        let p = try JSONDecoder().decode(Profile.self, from: Data(old.utf8))
        XCTAssertEqual(p.name, "Én")
        XCTAssertFalse(p.orthodontic)
        XCTAssertEqual(p.rewardStickers, 14)
    }
}

final class WebLinkTests: XCTestCase {
    lazy var v: [String: String] = {
        let u = Bundle.module.url(forResource: "weblink_vector.json", withExtension: nil, subdirectory: "Golden")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: u)) as! [String: String]
    }()
    func b(_ k: String) -> Data { WebLink.unb64(v[k]!)! }

    func testParsesQr() {
        let p = WebLink.parse(v["qr"]!)
        XCTAssertEqual(p?.base, "https://fogmosas.example")
        XCTAssertEqual(p?.uploadURL.absoluteString, "https://fogmosas.example/api/relay/\(v["sid"]!)")
        XCTAssertEqual(p?.webPublicKey, b("webPublic"))
        XCTAssertEqual(WebLink.parse("https://x.hu/app/l#\(v["sid"]!).\(v["webPublic"]!)")?.base, "https://x.hu/app")
        XCTAssertNil(WebLink.parse("http://evil.example/l#\(v["sid"]!).\(v["webPublic"]!)"))
        XCTAssertNotNil(WebLink.parse("http://localhost:8080/l#\(v["sid"]!).\(v["webPublic"]!)"))
        XCTAssertNil(WebLink.parse("https://x.hu/l#short.\(v["webPublic"]!)"))
        XCTAssertNil(WebLink.parse("hello"))
    }

    #if canImport(CryptoKit)
    func testEnvelopeMatchesNode() throws {
        let priv = try P256.KeyAgreement.PrivateKey(rawRepresentation: b("phonePrivate"))
        XCTAssertEqual(priv.publicKey.x963Representation, b("phonePublic"))
        let env = try WebLink.seal(webPublicKey: b("webPublic"), sid: v["sid"]!, plaintext: Data(v["plaintext"]!.utf8),
                                   ephemeral: priv, nonce: b("nonce"))
        XCTAssertEqual(WebLink.b64(env), v["envelope"]!)
        let random = try WebLink.seal(webPublicKey: b("webPublic"), sid: v["sid"]!, plaintext: Data(v["plaintext"]!.utf8))
        XCTAssertEqual(random.count, 65 + 12 + Data(v["plaintext"]!.utf8).count + 16)
    }
    #endif
}

final class TourTests: XCTestCase {
    func testPages() {
        for pf in [Platform.ios, .android] {
            let ps = Tour.pages(platform: pf)
            XCTAssertEqual(ps.count, 11)
            XCTAssertFalse(ps.contains { $0.text.contains("{") || $0.title.isEmpty })
        }
        XCTAssertTrue(Tour.pages(platform: .ios).contains { $0.text.contains("Face ID") })
    }
}

final class I18nTests: XCTestCase {
    func testEnglishAndPlurals() {
        I18n.setLanguage("en")
        defer { I18n.setLanguage("hu") }
        XCTAssertEqual(tr("Fogselyem: {0} napon", 1), "Floss: 1 day")
        XCTAssertEqual(tr("Fogselyem: {0} napon", 3), "Floss: 3 days")
        XCTAssertEqual(Quadrant.names[0], "upper right")
        XCTAssertEqual(Formatting.hu(1234.5), "1,234.5")
        XCTAssertEqual(Feature.byId("care_checkin")?.title, "Symptom journal")
        XCTAssertTrue(Tour.pages(platform: .ios)[0].title.hasPrefix("Times"))
    }

    func testHungarianDefault() {
        I18n.setLanguage("hu")
        XCTAssertEqual(tr("Fogselyem: {0} napon", 3), "Fogselyem: 3 napon")
        XCTAssertEqual(Formatting.hu(1234.5), "1 234,5")
    }
}

final class HoldUntilGoalTests: XCTestCase {
    private func run(_ cfg: SessionConfig) -> [BrushingSession] {
        let det = SessionDetector(cfg: cfg)
        var t = 0.0
        func feed(_ secs: Double, _ w: Double, _ b: Double) {
            for _ in 0..<Int(secs / 0.5) { det.update(t: t + 0.25, water: w, brush: b, sonic: 0, dt: 0.5); t += 0.5 }
        }
        feed(2, 0, 0); feed(3, 1, 0); feed(30, 0, 1); feed(20, 0, 0); feed(60, 0, 1); feed(20, 0, 0)
        return det.finish()
    }

    func testDefaultStopsOnSilence() {
        let s = run(SessionConfig())
        XCTAssertEqual(s.first?.endReason, "quiet")
        XCTAssertLessThan(s.first?.durationS ?? 0, 40)
    }

    func testHoldUntilGoalKeepsGoing() {
        var c = SessionConfig()
        c.holdUntilS = 120
        let s = run(c)
        XCTAssertEqual(s.count, 1)
        XCTAssertGreaterThan(s.first?.durationS ?? 0, 100)
    }

    func testFeedbackTunesTolerance() {
        XCTAssertEqual(adjustedQuietExtra(0, reason: "too_early"), 10)
        XCTAssertEqual(adjustedQuietExtra(10, reason: "too_late"), 5)
    }
}

final class SonicHumTests: XCTestCase {
    private func run(_ cfg: SessionConfig) -> [BrushingSession] {
        let det = SessionDetector(cfg: cfg)
        var t = 0.0
        func feed(_ secs: Double, _ w: Double, _ b: Double, _ s: Double) {
            for _ in 0..<Int(secs / 0.5) { det.update(t: t + 0.25, water: w, brush: b, sonic: s, dt: 0.5); t += 0.5 }
        }
        feed(2, 0, 0, 0); feed(3, 1, 0, 0); feed(20, 0, 0.2, 0.9); feed(8, 0.9, 0.1, 0.9)
        feed(100, 0, 0.1, 0.9); feed(6, 1, 0, 0); feed(10, 0, 0, 0)
        return det.finish()
    }

    func testHumIgnoresWaterAndKeepsGoing() {
        var c = SessionConfig()
        c.holdUntilS = 120
        c.sonicSuppressesWater = true
        let s = run(c)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.first?.endReason, "rinse")
        XCTAssertGreaterThan(s.first?.durationS ?? 0, 120)
        XCTAssertLessThan(s.first?.waterRunningS ?? 99, 1)
    }
}

final class TestRecordingTests: XCTestCase {
    func testWritesReadableWavAndJson() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rec = try TestRecording(directory: dir, meta: ["platform": "test"])
        rec.append((0..<16000).map { Float(sin(Double($0) * 0.1) * 0.5) })
        rec.row(ScoreRow(t: 0.5, brush: 0.1, water: 0.9, sonic: 0, sonicF0: 0), state: "water", rmsDb: -30)
        rec.event(1.0, "water_start")
        let files = rec.finish(result: ["endReason": "user"])
        let wav = try WAVReader.read(files[0])
        XCTAssertEqual(wav.samples.count, 16000)
        let js = try JSONSerialization.jsonObject(with: Data(contentsOf: files[1])) as! [String: Any]
        XCTAssertEqual(js["format"] as? String, "denthub-brush-test-1")
        XCTAssertEqual(TestRecording.latest(in: dir).map(\.lastPathComponent), files.map(\.lastPathComponent))
        TestRecording.saveRemark("a víz az elején hiányzott", base: rec.base, in: dir)
        XCTAssertEqual(TestRecording.latest(in: dir).count, 3)
        #if canImport(CryptoKit)
        XCTAssertTrue(TestAccess.check(" fogteszt2026 "))
        XCTAssertFalse(TestAccess.check("fogteszt"))
        #endif
        let pend = TestAccess.pending(in: dir, uploaded: [])
        XCTAssertEqual(pend.count, 3)
        XCTAssertEqual(TestAccess.pending(in: dir, uploaded: Set(pend.prefix(2).map(TestAccess.key))).count, 1)
        TestRecording.prune(in: dir, maxBytes: 0)
        XCTAssertTrue(TestRecording.all(in: dir).isEmpty)
    }
}

final class BrushTypeTests: XCTestCase {
    func testPoweredAndDecoding() throws {
        XCTAssertFalse(BrushType.manual.powered)
        XCTAssertTrue(BrushType.oscillating.powered)
        XCTAssertEqual(try JSONDecoder().decode(BrushType.self, from: Data(#""oscillating""#.utf8)), .oscillating)
        XCTAssertEqual(SonicConfig.oscillating.bandLowHz, 60)
    }
}
