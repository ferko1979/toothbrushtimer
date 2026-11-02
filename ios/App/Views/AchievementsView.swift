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
                    Section(tr("Matricák")) {
                        Text(tr("🟡 {0} matrica · 🦖 {1} figura", st.stickers, st.figures)).font(.headline)
                        Text(tr("Minden tökéletes nap egy matrica, 7 matrica egy figura.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if profile.child && profile.reward != nil {
                    Section(tr("Jutalom")) { RewardCard(profile: profile).listRowInsets(EdgeInsets()) }
                }
                Section(tr("Kitüntetések")) {
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
            .navigationTitle(tr("Kitüntetések"))
        }
    }
}
