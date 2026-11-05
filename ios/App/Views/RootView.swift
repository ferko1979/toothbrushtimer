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
    @State private var complaint = false
    @State private var messages = false
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let c = model.data.clinic, model.data.onboarded, !model.splashShown, brushing == nil {
                ClinicSplashView(clinic: c) { model.splashShown = true }
            } else if model.data.onboarded && model.settings.isOn("app_lock", platform: .ios) && !lock.unlocked && brushing == nil {
                LockView(title: tr("DentHub-Brush – zárolva"), reason: tr("DentHub-Brush feloldása")) { lock.unlocked = true }
            } else if model.data.onboarded && model.data.consentAt == nil && brushing == nil {
                ConsentView()
            } else if model.data.onboarded && !model.data.tourSeen && brushing == nil {
                TourView { model.data.tourSeen = true }
            } else if model.data.onboarded {
                TabView(selection: $router.selectedTab) {
                    // .id(refreshTick): rebuilt for "today" after a night, a pull-to-refresh or a return to the app.
                    HomeView().tabItem { Label(tr("Főoldal"), systemImage: "house") }.tag(0)
                    StatsView().tabItem { Label(tr("Statisztika"), systemImage: "chart.bar") }.tag(1)
                    AchievementsView().tabItem { Label(tr("Kitüntetések"), systemImage: "rosette") }.tag(2)
                    SettingsView().tabItem { Label(tr("Beállítások"), systemImage: "gearshape") }.tag(3)
                }
                .id(model.refreshTick)
                .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in model.checkDay() }
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
        .modifier(CareLinkAlert(model: model))
        .onChange(of: router.complaintRequest) { _, req in
            if req != nil && model.data.onboarded && brushing == nil { complaint = true }
            router.complaintRequest = nil
        }
        .onChange(of: router.messagesRequest) { _, req in
            if req != nil && model.data.onboarded && brushing == nil { messages = true }
            router.messagesRequest = nil
        }
        .sheet(isPresented: $messages) { MessengerView().environmentObject(model).environmentObject(router) }
        .sheet(isPresented: $complaint) {
            SymptomFlowView(profile: model.activeProfile, reports: model.data.symptoms).environmentObject(model)
        }
        .alert(tr("Összekötöd a rendelőddel?"), isPresented: Binding(get: { model.pendingClinic != nil }, set: { if !$0 { model.pendingClinic = nil } })) {
            Button(tr("Összekötés")) {
                model.data.clinic = model.pendingClinic
                model.pendingClinic = nil
            }
            Button(tr("Mégse"), role: .cancel) { model.pendingClinic = nil }
        } message: {
            Text(tr("{0}\nA rendelő logója megjelenik indításkor, és nekik küldheted a panaszaidat, fotóidat és időpontkéréseidet.", model.pendingClinic?.name ?? ""))
        }
        .onChange(of: scenePhase) { _, phase in
            // Lock again in the background, but never in the middle of a brushing.
            if phase == .background && brushing == nil { lock.lock() }
            if phase == .active {
                model.linkReminder = true
                model.refresh()
            }
        }
    }
}
