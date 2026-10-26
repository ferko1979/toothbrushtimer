import BrushCore
import Foundation

/// Everything the app stores (on the device only, as JSON in Application Support).
struct AppData: Codable {
    var onboarded = false
    var settings = AppSettings()
    var profiles: [Profile] = [Profile(id: "me", name: "Én")]
    var activeProfileId = "me"
    var records: [BrushRecord] = []
    var extras: [ExtraRecord] = []
}

final class AppModel: ObservableObject {
    @Published var data = AppData() { didSet { save() } }
    let heads: ModelHeads?
    let coach = Coach()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("toothbrushtimer.json")
        heads = try? ModelHeads.bundled()
        if let d = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: d) {
            data = decoded
        }
        Connectivity.shared.onRecord = { [weak self] rec in self?.add(record: rec) }
        pushContextToWatch()
    }

    private func save() {
        guard let d = try? JSONEncoder().encode(data) else { return }
        try? d.write(to: url, options: [.atomic, .completeFileProtection])
    }

    var settings: AppSettings {
        get { data.settings }
        set { data.settings = newValue }
    }

    var activeProfile: Profile {
        data.profiles.first { $0.id == data.activeProfileId } ?? data.profiles[0]
    }

    func profile(_ id: String) -> Profile? { data.profiles.first { $0.id == id } }

    func updateProfile(_ p: Profile) {
        if let i = data.profiles.firstIndex(where: { $0.id == p.id }) { data.profiles[i] = p }
        if p.id == "me" { pushContextToWatch() }
    }

    func records(for profileId: String) -> [BrushRecord] {
        data.records.filter { $0.profileId == profileId }
    }

    func extras(for profileId: String) -> [ExtraRecord] {
        data.extras.filter { $0.profileId == profileId }
    }

    /// Saves a brushing; returns the achievements it newly earned.
    @discardableResult
    func add(record: BrushRecord) -> [Achievement] {
        guard !data.records.contains(where: { $0.id == record.id }) else { return [] }
        let p = profile(record.profileId) ?? activeProfile
        let before = coach.earnedAchievements(records(for: p.id), goals: p.goals, today: Date())
        data.records.append(record)
        if var prof = profile(p.id), settings.isOn("calibration"), prof.brushType == .electric {
            prof.calibration.addSession(f0Hz: record.brushF0)
            updateProfile(prof)
        }
        let after = coach.earnedAchievements(records(for: p.id), goals: p.goals, today: Date())
        NotificationScheduler.reschedule(model: self)
        if settings.isOn("health_sync", platform: .ios) && !p.child {
            HealthSync.shared.save(record)
        }
        return after.subtracting(before).sorted().compactMap { Achievements.byId($0) }
    }

    func addExtra(_ kind: ExtraRecord.Kind) {
        data.extras.append(ExtraRecord(profileId: data.activeProfileId, date: Date(), kind: kind))
    }

    func pushContextToWatch() {
        let me = profile("me") ?? data.profiles[0]
        Connectivity.shared.pushContext(goals: me.goals, ownerName: me.name)
    }
}
