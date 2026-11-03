import BrushCore
import SwiftUI

// Tooth map, follow-up questions, photo timeline, care task reminders and the motor trend.
// Same screens as android/app/.../FollowupScreens.kt.

/// Adult teeth by quadrant (FDI); tap to select.
struct ToothMapPicker: View {
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("A fogakat szemből nézve látod: a te jobb oldalad a kép bal oldalán.")).font(.caption).foregroundStyle(.secondary)
            ForEach(ToothMap.quadrants, id: \.0) { q in
                Text(q.0).font(.caption.bold())
                HStack(spacing: 3) {
                    ForEach(q.1, id: \.self) { t in
                        let on = selected.contains(t)
                        Button {
                            if on { selected.remove(t) } else { selected.insert(t) }
                        } label: {
                            Text(t).font(.caption).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.brand : Color(.tertiarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(ToothMap.name(t))
                    }
                }
            }
            if !selected.isEmpty {
                Text(selected.sorted().map { ToothMap.name($0) }.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.brand)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
    }
}

/// Earlier photos of the same complaint side by side, oldest first.
struct PhotoTimelineView: View {
    let reports: [SymptomReport]
    var body: some View {
        if !reports.isEmpty {
            Text(tr("Fotók időrendben")).font(.subheadline.bold()).padding(.top, 6)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(reports) { r in
                        ForEach(r.photos, id: \.self) { name in
                            VStack(spacing: 2) {
                                if let img = ClinicFiles.image(name) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                Text(I18n.date(r.date)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Home: "Hogy van most?" 1, 3 and 7 days after a complaint.
struct FollowUpCard: View {
    @EnvironmentObject var model: AppModel
    @State private var reply: (text: String, contact: Bool)?
    @State private var visit = false

    var body: some View {
        let p = model.activeProfile
        let due = model.data.symptoms.filter { $0.profileId == p.id }.sorted { $0.date > $1.date }
            .lazy.compactMap { r in followUpDue(r, model.data.followUps, now: Date()).map { (r, $0) } }.first
        Group {
            if let rep = reply {
                Card {
                    Text(rep.text).font(.subheadline.bold())
                    HStack {
                        if rep.contact { Button(tr("📅 Időpontot kérek")) { visit = true }.buttonStyle(.bordered) }
                        Button(tr("Rendben")) { reply = nil }
                    }
                }
            } else if p.canRead, let d = due {
                let r = d.0
                let day = d.1
                Card {
                    Text(tr("Hogy van most?")).font(.subheadline.bold())
                    Text(tr("{0} – {1} napja jelezted.", Symptoms.kind(r.kind).title, day)).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(FollowUps.answers, id: \.0) { a in
                                Button(a.1) {
                                    model.addFollowUp(SymptomFollowUp(reportId: r.id, day: day, answer: a.0, date: Date()))
                                    if a.0 == "visited" { var q = p; q.lastCheckup = Date(); model.updateProfile(q) }
                                    reply = followUpAdvice(r, answer: a.0, day: day)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $visit) {
            NavigationStack {
                VisitRequestView(symptomId: nil) { visit = false; reply = nil }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Bezárás")) { visit = false } } }
            }
            .environmentObject(model)
        }
    }
}

/// Home: today's medicine / care tasks to tick off, and a button to add one.
struct CareTasksCard: View {
    @EnvironmentObject var model: AppModel
    @State private var add = false

    var body: some View {
        let p = model.activeProfile
        let today = Date()
        let tasks = model.data.careTasks.filter { $0.profileId == p.id && $0.activeOn(today) }
        Group {
            if p.canRead && !tasks.isEmpty {
                Card {
                    Text(tr("💊 Mai teendők")).font(.subheadline.bold())
                    ForEach(tasks) { t in
                        let pr = t.progress(today: today)
                        let left = t.days - (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: t.start),
                                                                               to: Calendar.current.startOfDay(for: today)).day ?? 0)
                        Text(tr("{0} · {1}/{2} · még {3} nap", t.title, pr.0, pr.1, left)).font(.subheadline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(t.times, id: \.self) { time in
                                    let done = t.isDone(today, time)
                                    Button((done ? "✔︎ " : "") + time) { model.putCareTask(t.toggled(today, time)) }
                                        .buttonStyle(.bordered).tint(done ? Theme.ok : nil)
                                }
                                Button(tr("Törlés"), role: .destructive) { model.removeCareTask(t.id) }
                            }
                        }
                    }
                    Button(tr("＋ Új emlékeztető")) { add = true }.font(.caption)
                }
            } else if p.canRead {
                Button(tr("💊 Gyógyszer / teendő emlékeztető")) { add = true }.font(.subheadline)
            }
        }
        .sheet(isPresented: $add) { CareTaskSheet(profileId: p.id).environmentObject(model) }
    }
}

/// New medicine / care task: preset or own title, times a day, number of days.
struct CareTaskSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let profileId: String
    @State private var title = ""
    @State private var perDay = 2
    @State private var days = 7
    @State private var times = CareTaskPresets.times(2)

    var body: some View {
        NavigationStack {
            Form {
                Section(tr("Gyakori")) {
                    ForEach(CareTaskPresets.all, id: \.title) { pr in
                        Button(pr.title) { title = pr.title; times = pr.times; perDay = pr.times.count; days = pr.days }
                    }
                }
                Section {
                    TextField(tr("Mit kell tenni?"), text: $title)
                    Stepper(tr("Naponta {0}×: {1}", perDay, times.joined(separator: ", ")), value: Binding(get: { perDay }, set: {
                        perDay = $0
                        times = CareTaskPresets.times($0)
                    }), in: 1...4)
                    Stepper(tr("{0} napig", days), value: $days, in: 1...30)
                } footer: {
                    Text(tr("Mindig az orvos vagy a betegtájékoztató utasítása szerint szedd a gyógyszert."))
                }
            }
            .navigationTitle(tr("Gyógyszer / teendő emlékeztető")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Mentés")) {
                        model.putCareTask(CareTask(profileId: profileId, title: title.trimmingCharacters(in: .whitespaces), times: times,
                                                   start: Calendar.current.startOfDay(for: Date()), days: days))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Statistics, electric brush: weekly motor frequency (battery health).
struct MotorTrendCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let p = model.activeProfile
        if p.brushType.powered && p.canRead {
            let t = motorTrend(model.records(for: p.id), today: Date())
            Card {
                Text(tr("🔋 Fogkefe-akku (motor zúgása hetente)")).font(.subheadline.bold())
                if !t.weeks.isEmpty {
                    let lo = (t.weeks.map(\.medianHz).min() ?? 0) - 3
                    let hi = (t.weeks.map(\.medianHz).max() ?? 1) + 1
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(t.weeks, id: \.weekStart) { w in
                            VStack(spacing: 2) {
                                Text("\(Int(w.medianHz))").font(.caption2).foregroundStyle(.secondary)
                                RoundedRectangle(cornerRadius: 4).fill(Theme.brand)
                                    .frame(height: 70 * max(0.1, min(1, (w.medianHz - lo) / (hi - lo))))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 90, alignment: .bottom)
                }
                Text(t.text).font(.caption).foregroundStyle((t.changePct ?? 0) <= -2 ? Theme.warn : .secondary)
            }
        }
    }
}
