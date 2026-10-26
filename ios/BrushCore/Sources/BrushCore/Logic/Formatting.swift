import Foundation

enum Formatting {
    /// 30703 -> "30 703" (Hungarian thousands separator).
    static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(" ") }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + String(out.reversed())
    }

    /// Hungarian decimal: 6.7 -> "6,7".
    static func hu(_ x: Double, digits: Int = 1) -> String {
        let s = String(format: "%.\(digits)f", x)
        let parts = s.split(separator: ".")
        let intPart = Int(parts[0]) ?? 0
        let grouped = Formatting.grouped(intPart)
        if parts.count > 1 { return grouped + "," + parts[1] }
        return grouped
    }

    /// 125 -> "2:05"
    static func clock(_ seconds: Double) -> String {
        let s = Swift.max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

public func formatClock(_ seconds: Double) -> String { Formatting.clock(seconds) }
