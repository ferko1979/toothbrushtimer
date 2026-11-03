import XCTest
@testable import BrushCore

/// Mirrors android/brushcore/src/test/kotlin/hu/fogmosas/core/SessionCuesTest.kt.
final class SessionCuesTests: XCTestCase {
    private var cfg: SessionConfig {
        var c = SessionConfig()
        c.holdUntilS = 120
        c.sonicSuppressesWater = true
        c.runHysteresis = true
        c.quietWaterRinseS = 3.5
        c.wetCue = true
        c.sonicStopWatch = true
        return c
    }

    /// Steps of 0.5 s: (seconds, water, brush, sonic, rmsDb, f0).
    @discardableResult
    private func run(_ d: SessionDetector, _ segs: [[Double]], from t0: Double = 0) -> Double {
        var t = t0
        for s in segs {
            for _ in 0..<Int(s[0] / 0.5) {
                t += 0.5
                d.update(t: t, water: s[1], brush: s[2], sonic: s[3], dt: 0.5, rmsDb: s[4], sonicF0: s[5])
            }
        }
        return t
    }

    func testWettingArmsAndBrushingStartsAfterToothpaste() {
        let d = SessionDetector(cfg: cfg)
        run(d, [[3, 0, 0, 0, -70, 0], [1.5, 0, 0.8, 0, -56, 0], [1.5, 0, 0.8, 0, -70, 0],
                [6, 0, 0.2, 0, -70, 0], [40, 0, 0.9, 1, -59, 256]])
        XCTAssertTrue(d.events.contains { $0.1 == .brushWet })
        XCTAssertEqual(d.sessions.count, 1)
        let s = d.sessions[0]
        XCTAssertEqual(s.cue, "wet")
        XCTAssertTrue(s.wetBefore)
        XCTAssertTrue((11.5...12.5).contains(s.start), "start \(s.start)")
    }

    func testQuietWaterWhileScrubbingIsNotARinseButTheLoudTapIs() {
        let d = SessionDetector(cfg: cfg)
        let t = run(d, [[130, 0, 0.9, 1, -59, 256], [5, 0, 0.5, 0, -60, 0], [2, 0.9, 0, 0, -59.5, 0], [5, 0, 0.1, 0, -61, 0]])
        XCTAssertEqual(d.state, .brushing)
        let s = d.sessions[0]
        XCTAssertNotNil(s.sonicStoppedAt)
        XCTAssertGreaterThanOrEqual(s.manualAfterSonicS, 2)
        XCTAssertEqual(brushPowerNotes(s, history: []).count, 1)
        run(d, [[3, 0.9, 0, 0, -47, 0], [6, 0, 0, 0, -65, 0]], from: t)
        XCTAssertEqual(d.sessions[0].endReason, "rinse")
        XCTAssertTrue((141.5...142.5).contains(d.sessions[0].end), "end \(d.sessions[0].end)")
    }

    func testSlowerMotorThanUsualIsReported() {
        let d = SessionDetector(cfg: cfg)
        run(d, [[60, 0, 0.9, 1, -59, 248]])
        let s = d.current!
        XCTAssertNil(s.sonicStoppedAt)
        XCTAssertEqual(brushPowerNotes(s, history: [256, 255.9, 256.1]).count, 1)
        XCTAssertTrue(brushPowerNotes(s, history: [248, 248.5, 247.8]).isEmpty)
    }
}
