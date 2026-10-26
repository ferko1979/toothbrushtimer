import Foundation

/// Personal calibration (calibration.py): brush tone frequency and tap flow.
public struct BrushCalibration: Codable, Equatable {
    public var f0s: [Double] = []
    public var sessionsNeeded = 3
    public var agreeHz = 5.0
    public var toleranceHz = 10.0

    public init() {}

    public mutating func addSession(f0Hz: Double?) {
        if let f = f0Hz, f > 0 { f0s.append(f) }
    }

    public var brushF0: Double? {
        let recent = Array(f0s.suffix(sessionsNeeded))
        guard recent.count >= sessionsNeeded else { return nil }
        let m = Stats.median(recent)
        return recent.allSatisfy { abs($0 - m) <= agreeHz } ? m : nil
    }

    public var remaining: Int { Swift.max(sessionsNeeded - f0s.count, 0) }

    public func sonicConfig() -> SonicConfig {
        guard let f0 = brushF0 else { return SonicConfig() }
        return SonicConfig(calibratedF0: f0, toleranceHz: toleranceHz)
    }

    public var statusText: String {
        if let f0 = brushF0 { return "Kalibrálva: a fogkeféd \(Int(f0.rounded())) Hz-en zúg." }
        if remaining > 0 { return "Kalibráció: még \(remaining) fogmosás kell a fogkeféd hangjának megtanulásához." }
        return "Kalibráció: a fogkefe hangja még nem egyértelmű, folytatom a tanulást."
    }
}

public enum TapFlowError: Error, Equatable { case invalidInput, unrealistic(Double) }

/// "Fill a 1 litre bottle and press stop" -> litres per minute.
public func tapFlowFromMeasurement(litres: Double, seconds: Double) throws -> Double {
    guard litres > 0, seconds > 0 else { throw TapFlowError.invalidInput }
    let flow = litres / seconds * 60
    guard (1.0...30.0).contains(flow) else { throw TapFlowError.unrealistic(flow) }
    return flow
}
