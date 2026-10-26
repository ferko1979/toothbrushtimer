import Foundation

/// Minimal reader for 16-bit PCM WAV files (used by the golden tests).
public enum WAVReader {
    public enum WAVError: Error { case invalid(String) }

    /// Returns (samples as float = int16 / 32768, sample rate). Multi-channel files are averaged.
    public static func read(_ url: URL) throws -> (samples: [Double], sampleRate: Int) {
        let data = try Data(contentsOf: url)
        let bytes = [UInt8](data)
        func u32(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 | Int(bytes[o + 2]) << 16 | Int(bytes[o + 3]) << 24 }
        func u16(_ o: Int) -> Int { Int(bytes[o]) | Int(bytes[o + 1]) << 8 }
        guard bytes.count > 44, String(bytes: bytes[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: bytes[8..<12], encoding: .ascii) == "WAVE" else {
            throw WAVError.invalid("not a RIFF/WAVE file")
        }
        var pos = 12
        var channels = 1, rate = 16000, bits = 16
        var dataStart = -1, dataLen = 0
        while pos + 8 <= bytes.count {
            let id = String(bytes: bytes[pos..<(pos + 4)], encoding: .ascii) ?? ""
            let len = u32(pos + 4)
            if id == "fmt " {
                guard u16(pos + 8) == 1 else { throw WAVError.invalid("only PCM is supported") }
                channels = u16(pos + 10)
                rate = u32(pos + 12)
                bits = u16(pos + 22)
            } else if id == "data" {
                dataStart = pos + 8
                dataLen = Swift.min(len, bytes.count - dataStart)
                break
            }
            pos += 8 + len + (len & 1)
        }
        guard dataStart >= 0, bits == 16 else { throw WAVError.invalid("no 16-bit data chunk") }
        let frames = dataLen / (2 * channels)
        var out = [Double](repeating: 0, count: frames)
        for f in 0..<frames {
            var acc = 0.0
            for c in 0..<channels {
                let o = dataStart + 2 * (f * channels + c)
                let v = Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8)
                acc += Double(v) / 32768.0
            }
            out[f] = acc / Double(channels)
        }
        return (out, rate)
    }
}
