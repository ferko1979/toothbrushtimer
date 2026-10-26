import AVFoundation
import BrushCore
import CoreMotion
import Foundation
import HealthKit
import UserNotifications

/// Gravity vector for the listening policy (is the phone lying flat and still?).
final class MotionMonitor {
    private let manager = CMMotionManager()

    func start(_ handler: @escaping (Double, Double, Double) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 0.1
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let g = motion?.gravity else { return }
            handler(g.x, g.y, g.z)
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}

/// Rolling 7-day plan of local notifications (iOS allows 64 pending).
enum NotificationScheduler {
    static func requestAuthorization(_ done: @escaping (Bool) -> Void = { _ in }) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    static func reschedule(model: AppModel) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("rem.") })
            DispatchQueue.main.async {
                guard model.settings.isOn("notifications") else { return }
                let me = model.profile("me") ?? model.activeProfile
                let plan = ReminderPlanner().plan(now: Date(), records: model.records(for: me.id), goals: me.goals,
                                                  settings: model.settings.reminders, days: 7)
                for r in plan {
                    let content = UNMutableNotificationContent()
                    content.title = "🪥 Fogmosás"
                    content.body = r.text
                    content.sound = .default
                    content.userInfo = ["arm": true, "key": r.key]
                    let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                    center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
                }
            }
        }
    }
}

/// Apple Health: Fogmosás (HKCategoryTypeIdentifier.toothbrushingEvent).
final class HealthSync {
    static let shared = HealthSync()
    private let store = HKHealthStore()
    private var type: HKCategoryType? { HKObjectType.categoryType(forIdentifier: .toothbrushingEvent) }

    func requestAuthorization(_ done: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(), let t = type else { done(false); return }
        store.requestAuthorization(toShare: [t], read: []) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    func save(_ record: BrushRecord) {
        guard HKHealthStore.isHealthDataAvailable(), let t = type,
              store.authorizationStatus(for: t) == .sharingAuthorized else { return }
        let sample = HKCategorySample(type: t, value: HKCategoryValue.notApplicable.rawValue,
                                      start: record.start, end: record.start.addingTimeInterval(record.durationS))
        store.save(sample) { _, _ in }
    }
}

/// Reads feedback aloud (children who cannot read yet).
final class Speaker {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()

    func say(_ text: String) {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: text.unicodeScalars.filter { !$0.properties.isEmojiPresentation })
        let u = AVSpeechUtterance(string: String(view))
        u.voice = AVSpeechSynthesisVoice(language: "hu-HU")
        u.rate = 0.45
        synth.speak(u)
    }
}
