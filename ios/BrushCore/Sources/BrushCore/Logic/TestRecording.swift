import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Test builds only ("Teszt mód"): saves the microphone audio as a 16 kHz mono WAV and the detector's
/// timeline (scores every 0.5 s, events, result) as JSON, so a tester can send both to the developers.
/// Same format as android/brushcore/.../TestRecording.kt. Call from one queue.
public final class TestRecording {
    public static let maxSeconds = 8 * 60
    static let rate = 16000

    public let wavURL: URL
    public let jsonURL: URL
    private let handle: FileHandle
    private let meta: [String: Any]
    private var samples = 0
    private var rows: [[Any]] = []
    private var events: [[Any]] = []
    private var closed = false

    public init(directory: URL, meta: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let base = "denthub-brush-" + f.string(from: Date())
        wavURL = directory.appendingPathComponent(base + ".wav")
        jsonURL = directory.appendingPathComponent(base + ".json")
        FileManager.default.createFile(atPath: wavURL.path, contents: Data(count: 44))
        handle = try FileHandle(forWritingTo: wavURL)
        handle.seekToEndOfFile()
        self.meta = meta
    }

    public static let remarkSuffix = "-remark.txt"
    public var base: String { wavURL.deletingPathExtension().lastPathComponent }

    /// Recording names (oldest first): one per WAV or JSON timeline.
    public static func bases(in directory: URL) -> [String] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix("denthub-brush-") && ($0.hasSuffix(".wav") || $0.hasSuffix(".json")) }
            .map { ($0 as NSString).deletingPathExtension }
        return Array(Set(names)).sorted()
    }

    /// The files of one recording that exist: audio, timeline, tester's remark.
    public static func files(of base: String, in directory: URL) -> [URL] {
        [base + ".wav", base + ".json", base + remarkSuffix].map { directory.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Newest recording (wav + json + remark) in the folder.
    public static func latest(in directory: URL) -> [URL] {
        guard let base = bases(in: directory).last else { return [] }
        return files(of: base, in: directory)
    }

    /// Every recording with its remark (oldest first).
    public static func all(in directory: URL) -> [URL] { bases(in: directory).flatMap { files(of: $0, in: directory) } }

    /// Saves (overwrites) the tester's remark next to the recording, as they type it.
    public static func saveRemark(_ text: String, base: String, in directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(base + ".wav").path) else { return }
        try? Data(text.utf8).write(to: directory.appendingPathComponent(base + remarkSuffix))
    }

    /// Keeps every recording; only when they take more than maxBytes are the oldest dropped.
    public static func prune(in directory: URL, maxBytes: Int = 2_000_000_000) {
        func size(_ u: URL) -> Int { ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0 }
        let groups = bases(in: directory).map { files(of: $0, in: directory) }
        var total = groups.reduce(0) { $0 + $1.reduce(0) { $0 + size($1) } }
        for g in groups where total > maxBytes {
            total -= g.reduce(0) { $0 + size($1) }
            g.forEach { try? FileManager.default.removeItem(at: $0) }
        }
    }

    public func append(_ x: [Float]) {
        guard !closed, samples < Self.maxSeconds * Self.rate else { return }
        var data = Data(capacity: x.count * 2)
        for v in x {
            let i = Int16(clamping: Int((Swift.max(-1, Swift.min(1, v)) * 32767).rounded()))
            withUnsafeBytes(of: i.littleEndian) { data.append(contentsOf: $0) }
        }
        handle.write(data)
        samples += x.count
    }

    private func r3(_ d: Double) -> Double { (d * 1000).rounded() / 1000 }

    public func row(_ r: ScoreRow, state: String, rmsDb: Double) {
        guard !closed else { return }
        rows.append([r3(r.t), r3(r.brush), r3(r.water), r3(r.sonic), r3(r.sonicF0), state, r3(rmsDb)])
    }

    public func event(_ t: Double, _ name: String) {
        guard !closed else { return }
        events.append([r3(t), name])
    }

    /// Finalises the WAV header and writes the JSON.
    @discardableResult
    public func finish(result: [String: Any]) -> [URL] {
        guard !closed else { return [wavURL, jsonURL] }
        closed = true
        let dataBytes = UInt32(samples * 2)
        handle.seek(toFileOffset: 0)
        handle.write(Self.header(dataBytes))
        handle.closeFile()
        let obj: [String: Any] = [
            "format": "denthub-brush-test-1", "wav": wavURL.lastPathComponent, "sampleRate": Self.rate,
            "audioSeconds": Double(samples) / Double(Self.rate), "meta": meta, "result": result,
            "rowColumns": ["t", "brush", "water", "sonic", "sonicF0", "state", "rmsDb"], "rows": rows, "events": events,
        ]
        if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: jsonURL) }
        return [wavURL, jsonURL]
    }

    static func header(_ dataBytes: UInt32) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return d
    }
}

/// Test mode is in every build but behind the tester password (shared with testers). The same password
/// authenticates the uploads (server: TEST_UPLOAD_CODE, web/testupload.mjs). Same as TestAccess in
/// android/brushcore/.../TestRecording.kt.
public enum TestAccess {
    static let hash = "93e113c18ed319edbee0ded459ce64eaee6c333bc9cce128cb47e816a1d0d44f"
    public static let defaultHost = "https://fogmosas-web.onrender.com"

    public static func check(_ code: String) -> Bool {
        sha256Hex(Data(code.trimmingCharacters(in: .whitespacesAndNewlines).utf8)) == hash
    }

    public static func key(_ u: URL) -> String {
        let size = ((try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? NSNumber)?.intValue ?? 0
        return "\(u.lastPathComponent):\(size)"
    }

    /// Files not uploaded yet: the uploaded list holds "name:size" (a remark edited later goes up again).
    public static func pending(in directory: URL, uploaded: Set<String>) -> [URL] {
        TestRecording.all(in: directory).filter { u in
            guard !uploaded.contains(key(u)) else { return false }
            // The recording being made has no timeline yet; its WAV waits until the JSON is written.
            if u.pathExtension == "wav" {
                return FileManager.default.fileExists(atPath: u.deletingPathExtension().appendingPathExtension("json").path)
            }
            return true
        }
    }
}

func sha256Hex(_ d: Data) -> String {
    #if canImport(CryptoKit)
    return SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
    #else
    return ""
    #endif
}
