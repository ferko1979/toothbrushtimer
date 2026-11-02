import BrushCore
import SwiftUI

@main
struct ToothbrushTimerWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(model)
        }
    }
}

/// Watch-side storage: goals come from the phone, records go to the phone.
final class WatchModel: ObservableObject {
    @Published var goals = Goals() { didSet { save() } }
    @Published var ownerName = "" { didSet { save() } }
    @Published var records: [BrushRecord] = [] { didSet { save() } }
    let heads: ModelHeads?
    let coach = Coach()
    private let url: URL

    struct Stored: Codable { var goals: Goals; var ownerName: String; var records: [BrushRecord] }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("watch.json")
        heads = try? ModelHeads.bundled()
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stored.self, from: d) {
            goals = s.goals
            ownerName = s.ownerName
            records = s.records
        }
        Connectivity.shared.onContext = { [weak self] goals, owner in
            guard let self = self else { return }
            self.goals = goals
            self.ownerName = owner
            WatchSummary.publish(records: self.records, goals: goals, coach: self.coach)
        }
        Connectivity.shared.activate()
        WatchSummary.publish(records: records, goals: goals, coach: coach)
    }

    private func save() {
        let recent = records.filter { $0.start > Date().addingTimeInterval(-60 * 86400) }
        if let d = try? JSONEncoder().encode(Stored(goals: goals, ownerName: ownerName, records: recent)) {
            try? d.write(to: url, options: .atomic)
        }
    }

    func add(_ r: BrushingController.Result) {
        let rec = BrushRecord(profileId: "me", start: r.start, durationS: r.durationS, waterRunningS: r.waterRunningS,
                              source: "watch", brushF0: r.brushF0)
        records.append(rec)
        Connectivity.shared.send(record: rec)
        WatchSummary.publish(records: records, goals: goals, coach: coach)
    }

    func addCare(floss: Bool, bleeding: Bool, sensitive: Bool) {
        guard floss || bleeding || sensitive else { return }
        Connectivity.shared.send(care: CareEntry(profileId: "me", date: Date(), sensitivity: sensitive ? 1 : 0,
                                                 bleeding: bleeding, floss: floss))
    }
}

/// Publishes today's progress for the complication.
enum WatchSummary {
    static func publish(records: [BrushRecord], goals: Goals, coach: Coach) {
        let now = Date()
        WatchSummaryStore.save(WatchSummaryData(day: now, todayCount: coach.todayCount(records, today: now), perDay: goals.perDay,
                                                streak: coach.perfectStreak(records, goals: goals, today: now),
                                                lastDurationS: records.max(by: { $0.start < $1.start })?.durationS))
    }
}
