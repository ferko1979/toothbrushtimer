import BrushCore
import Foundation

/// Everything the app stores (on the device only, as JSON in Application Support).
struct AppData: Codable {
    var onboarded = false
    var settings = AppSettings()
    var profiles: [Profile] = [Profile(id: "me", name: tr("Én"))]
    var activeProfileId = "me"
    var records: [BrushRecord] = []
    var extras: [ExtraRecord] = []
    var care: [CareEntry] = []
    var tourSeen = false
    /// Set after the first successful transfer to the DentHub website (QR link).
    var denthubLinkedAt: Date?
    var denthubHost: String?
    var feedback: [FeedbackEntry] = []

    init() {}

    // Older files: missing keys fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? [Profile(id: "me", name: tr("Én"))]
        activeProfileId = try c.decodeIfPresent(String.self, forKey: .activeProfileId) ?? "me"
        records = try c.decodeIfPresent([BrushRecord].self, forKey: .records) ?? []
        extras = try c.decodeIfPresent([ExtraRecord].self, forKey: .extras) ?? []
        care = try c.decodeIfPresent([CareEntry].self, forKey: .care) ?? []
        tourSeen = try c.decodeIfPresent(Bool.self, forKey: .tourSeen) ?? false
        denthubLinkedAt = try c.decodeIfPresent(Date.self, forKey: .denthubLinkedAt)
        denthubHost = try c.decodeIfPresent(String.self, forKey: .denthubHost)
        feedback = try c.decodeIfPresent([FeedbackEntry].self, forKey: .feedback) ?? []
    }
}

final class AppModel: ObservableObject {
    @Published var data = AppData() {
        didSet {
            if data.settings.language != oldValue.settings.language { I18n.setLanguage(data.settings.language) }
            save()
        }
    }
    /// "Not linked to DentHub yet" banner: shown again every time the app is opened.
    @Published var linkReminder = true
    let heads: ModelHeads?
    let coach = Coach()
    private let url: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("toothbrushtimer.json")
        heads = try? ModelHeads.bundled()
        if let d = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(AppData.self, from: d) {
            I18n.setLanguage(decoded.settings.language)
            data = decoded
        } else {
            // First start: language (and with it the default profile name) from the device.
            I18n.setLanguage(nil)
            data = AppData()
        }
        Connectivity.shared.onRecord = { [weak self] rec in self?.add(record: rec) }
        Connectivity.shared.onCare = { [weak self] e in
            // Journal entry from the watch: it belongs to the main profile.
            guard let self = self, !self.data.care.contains(where: { $0.id == e.id }) else { return }
            var entry = e
            entry.profileId = "me"
            self.data.care.append(entry)
        }
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
        data.care.append(CareEntry(profileId: data.activeProfileId, date: Date(), floss: kind == .floss, mouthwash: kind == .mouthwash))
    }

    /// Journal entries of a profile, including old floss / mouthwash ticks.
    func care(for profileId: String) -> [CareEntry] {
        data.care.filter { $0.profileId == profileId } + extras(for: profileId).map(\.asCare)
    }

    func addCare(_ e: CareEntry) { data.care.append(e) }

    func pushContextToWatch() {
        let me = profile("me") ?? data.profiles[0]
        Connectivity.shared.pushContext(goals: me.goals, ownerName: me.name)
    }
}
