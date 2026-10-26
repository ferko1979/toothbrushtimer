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

    var body: some View {
        Group {
            if model.data.onboarded {
                TabView {
                    HomeView().tabItem { Label("Főoldal", systemImage: "house") }
                    StatsView().tabItem { Label("Statisztika", systemImage: "chart.bar") }
                    AchievementsView().tabItem { Label("Kitüntetések", systemImage: "rosette") }
                    SettingsView().tabItem { Label("Beállítások", systemImage: "gearshape") }
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
    }
}
