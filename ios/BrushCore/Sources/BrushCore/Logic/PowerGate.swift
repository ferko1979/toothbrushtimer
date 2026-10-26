import Foundation

/// Battery saver: cheap loudness gate in front of the detectors (power_gate.py).
public final class EnergyGate {
    public var openDb = 6.0
    public var holdS = 15.0
    public var floorRiseDbPerS = 0.05
    public var hopS = 0.5
    private var floor: Double?
    private var lastLoud = -1e9

    public init() {}

    public func update(t: Double, rmsDb: Double) -> Bool {
        if let f = floor, rmsDb >= f {
            floor = f + floorRiseDbPerS * hopS
        } else {
            floor = rmsDb
        }
        if rmsDb >= (floor ?? rmsDb) + openDb { lastLoud = t }
        return t - lastLoud <= holdS
    }
}
