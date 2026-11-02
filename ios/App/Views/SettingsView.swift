import BrushCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @State private var addingChild = false
    @State private var confirmDelete = false
    @State private var touring = false
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        if model.settings.isOn("parent_lock", platform: .ios) && !lock.parentUnlocked {
            LockView(title: tr("A beállítások szülői zárral védettek"), reason: tr("Szülői zár")) { lock.parentUnlocked = true }
        } else {
            settingsForm
        }
    }

    private var settingsForm: some View {
        NavigationStack {
            Form {
                Section {
                    Button { touring = true } label: { Label(tr("Mit tud az app? (bemutató)"), systemImage: "sparkles") }
                }
                Section("Nyelv / Language") {
                    Picker("Nyelv / Language", selection: $model.data.settings.language) {
                        Text(tr("Telefon nyelve")).tag("")
                        Text("Magyar").tag("hu")
                        Text("English").tag("en")
                    }
                    .pickerStyle(.segmented)
                }
                profilesSection
                remindersSection
                let groups = model.settings.groups(platform: .ios)
                ForEach(0..<groups.count, id: \.self) { i in
                    Section(groups[i].0) {
                        ForEach(groups[i].1) { f in featureToggle(f) }
                    }
                }
                waterSection
                Section(tr("Adatvédelem")) {
                    Text(tr("A hang csak ezen a készüléken, a memóriában dolgozódik fel. Hangfelvétel nem készül, és semmi nem kerül szerverre. A webes megtekintés csak akkor küld adatot, ha te olvasod be a QR-kódot, és akkor is titkosítva."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(tr("Összes adat törlése"), role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(tr("Beállítások"))
            .onChange(of: model.data.settings) { _, _ in NotificationScheduler.reschedule(model: model) }
            .sheet(isPresented: $addingChild) { AddChildView().environmentObject(model) }
            .fullScreenCover(isPresented: $touring) { TourView { touring = false } }
            .confirmationDialog(tr("Biztosan törölsz minden adatot?"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(tr("Törlés"), role: .destructive) { model.data = AppData() }
            }
        }
    }

    // MARK: Profiles

    private var profilesSection: some View {
        Section(tr("Profilok")) {
            ForEach(model.data.profiles) { p in
                NavigationLink {
                    ProfileEditView(profileId: p.id)
                } label: {
                    HStack {
                        AvatarCircle(emoji: p.avatarEmoji, size: 36)
                        Text(p.name)
                        if p.child { Text(p.canRead ? "gyerek" : tr("gyerek · csak képek")).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .deleteDisabled(p.id == "me")
            }
            .onDelete { idx in
                let ids = idx.map { model.data.profiles[$0].id }.filter { $0 != "me" }
                model.data.profiles.removeAll { ids.contains($0.id) }
                if ids.contains(model.data.activeProfileId) { model.data.activeProfileId = "me" }
            }
            Button(tr("Gyerek hozzáadása")) { addingChild = true }
        }
    }

    // MARK: Reminders

    private var remindersSection: some View {
        let r = $model.data.settings.reminders
        return Section(tr("Emlékeztetők")) {
            Toggle(tr("Reggel, ébredés után"), isOn: r.morningEnabled)
            if model.data.settings.reminders.morningEnabled {
                DatePicker(tr("Ébredés"), selection: Binding(clock: r.wakeTime), displayedComponents: .hourAndMinute)
            }
            Toggle(tr("Lefekvés előtt"), isOn: r.bedtimeEnabled)
            if model.data.settings.reminders.bedtimeEnabled {
                DatePicker(tr("Lefekvés"), selection: Binding(clock: r.bedtime), displayedComponents: .hourAndMinute)
                Stepper(tr("{0} perccel előtte", model.data.settings.reminders.bedtimeLeadMin), value: r.bedtimeLeadMin, in: 5...60, step: 5)
            }
            Toggle(tr("Esti emlékeztető (pl. vacsora után)"), isOn: r.eveningEnabled)
            if model.data.settings.reminders.eveningEnabled {
                DatePicker(tr("Időpont"), selection: Binding(clock: r.eveningTime), displayedComponents: .hourAndMinute)
            }
            Toggle(tr("Ismétlés, ha elmaradt"), isOn: r.followupEnabled)
            if model.data.settings.reminders.followupEnabled {
                Stepper(tr("{0} perc múlva", model.data.settings.reminders.followupAfterMin), value: r.followupAfterMin, in: 5...60, step: 5)
            }
            Text(tr("iPhone-on a reggeli emlékeztető az ébredés idejére érkezik, és a lezárt képernyőn vár, amíg először kézbe veszed a telefont."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Features

    @ViewBuilder
    private func featureToggle(_ f: Feature) -> some View {
        if f.available {
            let isLock = f.id == "app_lock" || f.id == "parent_lock"
            Toggle(isOn: Binding(get: { model.settings.isOn(f.id) }, set: { on in
                if isLock {
                    DeviceAuth.authenticate(reason: f.title) { ok in
                        guard ok else { return }
                        model.data.settings.set(f.id, on)
                        lock.unlocked = true
                        lock.parentUnlocked = true
                    }
                    return
                }
                model.data.settings.set(f.id, on)
                if f.id == "health_sync" && on { HealthSync.shared.requestAuthorization { _ in } }
                if f.id == "notifications" && on { NotificationScheduler.requestAuthorization() }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                    let desc = isLock && !DeviceAuth.available ? tr("Ehhez kódot vagy Face ID-t / Touch ID-t kell beállítani a telefonon.") : f.description
                    if !desc.isEmpty { Text(desc).font(.caption).foregroundStyle(.secondary) }
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
        Section(tr("Víz")) {
            Picker(tr("Mértékegység és árak"), selection: $model.data.settings.locale) {
                Text(tr("Magyarország (liter, Ft)")).tag("hu")
                Text(tr("USA (gallon, $)")).tag("us")
            }
            NavigationLink(tr("Csap vízhozamának mérése")) { TapFlowView() }
            if let f = model.settings.tapFlowLPerMin {
                Text(String(format: tr("A te csapod: %.1f l/perc"), f)).font(.caption).foregroundStyle(.secondary)
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
                Section(tr("Cél")) {
                    Stepper(tr("Naponta {0}×", p.goals.perDay), value: Binding(get: { p.goals.perDay }, set: { v in
                        var q = p; q.goals = Goals(perDay: v, targetS: p.goals.targetS); model.updateProfile(q)
                    }), in: 1...4)
                    Stepper(tr("Célidő: {0}", formatClock(p.goals.targetS)), value: Binding(get: { p.goals.targetS }, set: { v in
                        var q = p; q.goals = Goals(perDay: p.goals.perDay, targetS: v); model.updateProfile(q)
                    }), in: 30...300, step: 15)
                    ForEach(p.goals.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(Theme.warn) }
                }
                Section(tr("Fogkefe")) {
                    Picker(tr("Típus"), selection: Binding(get: { p.brushType }, set: { v in var q = p; q.brushType = v; model.updateProfile(q) })) {
                        Text(tr("Kézi")).tag(BrushType.manual)
                        Text(tr("Elektromos")).tag(BrushType.electric)
                    }
                    Button(p.brushType == .electric ? tr("Új fogkefefejet tettem fel") : tr("Új fogkefét kezdtem")) {
                        var q = p; q.brushHeadInstalled = Date(); model.updateProfile(q)
                    }
                    if p.brushType == .electric && model.settings.isOn("calibration") {
                        Text(p.calibration.statusText).font(.caption).foregroundStyle(.secondary)
                        Button(tr("Kalibráció újrakezdése")) { var q = p; q.calibration = BrushCalibration(); model.updateProfile(q) }
                    }
                }
                ProfileCareSection(profileId: p.id)
                if p.child {
                    Section(tr("Gyerek")) {
                        Toggle(tr("Tud olvasni"), isOn: Binding(get: { p.canRead }, set: { v in var q = p; q.canRead = v; model.updateProfile(q) }))
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
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { dismiss() } } }
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
                Text(tr("Tegyél a csap alá egy ismert méretű edényt (pl. 1 literes palackot). Nyisd meg a csapot úgy, ahogy fogmosáskor szoktad, és nyomd meg az Indítást; amikor megtelt, a Stopot."))
                    .font(.subheadline)
                Stepper(String(format: tr("Edény: %.1f l"), litres), value: $litres, in: 0.5...5, step: 0.5)
            }
            Section {
                if let st = started {
                    Button(tr("Stop")) {
                        let secs = Date().timeIntervalSince(st)
                        started = nil
                        do {
                            let f = try tapFlowFromMeasurement(litres: litres, seconds: secs)
                            model.data.settings.tapFlowLPerMin = f
                            result = String(format: tr("%.1f l/perc – elmentve."), f)
                        } catch {
                            result = tr("Ez nem tűnik reálisnak, próbáld újra.")
                        }
                    }
                    .font(.title2.bold()).foregroundStyle(Theme.danger)
                } else {
                    Button(tr("Indítás")) { started = Date(); result = nil }.font(.title2.bold())
                }
                if let r = result { Text(r) }
                if model.settings.tapFlowLPerMin != nil {
                    Button(tr("Alapértékre vissza")) { model.data.settings.tapFlowLPerMin = nil }
                }
            }
        }
        .navigationTitle(tr("Csap mérése"))
    }
}
