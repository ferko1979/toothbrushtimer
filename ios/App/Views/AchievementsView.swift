import BrushCore
import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let profile = model.activeProfile
        let records = model.records(for: profile.id)
        let earned = model.coach.earnedAchievements(records, goals: profile.goals, today: Date())
        NavigationStack {
            List {
                if profile.child {
                    let st = stickers(records, goals: profile.goals, coach: model.coach)
                    Section("Matricák") {
                        Text("🟡 \(st.stickers) matrica · 🦖 \(st.figures) figura").font(.headline)
                        Text("Minden tökéletes nap egy matrica, 7 matrica egy figura.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Kitüntetések") {
                    ForEach(Achievements.all) { a in
                        HStack(spacing: 12) {
                            Text(earned.contains(a.id) ? "🏅" : "🔒").font(.title2)
                            VStack(alignment: .leading) {
                                Text(achievementTitle(a.id, for: profile)).font(.headline)
                                Text(a.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .opacity(earned.contains(a.id) ? 1 : 0.5)
                    }
                }
            }
            .navigationTitle("Kitüntetések")
        }
    }
}
