import XCTest
@testable import BrushCore

/// The Swift port must reproduce the Python reference (analysis/export_golden.py).
final class GoldenTests: XCTestCase {
    struct Expected: Decodable {
        struct Mel: Decodable { let shape: [Int]; let first_frames: [[Double]]; let frame_400: [Double] }
        struct Windows: Decodable { let t: [Double]; let features: [[Double]] }
        struct Scores: Decodable { let t: [Double]; let brush: [Double]; let water: [Double]; let sonic: [Double]; let sonic_f0: [Double] }
        struct Session: Decodable { let start: Double; let end: Double; let cue: String; let water_running_s: Double }
        struct Tol: Decodable { let log_mel: Double; let features: Double; let probabilities: Double; let sonic_score: Double; let session_s: Double }
        let audio: String
        let model: String
        let tolerance: Tol
        let log_mel: Mel
        let brush_windows: Windows
        let water_windows: Windows
        let scores: Scores
        let sessions: [Session]
        let events: [[EventValue]]
    }

    enum EventValue: Decodable {
        case num(Double), str(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { self = .num(d) } else { self = .str(try c.decode(String.self)) }
        }
        var string: String? { if case .str(let s) = self { return s } else { return nil } }
    }

    func url(_ name: String) throws -> URL {
        guard let u = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Golden") else {
            throw XCTSkip("golden file \(name) missing")
        }
        return u
    }

    func load() throws -> (Expected, [Double], ModelHeads) {
        let exp = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: url("golden_expected.json")))
        let wav = try WAVReader.read(url(exp.audio))
        XCTAssertEqual(wav.sampleRate, 16000)
        let heads = try ModelHeads(url: url(exp.model))
        return (exp, wav.samples, heads)
    }

    func assertClose(_ a: [Double], _ b: [Double], tol: Double, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, "\(what): length", file: file, line: line)
        var worst = 0.0, at = -1
        for i in 0..<Swift.min(a.count, b.count) where abs(a[i] - b[i]) > worst { worst = abs(a[i] - b[i]); at = i }
        XCTAssertLessThanOrEqual(worst, tol, "\(what): max diff \(worst) at \(at)", file: file, line: line)
    }

    func testLogMel() throws {
        let (exp, x, _) = try load()
        let frames = LogMelExtractor().frames(x)
        XCTAssertEqual([frames.count, frames.first?.count ?? 0], exp.log_mel.shape)
        for i in 0..<exp.log_mel.first_frames.count {
            assertClose(frames[i], exp.log_mel.first_frames[i], tol: exp.tolerance.log_mel, "log-mel frame \(i)")
        }
        assertClose(frames[400], exp.log_mel.frame_400, tol: exp.tolerance.log_mel, "log-mel frame 400")
    }

    func testWindowFeatures() throws {
        let (exp, x, _) = try load()
        let frames = LogMelExtractor().frames(x)
        let b = WindowFeatureExtractor.allWindows(frames, win: WindowFeatureExtractor.brushWindow)
        assertClose(b.times, exp.brush_windows.t, tol: 1e-6, "brush window times")
        XCTAssertEqual(b.features.count, exp.brush_windows.features.count)
        for i in 0..<b.features.count {
            assertClose(b.features[i], exp.brush_windows.features[i], tol: exp.tolerance.features, "brush features \(i)")
        }
        let w = WindowFeatureExtractor.allWindows(frames, win: WindowFeatureExtractor.waterWindow)
        for i in 0..<w.features.count {
            assertClose(w.features[i], exp.water_windows.features[i], tol: exp.tolerance.features, "water features \(i)")
        }
    }

    func testStreamingScoresAndSession() throws {
        let (exp, x, heads) = try load()
        let det = StreamingDetector(heads: heads)
        var rows: [ScoreRow] = []
        det.onRow = { rows.append($0) }
        // Feed in uneven chunks like a real microphone would.
        var i = 0
        let chunks = [1600, 4096, 777, 16000, 3200]
        var c = 0
        while i < x.count {
            let n = Swift.min(chunks[c % chunks.count], x.count - i)
            det.append(x[i..<(i + n)].map { Float($0) })
            i += n
            c += 1
        }
        let sessions = det.finish()
        assertClose(rows.map(\.t), exp.scores.t, tol: 1e-6, "row times")
        assertClose(rows.map(\.water), exp.scores.water, tol: exp.tolerance.probabilities, "water")
        assertClose(rows.map(\.brush), exp.scores.brush, tol: exp.tolerance.probabilities, "brush")
        assertClose(rows.map(\.sonic), exp.scores.sonic, tol: exp.tolerance.sonic_score, "sonic")
        XCTAssertEqual(sessions.count, exp.sessions.count)
        for (s, e) in zip(sessions, exp.sessions) {
            XCTAssertEqual(s.start, e.start, accuracy: exp.tolerance.session_s)
            XCTAssertEqual(s.end, e.end, accuracy: exp.tolerance.session_s)
            XCTAssertEqual(s.cue, e.cue)
        }
        XCTAssertEqual(det.session.events.map { $0.1.rawValue }, exp.events.compactMap { $0.last?.string })
    }

    func testBundledModelLoads() throws {
        let heads = try ModelHeads.bundled()
        XCTAssertEqual(heads.brush.coef.count, WindowFeatureExtractor.featureCount)
        XCTAssertEqual(heads.water.coef.count, WindowFeatureExtractor.featureCount)
    }
}
