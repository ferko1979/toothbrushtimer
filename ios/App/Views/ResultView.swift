import BrushCore
import SwiftUI

struct ResultView: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let record: BrushRecord
    let achievements: [Achievement]
    let onDone: () -> Void

    var body: some View {
        let fb = feedback(for: profile, durationS: record.durationS, coach: model.coach)
        let settings = model.settings
        ScrollView {
            VStack(spacing: 14) {
                if profile.child {
                    AvatarCircle(emoji: profile.avatarEmoji, size: 110).padding(.top)
                    Text(fb.icons).font(.system(size: 44))
                    let st = stickers(model.records(for: profile.id), goals: profile.goals, coach: model.coach)
                    Card {
                        Text(String(repeating: "🟡", count: st.stickers % 7) + String(repeating: "⚪", count: 7 - st.stickers % 7))
                            .font(.title2).frame(maxWidth: .infinity)
                        if profile.canRead { Text("Figurák: \(st.figures)").font(.caption).frame(maxWidth: .infinity) }
                    }
                    if profile.canRead { Text(fb.text).multilineTextAlignment(.center) }
                    if !profile.canRead {
                        Button { Speaker.shared.say(fb.text) } label: { Text("🔊").font(.system(size: 40)) }
                    }
                } else {
                    Text(record.durationS >= profile.goals.targetS ? "🎉" : "💪").font(.system(size: 54)).padding(.top)
                    Text(formatClock(record.durationS)).font(.largeTitle.bold())
                    Text(fb.text).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                if settings.isOn("water_warnings") && profile.canRead {
                    let msg = waterMessage(brushingS: record.durationS, waterRunningS: record.waterRunningS, locale: settings.waterLocale)
                    Card {
                        Text(msg.title).font(.headline).foregroundStyle(msg.wasted ? Theme.danger : Theme.ok)
                        ForEach(msg.lines, id: \.self) { Text($0).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if settings.isOn("achievements") {
                    ForEach(achievements) { a in
                        Card {
                            Text("🏅 Új kitüntetés: \(achievementTitle(a.id, for: profile))").font(.headline)
                            if profile.canRead { Text(a.description).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                }
                if settings.isOn("floss_tracking") || settings.isOn("mouthwash_tracking") {
                    Card {
                        Text("Kiegészítők ma").font(.subheadline.bold())
                        HStack {
                            if settings.isOn("floss_tracking") { ExtraButton(kind: .floss, title: "🧵 Fogselyem") }
                            if settings.isOn("mouthwash_tracking") { ExtraButton(kind: .mouthwash, title: "🫧 Szájvíz") }
                        }
                    }
                }
                Button("Kész", action: onDone).buttonStyle(.borderedProminent).controlSize(.large).padding(.top)
            }
            .padding()
        }
        .background(profile.child ? LinearGradient(colors: [Theme.kidTop, Theme.kidBottom], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [Color(.systemGroupedBackground)], startPoint: .top, endPoint: .bottom))
    }
}

private struct ExtraButton: View {
    @EnvironmentObject var model: AppModel
    let kind: ExtraRecord.Kind
    let title: String
    var body: some View {
        let done = extrasDoneToday(model.extras(for: model.data.activeProfileId), kind: kind, today: Date())
        Button(done ? title + " ✔︎" : title) { if !done { model.addExtra(kind) } }
            .buttonStyle(.bordered)
            .disabled(done)
    }
}
