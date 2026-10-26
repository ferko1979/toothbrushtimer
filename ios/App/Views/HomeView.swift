import BrushCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: AppRouter

    private var profile: Profile { model.activeProfile }
    private var records: [BrushRecord] { model.records(for: profile.id) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(greeting).font(.largeTitle.bold())
                    if model.data.profiles.count > 1 { picker }
                    BigButton(title: "🪥  Fogmosás indítása") {
                        router.startRequest = AppRouter.StartRequest(armed: false)
                    }
                    todayCard
                    if model.settings.isOn("habit_tips"), let tip = detectHabits(records, goals: profile.goals, today: Date()).first {
                        Card {
                            Text("Tipp").font(.subheadline.bold())
                            Text(tip.message).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    if model.settings.isOn("brush_head_reminder") {
                        let st = brushHeadStatus(installed: profile.brushHeadInstalled, electric: profile.brushType == .electric,
                                                 records: records, today: Date())
                        Card {
                            HStack {
                                Text("🪥 " + (profile.brushType == .electric ? "Fogkefefej" : "Fogkefe") + ": \(st.ageDays) napos").font(.subheadline)
                                Spacer()
                                if st.due { Text("csere!").font(.caption.bold()).foregroundStyle(Theme.warn) }
                            }
                            if st.due || st.soon { Text(st.message).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if model.settings.isOn("floss_tracking") {
                        let done = extrasDoneToday(model.extras(for: profile.id), kind: .floss, today: Date())
                        Card {
                            HStack {
                                Text(done ? "🧵 Fogselyem: ma kipipálva ✔︎" : "🧵 Fogselyem: ma még nem volt").font(.subheadline)
                                Spacer()
                                if !done { Button("Kész") { model.addExtra(.floss) }.buttonStyle(.bordered) }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        let part = h < 10 ? "Jó reggelt" : (h < 18 ? "Szia" : "Jó estét")
        return profile.canRead ? "\(part), \(profile.name)!" : profile.avatarEmoji
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ki mos most fogat?").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                ForEach(model.data.profiles) { p in
                    Button { model.data.activeProfileId = p.id } label: {
                        VStack(spacing: 3) {
                            AvatarCircle(emoji: p.avatarEmoji, size: 56, selected: p.id == profile.id)
                            Text(p.canRead ? p.name : " ").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var todayCard: some View {
        let coach = model.coach
        let count = coach.todayCount(records, today: Date())
        let streak = coach.perfectStreak(records, goals: profile.goals, today: Date())
        return Card {
            HStack {
                VStack(alignment: .leading) {
                    Text("Ma").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(count) / \(profile.goals.perDay)").font(.title.bold())
                }
                Spacer()
                if model.settings.isOn("achievements") {
                    VStack(alignment: .trailing) {
                        Text("Sorozat").font(.subheadline).foregroundStyle(.secondary)
                        Text("🔥 \(streak) nap").font(.title.bold())
                    }
                }
            }
            if profile.canRead {
                Text(coach.dailySummary(records, goals: profile.goals, today: Date())).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
