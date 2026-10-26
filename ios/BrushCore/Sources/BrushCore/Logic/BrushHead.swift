import Foundation

/// Toothbrush / brush-head replacement (brush_head.py). ADA: every 3-4 months.
public struct BrushHeadStatus: Equatable {
    public let ageDays: Int
    public let uses: Int
    public let due: Bool
    public let soon: Bool
    public let message: String
}

public func brushHeadStatus(installed: Date, electric: Bool, records: [BrushRecord], today: Date,
                            afterIllness: Bool = false, calendar: Calendar = .current) -> BrushHeadStatus {
    let age = calendar.dateComponents([.day], from: calendar.startOfDay(for: installed),
                                      to: calendar.startOfDay(for: today)).day ?? 0
    let uses = records.filter { $0.start >= calendar.startOfDay(for: installed) }.count
    let thing = electric ? "fogkefefejet" : "fogkefét"
    if afterIllness {
        return BrushHeadStatus(ageDays: age, uses: uses, due: true, soon: false,
                               message: "Betegség után érdemes új \(thing) használni, hogy ne maradjanak kórokozók a sörtéken.")
    }
    if age >= 90 {
        return BrushHeadStatus(ageDays: age, uses: uses, due: true, soon: false,
                               message: "Ideje új \(thing) venni: \(age) napja (\(uses) fogmosás) használod. A fogorvosok 3–4 havonta javasolják a cserét.")
    }
    if age >= 83 {
        return BrushHeadStatus(ageDays: age, uses: uses, due: false, soon: true,
                               message: "Egy héten belül esedékes a csere: \(age) napja (\(uses) fogmosás) használod.")
    }
    return BrushHeadStatus(ageDays: age, uses: uses, due: false, soon: false,
                           message: "\(age) napos, \(uses) fogmosás. Ha a sörték szétállnak vagy elhajlottak, cseréld hamarabb.")
}
