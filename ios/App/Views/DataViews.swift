import BrushCore
import SwiftUI
import UniformTypeIdentifiers

// Health data notice and consent, deleting everything, password-protected backup and family transfer.
// Same screens as android/app/.../DataScreens.kt.

enum PrivacyText {
    static var summary: String {
        tr("Az app egészségügyi adatokat kezel (fogmosás, tünetek, panaszok, fotók). Ezek csak ezen a telefonon tárolódnak, titkosított tárhelyen. Hangfelvétel nem készül (kivéve, ha a teszt módot bekapcsolod).")
    }
    static var points: [String] {
        [tr("A rendelődnek csak akkor megy adat, ha te küldöd el (üzenet, e-mail, jelentés)."),
         tr("A webes megtekintés végponttól végpontig titkosított; a szerver nem tudja elolvasni."),
         tr("A fotókat csak te látod, amíg el nem küldöd őket."),
         tr("Bármikor letöltheted (titkosított mentés) vagy véglegesen törölheted az összes adatodat."),
         tr("A tanácsok általános tájékoztatások, nem helyettesítik az orvosi vizsgálatot.")]
    }
}

/// Health data notice; the app can be used once the user agrees (new and existing users alike).
struct ConsentView: View {
    @EnvironmentObject var model: AppModel
    @State private var ok = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("🔒 Adataid védelme")).font(.title2.bold())
                Text(PrivacyText.summary)
                ForEach(PrivacyText.points, id: \.self) { Text("• " + $0).foregroundStyle(.secondary) }
                Toggle(tr("Elolvastam, és hozzájárulok, hogy az app ezeket az adatokat a telefonomon kezelje."), isOn: $ok)
                Button(tr("Tovább")) { model.data.consentAt = Date() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(!ok)
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

/// The backup file for the share / save sheets.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

private struct PasswordSheet: View {
    let title: String
    let confirmTwice: Bool
    let error: String?
    let onDone: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var p1 = ""
    @State private var p2 = ""

    var body: some View {
        let problem = confirmTwice ? (BackupCrypto.passwordProblem(p1) ?? (p1 != p2 ? tr("A két jelszó nem egyezik.") : nil)) : nil
        NavigationStack {
            Form {
                Section {
                    SecureField(tr("Jelszó"), text: $p1)
                    if confirmTwice { SecureField(tr("Jelszó még egyszer"), text: $p2) }
                } footer: {
                    VStack(alignment: .leading) {
                        if confirmTwice { Text(tr("Ezzel a jelszóval tudod majd visszaállítani. Ha elfelejted, a mentés nem nyitható meg.")) }
                        if let e = error ?? (p1.isEmpty ? nil : problem) { Text(e).foregroundStyle(Theme.danger) }
                    }
                }
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(tr("OK")) { onDone(p1) }.disabled(p1.isEmpty || problem != nil) }
            }
        }
    }
}

/// Settings: password-protected backup / restore, family transfer, privacy notice and deleting everything.
struct DataSection: View {
    @EnvironmentObject var model: AppModel
    private enum Step: Identifiable {
        case backupPassword(profile: String?), openPassword(restore: Bool)
        var id: String {
            switch self {
            case .backupPassword(let p): return "b" + (p ?? "")
            case .openPassword(let r): return r ? "r" : "p"
            }
        }
    }
    @State private var step: Step?
    @State private var exportDoc: BackupDocument?
    @State private var exportName = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var importRestore = true
    @State private var picked: Data?
    @State private var error: String?
    @State private var pendingRestore: BackupPayload?
    @State private var pendingProfile: BackupPayload?
    @State private var status: String?
    @State private var showPrivacy = false
    @State private var confirmWipe = 0

