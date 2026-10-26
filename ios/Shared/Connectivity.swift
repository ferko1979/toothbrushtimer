import BrushCore
import Foundation
import WatchConnectivity

/// Phone <-> watch: the watch sends finished brushings, the phone sends goals/profile.
final class Connectivity: NSObject, WCSessionDelegate {
    static let shared = Connectivity()

    var onRecord: ((BrushRecord) -> Void)?
    var onContext: ((Goals, String) -> Void)?   // goals, owner profile name

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(record: BrushRecord) {
        guard WCSession.isSupported(), let data = try? JSONEncoder().encode(record) else { return }
        WCSession.default.transferUserInfo(["record": data])
    }

    func pushContext(goals: Goals, ownerName: String) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = try? JSONEncoder().encode(goals) else { return }
        try? WCSession.default.updateApplicationContext(["goals": data, "owner": ownerName])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["record"] as? Data,
              let rec = try? JSONDecoder().decode(BrushRecord.self, from: data) else { return }
        DispatchQueue.main.async { self.onRecord?(rec) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["goals"] as? Data,
              let goals = try? JSONDecoder().decode(Goals.self, from: data) else { return }
        let owner = applicationContext["owner"] as? String ?? ""
        DispatchQueue.main.async { self.onContext?(goals, owner) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    #endif
}
