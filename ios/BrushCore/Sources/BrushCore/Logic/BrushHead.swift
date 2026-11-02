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
    let thing = electric ? tr("fogkefefejet") : tr("fogkefét")
    if afterIllness {
        return BrushHeadStatus(ageDays: age, uses: uses, due: true, soon: false,
                               message: tr("Betegség után érdemes új {0} használni, hogy ne maradjanak kórokozók a sörtéken.", thing))
    }
    if age >= 90 {
        return BrushHeadStatus(ageDays: age, uses: uses, due: true, soon: false,
                               message: tr("Ideje új {0} venni: {1} napja ({2} fogmosás) használod. A fogorvosok 3–4 havonta javasolják a cserét.", thing, age, uses))
    }
    if age >= 83 {
        return BrushHeadStatus(ageDays: age, uses: uses, due: false, soon: true,
                               message: tr("Egy héten belül esedékes a csere: {0} napja ({1} fogmosás) használod.", age, uses))
    }
    return BrushHeadStatus(ageDays: age, uses: uses, due: false, soon: false,
                           message: tr("{0} napos, {1} fogmosás. Ha a sörték szétállnak vagy elhajlottak, cseréld hamarabb.", age, uses))
}
