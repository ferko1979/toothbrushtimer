import AppIntents
import Foundation

/// "Hé Siri, fogmosás indítása" / Shortcuts / Action button.
struct StartBrushingIntent: AppIntent {
    static var title: LocalizedStringResource = "Fogmosás indítása"
    static var description = IntentDescription("Megnyitja az appot, és elkezdi figyelni a fogmosást.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.startRequest = AppRouter.StartRequest(armed: true)
        return .result()
    }
}

struct BrushShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartBrushingIntent(),
                    phrases: ["Start brushing with \(.applicationName)",
                              "\(.applicationName) start brushing",
                              "Fogmosás \(.applicationName)"],
                    shortTitle: "Fogmosás",
                    systemImageName: "mouth")
    }
}
