import BrushCore
import SwiftUI

extension AppModel {
    /// Extras offered in the journal for a profile (orthodontic mode adds floss and interdental).
    func careExtras(for p: Profile) -> [CareKind] {
        var out: [CareKind] = []
        if settings.isOn("floss_tracking") || p.orthodontic { out.append(.floss) }
        if settings.isOn("interdental_tracking") || p.orthodontic { out.append(.interdental) }
        if settings.isOn("mouthwash_tracking") { out.append(.mouthwash) }
        if settings.isOn("tongue_tracking") { out.append(.tongue) }
        return out
    }
}

extension CareKind {
    var icon: String {
        switch self {
        case .floss: return "🧵"
        case .mouthwash: return "🫧"
        case .interdental: return "🪥"
        case .tongue: return "👅"
        case .sensitivity: return "⚡"
        case .bleeding: return "🩸"
        }
    }
}

/// Selectable capsule used by the check-in.
struct ChoiceChip: View {
    let title: String
    let selected: Bool
    var big = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(big ? .system(size: 28) : .subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(selected ? Theme.brand.opacity(0.18) : Color(.tertiarySystemFill)))
                .overlay(Capsule().stroke(selected ? Theme.brand : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Check-in after brushing

struct CareCheckInCard: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    @State private var saved = false
    @State private var sens = 0
    @State private var bleed = false
    @State private var ticked: Set<CareKind> = []
    @State private var paste: String?
    private static let faces = ["😀", "😐", "😣"]
    private static var faceLabels: [String] { [tr("Nem"), tr("Kicsit"), tr("Nagyon")] }

    var body: some View {
        let s = model.settings
        let extras = model.careExtras(for: profile)
        let symptoms = s.isOn("care_checkin")
        let pasteOn = s.isOn("toothpaste_tracking")
        let pictures = !profile.canRead
        if symptoms || !extras.isEmpty || pasteOn {
            Card {
                if saved {
                    Text(pictures ? "✔︎ 👍" : tr("Elmentve a naplóba ✔︎")).font(.headline).foregroundStyle(Theme.ok)
                } else {
                    if symptoms {
                        Text(pictures ? "🦷 ?" : tr("Hogy érezted a fogmosást?")).font(.headline)
                        if !pictures { Text(tr("Érzékeny volt a fogad?")).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            ForEach(0..<3, id: \.self) { i in
                                ChoiceChip(title: pictures ? Self.faces[i] : "\(Self.faces[i]) \(Self.faceLabels[i])", selected: sens == i, big: pictures) { sens = i }
                            }
                        }
                        ChoiceChip(title: pictures ? "🩸" : tr("🩸 Vérzett az ínyem"), selected: bleed, big: pictures) { bleed.toggle() }
                    }
                    if !extras.isEmpty {
                        if !pictures { Text(tr("Ma ezt is csináltam:")).font(.caption).foregroundStyle(.secondary) }
                        HStack {
                            ForEach(extras, id: \.self) { k in
                                ChoiceChip(title: pictures ? k.icon : "\(k.icon) \(k.label)", selected: ticked.contains(k), big: pictures) {
                                    if ticked.contains(k) { ticked.remove(k) } else { ticked.insert(k) }
                                }
                            }
                        }
                    }
                    if pasteOn && !pictures {
                        Picker(tr("Fogkrém"), selection: Binding(get: { paste ?? profile.toothpaste ?? "" }, set: { paste = $0.isEmpty ? nil : $0 })) {
                            Text(tr("Fogkrém…")).tag("")
                            ForEach(Toothpastes.all) { Text($0.title).tag($0.id) }
                        }
                    }
                    Button(pictures ? "✔︎" : tr("Mentés a naplóba")) { save(pasteOn: pasteOn) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func save(pasteOn: Bool) {
        let tp = pasteOn ? (paste ?? profile.toothpaste) : nil
        model.addCare(CareEntry(profileId: profile.id, date: Date(), sensitivity: sens, bleeding: bleed,
                                floss: ticked.contains(.floss), mouthwash: ticked.contains(.mouthwash),
                                interdental: ticked.contains(.interdental), tongue: ticked.contains(.tongue), toothpaste: tp))
        if pasteOn, let tp = tp, tp != profile.toothpaste, var p = model.profile(profile.id) {
            p.toothpaste = tp
            model.updateProfile(p)
        }
        saved = true
    }
}

// MARK: - Home cards

struct DentistHomeCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let p = model.activeProfile
        if model.settings.isOn("dentist_reminders") && p.canRead {
            let st = dentistStatus(lastCheckup: p.lastCheckup, lastCleaning: p.lastCleaning, today: Date())
            if let msg = st.message ?? (p.lastCheckup == nil ? tr("Mikor voltál utoljára fogorvosnál? Add meg, és szólok, ha esedékes a kontroll.") : nil) {
                Card {
                    Text(tr("🦷 Fogorvos")).font(.subheadline.bold())
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(tr("Ma voltam kontrollon")) { var q = p; q.lastCheckup = Date(); model.updateProfile(q) }.buttonStyle(.bordered)
                        if st.cleaningOverdue || p.lastCleaning == nil {
                            Button(tr("Fogkő is")) { var q = p; q.lastCleaning = Date(); model.updateProfile(q) }
                        }
                    }
                }
            }
        }
    }
}

struct RewardCard: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    var body: some View {
        if model.settings.isOn("kid_rewards"),
           let r = rewardProgress(model.records(for: profile.id), goals: profile.goals, reward: profile.reward,
                                  need: profile.rewardStickers, since: profile.rewardSince, coach: model.coach) {
            Card {
                Text(r.done ? tr("🎁 {0} – megvan!", r.text) : "🎁 \(r.text)").font(.headline)
                ProgressView(value: r.fraction).tint(Theme.brand2)
                Text(profile.canRead ? tr("{0} / {1} matrica", r.have, r.need) : String(repeating: "🟡", count: min(r.have, 14)))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Statistics

struct CareStatsSections: View {
    @EnvironmentObject var model: AppModel
    @State private var pdf: URL?
    @State private var scanning = false
    @State private var pairing: WebLink.Pairing?
    @State private var webStatus: String?

    var body: some View {
        let p = model.activeProfile
        let es = model.care(for: p.id)
        let today = Date()
        let extras = model.careExtras(for: p)
        if !extras.isEmpty || model.settings.isOn("care_checkin") {
            Section(tr("Fogápolás")) {
                ForEach(extras, id: \.self) { k in
                    let streak = careStreak(es, k, today: today)
                    HStack {
                        Text("\(k.icon) \(k.label)")
                        Spacer()
                        Text(tr("{0}/7 · {1}/30 nap", careCount(es, k, today: today, days: 7), careCount(es, k, today: today, days: 30)) + (streak > 1 ? " · 🔥\(streak)" : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.settings.isOn("care_checkin") {
                    ForEach([CareKind.sensitivity, .bleeding], id: \.self) { k in
                        HStack {
                            Text("\(k.icon) \(k.label)")
                            Spacer()
                            Text(tr("{0} nap / 2 hét · {1} / 30", careCount(es, k, today: today, days: 14), careCount(es, k, today: today, days: 30)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if p.orthodontic { Text("🦷 " + Orthodontic.note).font(.caption).foregroundStyle(.secondary) }
                ForEach(careInsights(es, today: today, flossTracked: model.settings.isOn("floss_tracking") || p.orthodontic)) { ins in
                    Text(ins.text).font(.footnote).foregroundStyle(ins.alert ? Theme.danger : .primary)
                }
            }
        }
        if model.settings.isOn("dentist_report") {
            Section(tr("Jelentés a fogorvosnak")) {
                Text(tr("Fogmosás, fogköztisztítás, tünetek és fogkrém egy kinyomtatható PDF-ben.")).font(.caption).foregroundStyle(.secondary)
                ForEach([30, 90], id: \.self) { days in
                    Button(tr("PDF – utóbbi {0} nap", days)) {
                        pdf = ReportPDF.write(dentistReport(profile: p, records: model.records(for: p.id), entries: es, today: today,
                                                            days: days, coach: model.coach))
                    }
                }
            }
            .sheet(item: Binding(get: { pdf.map { IdentifiedURL(url: $0) } }, set: { pdf = $0?.url })) { item in
                ShareSheet(items: [item.url])
            }
        }
        if model.settings.isOn("family_overview") && !p.child && model.data.profiles.contains(where: \.child) {
            Section(tr("Család")) {
                ForEach(model.data.profiles.filter(\.child)) { k in
                    let rs = model.records(for: k.id)
                    HStack(spacing: 10) {
                        AvatarCircle(emoji: k.avatarEmoji, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(k.name).font(.subheadline.bold())
                            Text(tr("Ma {0}/{1} · 🔥 {2} nap · 🟡 {3} matrica", model.coach.todayCount(rs, today: today), k.goals.perDay, model.coach.perfectStreak(rs, goals: k.goals, today: today), stickers(rs, goals: k.goals, coach: model.coach).stickers)
                                 + (careDoneToday(model.care(for: k.id), .floss, today: today) ? " · 🧵" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                            if let r = rewardProgress(rs, goals: k.goals, reward: k.reward, need: k.rewardStickers, since: k.rewardSince, coach: model.coach) {
                                Text("🎁 \(r.text): \(r.have)/\(r.need)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        if model.settings.isOn("web_link", platform: .ios) {
            Section(tr("Megnézem a weben")) {
                Text(tr("Nyisd meg a DentHub-Brush weboldalát a számítógépen, és olvasd be az ott látható QR-kódot. Az adatok titkosítva mennek át, a szerver nem tárolja őket."))
                    .font(.caption).foregroundStyle(.secondary)
                Button { webStatus = nil; scanning = true } label: { Label(tr("QR-kód beolvasása"), systemImage: "qrcode.viewfinder") }
                if let s = webStatus { Text(s).font(.footnote).foregroundStyle(s.hasPrefix("✔") ? Theme.ok : Theme.danger) }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    QRScannerView { code in
                        scanning = false
                        if let pr = WebLink.parse(code) { pairing = pr } else { webStatus = tr("Ez nem a DentHub-Brush weboldal QR-kódja.") }
                    }
                    .ignoresSafeArea()
                    .navigationTitle(tr("QR-kód")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { scanning = false } } }
                }
            }
            .alert(tr("Megosztod a weboldallal?"), isPresented: Binding(get: { pairing != nil }, set: { if !$0 { pairing = nil } }), presenting: pairing) { pr in
                Button(tr("Megosztás")) { share(pr) }
                Button(tr("Mégse"), role: .cancel) {}
            } message: { pr in
                let who = model.activeProfile.child ? model.activeProfile.name : model.data.profiles.map(\.name).joined(separator: ", ")
                Text(tr("Webcím: {0}\nProfilok: {1}\n\nCsak akkor folytasd, ha ezt a címet te nyitottad meg a saját számítógépeden.", pr.host, who))
            }
        }
    }

    private func share(_ pr: WebLink.Pairing) {
        DeviceAuth.authenticate(reason: tr("Megosztás a weboldallal: {0}", pr.host)) { ok in
            guard ok else { return }
            do {
                let json = try WebShare.snapshotJSON(model: model)
                WebShare.send(pr, json: json) { err in
                    webStatus = err ?? tr("✔︎ Elküldve, nézd meg a böngészőben.")
                    if err == nil {
                        model.data.denthubLinkedAt = Date()
                        model.data.denthubHost = pr.host
                    }
                }
            } catch {
                webStatus = tr("Nem sikerült összeállítani az adatokat.")
            }
        }
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Settings

struct ProfileCareSection: View {
    @EnvironmentObject var model: AppModel
    let profileId: String
    @State private var rewardText = ""

    var body: some View {
        if let p = model.profile(profileId) {
            Section(tr("Fogápolás")) {
                Toggle(isOn: Binding(get: { p.orthodontic }, set: { on in
                    var q = p
                    q.orthodontic = on
                    if on && q.goals.targetS < Orthodontic.targetS { q.goals = Goals(perDay: q.goals.perDay, targetS: Orthodontic.targetS) }
                    model.updateProfile(q)
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Fogszabályzó"))
                        Text(tr("Hosszabb célidő ({0}), fogköztisztítás a naplóban.", formatClock(Orthodontic.targetS))).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.settings.isOn("toothpaste_tracking") {
                    Picker(tr("Fogkrém"), selection: Binding(get: { p.toothpaste ?? "" }, set: { v in var q = p; q.toothpaste = v.isEmpty ? nil : v; model.updateProfile(q) })) {
                        Text("—").tag("")
                        ForEach(Toothpastes.all) { Text($0.title).tag($0.id) }
                    }
                }
            }
            if model.settings.isOn("dentist_reminders") {
                Section(tr("Fogorvos")) {
                    DatePicker(tr("Utolsó kontroll"), selection: Binding(get: { p.lastCheckup ?? Date() }, set: { v in var q = p; q.lastCheckup = v; model.updateProfile(q) }),
                               in: ...Date(), displayedComponents: .date)
                    DatePicker(tr("Utolsó fogkőeltávolítás"), selection: Binding(get: { p.lastCleaning ?? Date() }, set: { v in var q = p; q.lastCleaning = v; model.updateProfile(q) }),
                               in: ...Date(), displayedComponents: .date)
                    if p.lastCheckup == nil { Text(tr("Még nincs megadva. Állítsd be, és szólok, ha esedékes a következő (félévente kontroll, évente fogkő).")).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if p.child && model.settings.isOn("kid_rewards") {
                Section(tr("Jutalom")) {
                    TextField(tr("Jutalom (pl. mozi, fagyi)"), text: $rewardText)
                    Stepper(tr("Ennyi matricáért: {0}", p.rewardStickers), value: Binding(get: { p.rewardStickers }, set: { v in var q = p; q.rewardStickers = v; model.updateProfile(q) }), in: 3...60)
                    Button(tr("Jutalom indítása")) {
                        var q = p
                        let t = rewardText.trimmingCharacters(in: .whitespaces)
                        q.reward = t.isEmpty ? nil : t
                        q.rewardSince = Date()
                        model.updateProfile(q)
                    }
                    if p.reward != nil {
                        Button(tr("Jutalom törlése"), role: .destructive) { var q = p; q.reward = nil; q.rewardSince = nil; rewardText = ""; model.updateProfile(q) }
                    }
                    Text(tr("A matricákat a jutalom indításától számoljuk (egy matrica = egy nap, amikor a napi cél teljesült).")).font(.caption).foregroundStyle(.secondary)
                }
                .onAppear { rewardText = p.reward ?? "" }
            }
        }
    }
}

// MARK: - DentHub link reminder

/// Until the app has been linked to the DentHub website, remind on every start where the results live.
struct LinkReminderCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: AppRouter
    var body: some View {
        if model.data.denthubLinkedAt == nil && model.linkReminder && model.activeProfile.canRead {
            Card {
                Text(tr("⚠️ Még nincs összekötve a DentHubbal")).font(.headline).foregroundStyle(Theme.warn)
                Text(tr("Regisztráció nélkül is használhatod, de az eredményeid most csak ezen a telefonon vannak. A DentHub oldalán akkor jelennek meg, ha összekötöd: nyisd meg a DentHub-Brush weboldalt, és olvasd be a QR-kódot."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(tr("Összekötés")) {
                        if !model.settings.isOn("web_link") { model.data.settings.set("web_link", true) }
                        router.selectedTab = 1
                    }.buttonStyle(.borderedProminent)
                    Button(tr("Később")) { model.linkReminder = false }
                }
            }
        }
    }
}

// MARK: - Lock

struct LockView: View {
    let title: String
    let reason: String
    let onUnlock: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Text("🔒").font(.system(size: 64))
            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Button(tr("Feloldás")) { DeviceAuth.authenticate(reason: reason) { if $0 { onUnlock() } } }
                .buttonStyle(.borderedProminent).controlSize(.large)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .onAppear { DeviceAuth.authenticate(reason: reason) { if $0 { onUnlock() } } }
    }
}
