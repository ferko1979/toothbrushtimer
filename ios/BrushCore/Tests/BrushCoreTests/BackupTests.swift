import XCTest
@testable import BrushCore

/// Mirrors android/brushcore/src/test/kotlin/hu/fogmosas/core/BackupTest.kt (same Node-made vector).
final class BackupTests: XCTestCase {
    private let vector = "44484231000102030405060708090a0b0c0d0e0f000003e86465666768696a6b6c6d6e6f8d9c10eec0d74ea3083aa9e843b8cfa94dedff4ea5a6bfe7b6f5c3ac6c10"
    private func hex(_ s: String) -> Data {
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            d.append(UInt8(s[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    func testKnownVector() throws {
        let salt = Data((0..<16).map { UInt8($0) })
        let nonce = Data((0..<12).map { UInt8(100 + $0) })
        let sealed = try BackupCrypto.seal(Data("hello fogmosas".utf8), password: "jelszo123", iterations: 1000, salt: salt, nonce: nonce)
        XCTAssertEqual(sealed, hex(vector))
        XCTAssertEqual(String(data: try BackupCrypto.open(hex(vector), password: "jelszo123"), encoding: .utf8), "hello fogmosas")
        XCTAssertThrowsError(try BackupCrypto.open(hex(vector), password: "rossz-jelszo"))
        var damaged = hex(vector)
        damaged[40] ^= 1
        XCTAssertThrowsError(try BackupCrypto.open(damaged, password: "jelszo123"))
    }

    func testPayloadRoundTrip() throws {
        let p = BackupPayload(kind: "full", platform: "ios", createdMs: 1, data: "{\"a\":1}", photos: ["x.jpg": Data([1, 2, 3]).base64EncodedString()])
        let file = try encodeBackup(p, password: "hosszu-jelszo")
        XCTAssertTrue(BackupCrypto.isBackup(file))
        XCTAssertEqual(try decodeBackup(file, password: "hosszu-jelszo"), p)
        XCTAssertNotNil(BackupCrypto.passwordProblem("rovid"))
        XCTAssertNil(BackupCrypto.passwordProblem("eleg-hosszu"))
    }

    func testCareLinkAndScrub() {
        let c = CareInstruction(title: "Szájöblítés klórhexidinnel", times: ["08:00", "20:00"], days: 7, clinic: "Mosoly Fogászat")
        XCTAssertEqual(parseCareLink(careLinkCode(c)), c)
        var bad = c; bad.times = ["25:00"]
        XCTAssertNil(parseCareLink(careLinkCode(bad)))
        bad = c; bad.days = 0
        XCTAssertNil(parseCareLink(careLinkCode(bad)))
        XCTAssertNil(parseCareLink("denthub://link?d=abc"))
        let hist = [-60.0, -61, -59, -60.5, -60]
        XCTAssertNotNil(scrubNote(brushDb: -52, history: hist, manual: true))
        XCTAssertNil(scrubNote(brushDb: -58, history: hist, manual: true))
        XCTAssertNil(scrubNote(brushDb: -52, history: hist, manual: false))
        XCTAssertNil(scrubNote(brushDb: -52, history: Array(hist.prefix(3)), manual: true))
    }
}
