import BrushCore
import SwiftUI

struct ResultView: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let record: BrushRecord
    let achievements: [Achievement]
    var testLog: [String] = []
    var endReason = "finish"
    var manual = false
    var notes: [String] = []
    /// Test mode: the recording the tester's remark is saved next to.
    var recordingBase: String? = nil
    var onResume: () -> Void = {}
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
                        if profile.canRead { Text(tr("Figurák: {0}", st.figures)).font(.caption).frame(maxWidth: .infinity) }
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
                            Text(tr("🏅 Új kitüntetés: {0}", achievementTitle(a.id, for: profile))).font(.headline)
                            if profile.canRead { Text(a.description).font(.subheadline).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !testLog.isEmpty {
                    TestLogCard(lines: testLog)
                    TestRecordingShareButton()
                }
                MeasurementFeedbackCard(profile: profile, record: record, endReason: endReason, manual: manual, notes: notes,
                                        recordingBase: recordingBase, onResume: onResume)
                if profile.canRead { BrushingExtrasView(profile: profile, record: record) }
                CareCheckInCard(profile: profile)
                Button(tr("Kész"), action: onDone).buttonStyle(.borderedProminent).controlSize(.large).padding(.top)
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