    var body: some View {
        Group {
            Section {
                Button(tr("Mentés fájlba")) { error = nil; step = .backupPassword(profile: nil) }
                Button(tr("Visszaállítás")) { importRestore = true; importing = true }
            } header: {
                Text(tr("💾 Mentés és átvitel"))
            } footer: {
                Text(tr("Jelszóval titkosított fájl: új telefonra vagy biztonsági másolatnak. A fotókat is tartalmazza."))
            }
            Section {
                ForEach(model.data.profiles) { p in
                    Button(tr("{0} átadása", p.name)) { error = nil; step = .backupPassword(profile: p.id) }
                }
                Button(tr("Profil fogadása")) { importRestore = false; importing = true }
                if let s = status { Text(s).font(.footnote).foregroundStyle(Theme.ok) }
            } footer: {
                Text(tr("Családi átvitel: egy profil (pl. a gyereké) átadása egy másik családtag telefonjára."))
            }
            Section(tr("🔒 Adatvédelem")) {
                Text(PrivacyText.summary).font(.footnote).foregroundStyle(.secondary)
                DisclosureGroup(tr("Adatkezelési tájékoztató"), isExpanded: $showPrivacy) {
                    ForEach(PrivacyText.points, id: \.self) { Text("• " + $0).font(.footnote) }
                }
                if let c = model.data.consentAt { Text(tr("Hozzájárultál: {0}", I18n.date(c))).font(.caption).foregroundStyle(.secondary) }
                Button(tr("Minden adatom törlése"), role: .destructive) { confirmWipe = 1 }
            }
        }
        .sheet(item: $step) { s in
            switch s {
            case .backupPassword(let pid):
                PasswordSheet(title: tr("Jelszó a mentéshez"), confirmTwice: true, error: nil) { pw in
                    step = nil
                    makeBackup(profile: pid, password: pw)
                }
            case .openPassword(let restore):
                PasswordSheet(title: tr("A mentés jelszava"), confirmTwice: false, error: error) { pw in open(password: pw, restore: restore) }
            }
        }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .data, defaultFilename: exportName) { result in
            if case .success = result { status = tr("Mentve ✔︎") }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .item]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let d = try? Data(contentsOf: url), BackupCrypto.isBackup(d) else { status = tr("Ez nem DentHub-Brush mentés."); return }
            picked = d
            error = nil
            step = .openPassword(restore: importRestore)
        }
        .alert(tr("Visszaállítod?"), isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button(tr("Visszaállítás"), role: .destructive) {
                if let p = pendingRestore {
                    do {
                        try model.importJSON(p.data)
                        writePhotos(p.photos)
                        status = tr("Visszaállítva ✔︎")
                    } catch {
                        status = tr("A visszaállítás nem sikerült.")
                    }
                }
                pendingRestore = nil
            }
            Button(tr("Mégse"), role: .cancel) { pendingRestore = nil }
        } message: {
            Text(tr("A mentés ({0}) felülírja a jelenlegi adatokat ezen a telefonon.",
                    I18n.date(Date(timeIntervalSince1970: Double(pendingRestore?.createdMs ?? 0) / 1000))))
        }
        .confirmationDialog(tr("Hova kerüljön a profil?"), isPresented: Binding(get: { pendingProfile != nil }, set: { if !$0 { pendingProfile = nil } }),
                            titleVisibility: .visible) {
            Button(tr("Új profilként")) { importProfile(into: nil) }
            ForEach(model.data.profiles) { t in
                Button(tr("Hozzáfűzés: {0}", t.name)) { importProfile(into: t.id) }
            }
            Button(tr("Mégse"), role: .cancel) { pendingProfile = nil }
        } message: {
            Text(tr("Új profilként, vagy egy meglévőhöz fűzve (a duplikátumokat kihagyjuk)."))
        }
        .alert(confirmWipe == 1 ? tr("Minden adatod törlődik") : tr("Biztosan? Ez nem vonható vissza."),
               isPresented: Binding(get: { confirmWipe > 0 }, set: { if !$0 { confirmWipe = 0 } })) {
            Button(confirmWipe == 1 ? tr("Tovább") : tr("Végleges törlés"), role: .destructive) {
                if confirmWipe == 1 {
                    DispatchQueue.main.async { confirmWipe = 2 }
                } else {
                    model.wipeEverything()
                    confirmWipe = 0
                }
            }
            Button(tr("Mégse"), role: .cancel) { confirmWipe = 0 }
        } message: {
            Text(tr("Fogmosások, napló, panaszok, fotók, emlékeztetők és beállítások – minden. Előtte érdemes titkosított mentést készíteni."))
        }
    }

    private func photos(_ names: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for n in names { if let d = try? Data(contentsOf: ClinicFiles.url(n)) { out[n] = d.base64EncodedString() } }
        return out
    }

    private func writePhotos(_ photos: [String: String]) {
        for (name, b64) in photos where name.range(of: "^[A-Za-z0-9._-]{1,80}$", options: .regularExpression) != nil {
            if let d = Data(base64Encoded: b64) { try? d.write(to: ClinicFiles.url(name), options: [.atomic, .completeFileProtection]) }
        }
    }

    private func makeBackup(profile pid: String?, password: String) {
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            let payload: BackupPayload
            if let pid = pid {
                payload = BackupPayload(kind: "profile", platform: "ios", createdMs: now, data: try model.exportProfile(pid),
                                        photos: photos(model.data.symptoms.filter { $0.profileId == pid }.flatMap(\.photos)))
            } else {
                payload = BackupPayload(kind: "full", platform: "ios", createdMs: now, data: try model.exportJSON(),
                                        photos: photos(model.data.symptoms.flatMap(\.photos)))
            }
            exportDoc = BackupDocument(data: try encodeBackup(payload, password: password))
            let who = pid.flatMap { model.profile($0)?.name.filter { $0.isLetter || $0.isNumber } }.map { "-" + $0 } ?? ""
            let day = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            exportName = String(format: "denthub-brush%@-%04d-%02d-%02d.dhb", who, day.year ?? 0, day.month ?? 0, day.day ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exporting = true }
        } catch {
            status = tr("A mentés nem sikerült.")
        }
    }

    private func open(password: String, restore: Bool) {
        guard let file = picked else { return }
        guard let p = try? decodeBackup(file, password: password) else { error = tr("Hibás jelszó, vagy sérült a fájl."); return }
        if p.platform != "ios" { error = tr("Ez a mentés Androidról készült; iPhone-on még nem nyitható meg."); return }
        if restore && p.kind != "full" { error = tr("Ez egy profil-átadás; a „Profil fogadása” gombbal nyisd meg."); return }
        if !restore && p.kind != "profile" { error = tr("Ez teljes mentés; a „Visszaállítás” gombbal nyisd meg."); return }
        step = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if restore { pendingRestore = p } else { pendingProfile = p }
        }
    }

    private func importProfile(into target: String?) {
        guard let p = pendingProfile else { return }
        do {
            try model.importProfile(p.data, into: target)
            writePhotos(p.photos)
            status = target.flatMap { model.profile($0)?.name }.map { tr("Hozzáfűzve: {0} ✔︎", $0) } ?? tr("Profil hozzáadva ✔︎")
        } catch {
            status = tr("A visszaállítás nem sikerült.")
        }
        pendingProfile = nil
    }
}

/// Care instructions from the clinic: confirm and add as a reminder.
struct CareLinkAlert: ViewModifier {
    @ObservedObject var model: AppModel
    func body(content: Content) -> some View {
        content.alert(tr("Utasítás a rendelőtől"), isPresented: Binding(get: { model.pendingCare != nil }, set: { if !$0 { model.pendingCare = nil } })) {
            Button(tr("Felvétel")) {
                if let c = model.pendingCare {
                    model.putCareTask(CareTask(profileId: model.activeProfile.id, title: c.title, times: c.times,
                                               start: Calendar.current.startOfDay(for: Date()), days: c.days))
                }
                model.pendingCare = nil
            }
            Button(tr("Mégse"), role: .cancel) { model.pendingCare = nil }
        } message: {
            if let c = model.pendingCare {
                Text([c.clinic, c.title, tr("Naponta {0}×: {1}", c.times.count, c.times.joined(separator: ", ")), tr("{0} napig", c.days),
                      tr("Emlékeztetőként felvesszük ide: {0}", model.activeProfile.name)].compactMap { $0 }.joined(separator: "\n"))
            }
        }
    }
}
