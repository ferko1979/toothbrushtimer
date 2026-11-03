import XCTest
@testable import BrushCore

final class WatchHandTests: XCTestCase {
    func testPlacementFromHands() {
        let same = watchListening(brushHand: "right", watchWrist: "right")
        XCTAssertTrue(same.sameHand && same.useMotion)
        XCTAssertEqual(same.nearGateDb, 14)
        let other = watchListening(brushHand: "right", watchWrist: "left")
        XCTAssertFalse(other.sameHand || other.useMotion)
        XCTAssertEqual(other.nearGateDb, 8)
    }

    func testStrokeRhythmScoresHigh() {
        let m = MotionRhythm()
        for i in 0..<150 {
            let v = 0.15 * sin(2 * Double.pi * 4 * Double(i) / 50)
            m.add(v * 0.6, v * 0.8, 0)
        }
        XCTAssertGreaterThan(m.score(), 0.8)
    }

    func testStillnessAndSlowMovesScoreLow() {
        let still = MotionRhythm()
        for _ in 0..<150 { still.add(0, 0, 0) }
        XCTAssertEqual(still.score(), 0)
        let slow = MotionRhythm()
        for i in 0..<150 { slow.add(0.3 * sin(2 * Double.pi * Double(i) / 50), 0, 0) }
        XCTAssertLessThan(slow.score(), 0.1)
        XCTAssertEqual(MotionRhythm().score(), 0)
    }
}

final class SideBalanceTests: XCTestCase {
    func testCalibratesOnTheFirstQuarter() {
        let b = SideBalance()
        var t = 0.0
        for _ in 0..<1500 { b.add(gx: 0.6, dt: 0.02, brushing: true, elapsedS: t); t += 0.02 }
        for _ in 0..<500 { b.add(gx: -0.6, dt: 0.02, brushing: true, elapsedS: t); t += 0.02 }
        XCTAssertEqual(b.result()?.right, 75)
        XCTAssertEqual(b.result()?.left, 25)
        XCTAssertTrue(b.note()?.contains("bal") == true)
        let none = SideBalance()
        for _ in 0..<3000 { none.add(gx: 0, dt: 0.02, brushing: true, elapsedS: 0) }
        XCTAssertNil(none.result())
    }
}
