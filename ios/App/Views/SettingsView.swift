import BrushCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var addingChild = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                profilesSection
                remindersSection
                let groups = model.settings.groups(platform: .ios)
                ForEach(0..<groups.count, id: \.self) { i in
                    Section(groups[i].0) {
                        ForEach(groups[i].1) { f in featureToggle(f) }
                    }
                }
                waterSection
                Section("Adatvédelem") {
                    Text("A hang csak ezen a készüléken, a memóriában dolgozódik fel. Hangfelvétel nem készül, és semmi nem kerül szerverre.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Összes adat törlése", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Beállítások")
            .onChange(of: model.data.settings) { _, _ in NotificationScheduler.reschedule(model: model) }
            .sheet(isPresented: $addingChild) { AddChildView().environmentObject(model) }
            .confirmationDialog("Biztosan törölsz minden adatot?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Törlés", role: .destructive) { model.data = AppData() }
            }
        }
    }

    // MARK: Profiles

    private var profilesSection: some View {
        Section("Profilok") {
            ForEach(model.data.profiles) { p in
                NavigationLink {
                    ProfileEditView(profileId: p.id)
                } label: {
                    HStack {
                        AvatarCircle(emoji: p.avatarEmoji, size: 36)
                        Text(p.name)
                        if p.child { Text(p.canRead ? "gyerek" : "gyerek · csak képek").font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .deleteDisabled(p.id == "me")
            }
            .onDelete { idx in
                let ids = idx.map { model.data.profiles[$0].id }.filter { $0 != "me" }
                model.data.profiles.removeAll { ids.contains($0.id) }
                if ids.contains(model.data.activeProfileId) { model.data.activeProfileId = "me" }
            }
            Button("Gyerek hozzáadása") { addingChild = true }
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        let r = $model.data.settings.reminders
        return Section("Emlékeztetők") {
            Toggle("Reggel, ébredés után", isOn: r.morningEnabled)
            if model.data.settings.reminders.morningEnabled {
                DatePicker("Ébredés", selection: Binding(clock: r.wakeTime), displayedComponents: .hourAndMinute)
            }
            Toggle("Lefekvés előtt", isOn: r.bedtimeEnabled)
            if model.data.settings.reminders.bedtimeEnabled {
                DatePicker("Lefekvés", selection: Binding(clock: r.bedtime), displayedComponents: .hourAndMinute)
                Stepper("\(model.data.settings.reminders.bedtimeLeadMin) perccel előtte", value: r.bedtimeLeadMin, in: 5...60, step: 5)
            }
            Toggle("Esti emlékeztető (pl. vacsora után)", isOn: r.eveningEnabled)
            if model.data.settings.reminders.eveningEnabled {
                DatePicker("Időpont", selection: Binding(clock: r.eveningTime), displayedComponents: .hourAndMinute)
            }
            Toggle("Ismétlés, ha elmaradt", isOn: r.followupEnabled)
            if model.data.settings.reminders.followupEnabled {
                Stepper("\(model.data.settings.reminders.followupAfterMin) perc múlva", value: r.followupAfterMin, in: 5...60, step: 5)
            }
            Text("iPhone-on a reggeli emlékeztető az ébredés idejére érkezik, és a lezárt képernyőn vár, amíg először kézbe veszed a telefont.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Features

    @ViewBuilder
    private func featureToggle(_ f: Feature) -> some View {
        if f.available {
            Toggle(isOn: Binding(get: { model.settings.isOn(f.id) }, set: { on in
                model.data.settings.set(f.id, on)
                if f.id == "health_sync" && on { HealthSync.shared.requestAuthorization { _ in } }
                if f.id == "notifications" && on { NotificationScheduler.requestAuthorization() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                    if !f.description.isEmpty { Text(f.description).font(.caption).foregroundStyle(.secondary) }
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                    Text("hamarosan").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: .constant(false)).labelsHidden().disabled(true)
            }
        }
    }

    // MARK: Water

    private var waterSection: some View {
        Section("Víz") {
            Picker("Mértékegység és árak", selection: $model.data.settings.locale) {
                Text("Magyarország (liter, Ft)").tag("hu")
                Text("USA (gallon, $)").tag("us")
            }
            NavigationLink("Csap vízhozamának mérése") { TapFlowView() }
            if let f = model.settings.tapFlowLPerMin {
                Text(String(format: "A te csapod: %.1f l/perc", f)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ProfileEditView: View {
    @EnvironmentObject var model: AppModel
    let profileId: String

    var body: some View {
        if let p = model.profile(profileId) {
            Form {
                Section("Cél") {
                    Stepper("Naponta \(p.goals.perDay)×", value: Binding(get: { p.goals.perDay }, set: { v in
                        var q = p; q.goals = Goals(perDay: v, targetS: p.goals.targetS); model.updateProfile(q)
                    }), in: 1...4)
                    Stepper("Célidő: \(formatClock(p.goals.targetS))", value: Binding(get: { p.goals.targetS }, set: { v in
                        var q = p; q.goals = Goals(perDay: p.goals.perDay, targetS: v); model.updateProfile(q)
                    }), in: 30...300, step: 15)
                    ForEach(p.goals.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warn) }
                }
                Section("Fogkefe") {
                    Picker("Típus", selection: Binding(get: { p.brushType }, set: { v in var q = p; q.brushType = v; model.updateProfile(q) })) {
                        Text("Kézi").tag(BrushType.manual)
                        Text("Elektromos").tag(BrushType.electric)
                    }
                    Button(p.brushType == .electric ? "Új fogkefefejet tettem fel" : "Új fogkefét kezdtem") {
                        var q = p; q.brushHeadInstalled = Date(); model.updateProfile(q)
                    }
                    if p.brushType == .electric && model.settings.isOn("calibration") {
                        Text(p.calibration.statusText).font(.caption).foregroundStyle(.secondary)
                        Button("Kalibráció újrakezdése") { var q = p; q.calibration = BrushCalibration(); model.updateProfile(q) }
                    }
                }
                if p.child {
                    Section("Gyerek") {
                        Toggle("Tud olvasni", isOn: Binding(get: { p.canRead }, set: { v in var q = p; q.canRead = v; model.updateProfile(q) }))
                    }
                }
            }
            .navigationTitle(p.name)
        }
    }
}

struct AddChildView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var flow: OnboardingFlow = {
        let f = OnboardingFlow()
        try? f.answer("family")
        return f
    }()

    var body: some View {
        NavigationStack {
            QuestionFlowView(flow: flow, stopAtMore: true) {
                // The new child's avatar must differ from existing children's.
                if let child = flow.profiles().dropFirst().first {
                    var c = child
                    c.id = "child-\(UUID().uuidString.prefix(8))"
                    let taken = Set(model.data.profiles.compactMap(\.avatar))
                    if let a = c.avatar, taken.contains(a) {
                        c.avatar = Avatar.all.first { !taken.contains($0.id) }?.id ?? a
                    }
                    model.data.profiles.append(c)
                }
                dismiss()
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Mégse") { dismiss() } } }
        }
    }
}

struct TapFlowView: View {
    @EnvironmentObject var model: AppModel
    @State private var started: Date?
    @State private var litres = 1.0
    @State private var result: String?

    var body: some View {
        Form {
            Section {
                Text("Tegyél a csap alá egy ismert méretű edényt (pl. 1 literes palackot). Nyisd meg a csapot úgy, ahogy fogmosáskor szoktad, és nyomd meg az Indítást; amikor megtelt, a Stopot.")
                    .font(.subheadline)
                Stepper(String(format: "Edény: %.1f l", litres), value: $litres, in: 0.5...5, step: 0.5)
            }
            Section {
                if let st = started {
                    Button("Stop") {
                        let secs = Date().timeIntervalSince(st)
                        started = nil
                        do {
                            let f = try tapFlowFromMeasurement(litres: litres, seconds: secs)
                            model.data.settings.tapFlowLPerMin = f
                            result = String(format: "%.1f l/perc – elmentve.", f)
                        } catch {
                            result = "Ez nem tűnik reálisnak, próbáld újra."
                        }
                    }
                    .font(.title2.bold()).foregroundStyle(Theme.danger)
                } else {
                    Button("Indítás") { started = Date(); result = nil }.font(.title2.bold())
                }
                if let r = result { Text(r) }
                if model.settings.tapFlowLPerMin != nil {
                    Button("Alapértékre vissza") { model.data.settings.tapFlowLPerMin = nil }
                }
            }
        }
        .navigationTitle("Csap mérése")
    }
}
