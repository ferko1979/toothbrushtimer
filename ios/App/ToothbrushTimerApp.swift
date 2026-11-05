import BrushCore
import SwiftUI
import UserNotifications

@main
struct ToothbrushTimerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = AppModel()
    @StateObject private var router = AppRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(router)
                .tint(Theme.brand)
                // DentHub clinic link (QR code or link from the clinic): denthub://link?d=...
                .onOpenURL { url in
                    if let c = parseClinicLink(url.absoluteString) { model.pendingClinic = c }
                    if let c = parseCareLink(url.absoluteString) { model.pendingCare = c }
                    if let a = Messaging.parseOffer(url.absoluteString, profileId: model.data.activeProfileId) {
                        model.receiveOffer(a)
                        router.messagesRequest = UUID()
                    }
                }
        }
    }
}

/// Requests coming from outside the UI: notification taps, Siri / Shortcuts.
final class AppRouter: ObservableObject {
    struct StartRequest: Equatable {
        /// Opened from a reminder / Siri: brushing is expected right away.
        let armed: Bool
        let id = UUID()
    }

    static let shared = AppRouter()
    @Published var startRequest: StartRequest?
    @Published var selectedTab = 0
    /// "Panaszom van" shortcut / quick action: open the complaint questions.
    @Published var complaintRequest: UUID?
    /// Clinic messages (message icon, appointment reminder, offer link).
    @Published var messagesRequest: UUID?
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Connectivity.shared.activate()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let arm = info["arm"] as? Bool ?? false
        DispatchQueue.main.async {
            if info["messages"] as? Bool == true { AppRouter.shared.messagesRequest = UUID() }
            else { AppRouter.shared.startRequest = AppRouter.StartRequest(armed: arm) }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
