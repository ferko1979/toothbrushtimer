import BrushCore
import SwiftUI

struct BrushingRequest: Identifiable {
    let id = UUID()
    let armed: Bool
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: AppRouter
    @State private var brushing: BrushingRequest?
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.data.onboarded && model.settings.isOn("app_lock", platform: .ios) && !lock.unlocked && brushing == nil {
                LockView(title: tr("Fogmosás – zárolva"), reason: tr("Fogmosás feloldása")) { lock.unlocked = true }
            } else if model.data.onboarded && !model.data.tourSeen && brushing == nil {
                TourView { model.data.tourSeen = true }
            } else if model.data.onboarded {
                TabView {
                    HomeView().tabItem { Label(tr("Főoldal"), systemImage: "house") }
                    StatsView().tabItem { Label(tr("Statisztika"), systemImage: "chart.bar") }
                    AchievementsView().tabItem { Label(tr("Kitüntetések"), systemImage: "rosette") }
                    SettingsView().tabItem { Label(tr("Beállítások"), systemImage: "gearshape") }
                }
            } else {
                OnboardingView()
            }
        }
        .onChange(of: router.startRequest) { _, req in
            guard let req = req, model.data.onboarded else { return }
            brushing = BrushingRequest(armed: req.armed)
            router.startRequest = nil
        }
        .fullScreenCover(item: $brushing) { req in
            BrushingView(profile: model.activeProfile, armed: req.armed)
                .environmentObject(model)
        }
        .onAppear { NotificationScheduler.reschedule(model: model) }
        .onChange(of: scenePhase) { _, phase in
            // Lock again in the background, but never in the middle of a brushing.
            if phase == .background && brushing == nil { lock.lock() }
        }
    }
}
