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
        let arm = response.notification.request.content.userInfo["arm"] as? Bool ?? false
        DispatchQueue.main.async { AppRouter.shared.startRequest = AppRouter.StartRequest(armed: arm) }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
