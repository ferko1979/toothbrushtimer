import Foundation

// "Pontos volt a mérés?" feedback after a brushing. Same as android/brushcore/.../Feedback.kt.

public enum FeedbackReasons {
    public struct Reason: Identifiable, Equatable { public let id: String; public let title: String }
    public static var all: [Reason] {
        [Reason(id: "too_early", title: tr("Túl korán leállt")),
         Reason(id: "too_late", title: tr("Túl későn állt le")),
         Reason(id: "no_start", title: tr("Későn indult / nem indult el")),
         Reason(id: "wrong_time", title: tr("Rossz időt mért")),
         Reason(id: "other", title: tr("Egyéb"))]
    }
}

/// Why the measurement stopped, for the result screen.
public func endReasonText(_ reason: String) -> String {
    switch reason {
    case "rinse": return tr("Leállás oka: öblítést hallottam.")
    case "quiet": return tr("Leállás oka: egy ideig nem hallottam fogmosást.")
    case "user": return tr("Leállás oka: te állítottad le.")
    default: return tr("Leállás oka: a figyelés véget ért.")
    }
}

public struct FeedbackEntry: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var profileId: String
    public var ok: Bool
    public var reason: String?
    public var note: String = ""
    public var durationS: Double
    public var endReason: String
    public var cue: String
    public var waterRunningS: Double
    public var brushType: String
    public var targetS: Double

    public init(date: Date, profileId: String, ok: Bool, reason: String?, note: String, durationS: Double,
                endReason: String, cue: String, waterRunningS: Double, brushType: String, targetS: Double) {
        self.date = date; self.profileId = profileId; self.ok = ok; self.reason = reason; self.note = note
        self.durationS = durationS; self.endReason = endReason; self.cue = cue; self.waterRunningS = waterRunningS
        self.brushType = brushType; self.targetS = targetS
    }
}

/// The app learns from "stopped too early / too late": extra seconds of silence tolerated (0…45 s).
public func adjustedQuietExtra(_ current: Double, reason: String?) -> Double {
    switch reason {
    case "too_early": return Swift.min(current + 10, 45)
    case "too_late": return Swift.max(current - 5, 0)
    default: return current
    }
}

/// Text the user can send to the developers (no audio, no personal data except what they typed).
public func feedbackReport(_ e: FeedbackEntry, platform: String, appVersion: String, quietExtraS: Double) -> String {
    var s = "DentHub-Brush feedback\n"
    s += "platform: \(platform) \(appVersion)\n"
    s += "verdict: \(e.ok ? "ok" : "wrong")\(e.reason.map { " / \($0)" } ?? "")\n"
    if !e.note.trimmingCharacters(in: .whitespaces).isEmpty { s += "note: \(e.note)\n" }
    s += String(format: "duration_s: %.1f, target_s: %d, end: %@, cue: %@\n", e.durationS, Int(e.targetS), e.endReason, e.cue)
    s += String(format: "water_running_s: %.1f, brush: %@, quiet_extra_s: %d\n", e.waterRunningS, e.brushType, Int(quietExtraS))
    return s
}
