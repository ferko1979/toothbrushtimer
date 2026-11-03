import BrushCore
import MessageUI
import PhotosUI
import SwiftUI

// Complaint questions, advice, photos, sending to the doctor, visit requests and the linked clinic.
// Same screens as android/app/.../ClinicScreens.kt.

func levelColor(_ l: TriageLevel) -> Color {
    switch l {
    case .selfCare: return Theme.ok
    case .monitor: return Color(red: 0.79, green: 0.64, blue: 0.13)
    case .soon: return Theme.warn
    case .urgent, .emergency: return Theme.danger
    }
}

enum ClinicFiles {
    static func url(_ name: String) -> URL { AppModel.photosDir.appendingPathComponent(name) }

    /// Saves a photo as JPEG in the app's photo folder; returns its file name.
    static func save(_ image: UIImage) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        let name = "p-\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(name), options: [.atomic, .completeFileProtection])
            return name
        } catch {
            return nil
        }
    }

    static func image(_ name: String) -> UIImage? { UIImage(contentsOfFile: url(name).path) }
    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }
}

/// What the e-mail / share sheet sends.
struct OutgoingMail: Identifiable {
    let id = UUID()
    let to: String?
    let subject: String
    let body: String
    let photos: [String]
}

/// Mail composer with the photos attached, or the share sheet when Mail is not set up.
struct MailSheet: View {
    let mail: OutgoingMail
    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposer(mail: mail).ignoresSafeArea()
        } else {
            ShareSheet(items: [mail.subject + "\n\n" + mail.body] + mail.photos.map { ClinicFiles.url($0) as Any })
        }
    }
}

struct MailComposer: UIViewControllerRepresentable {
    let mail: OutgoingMail
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let c = MFMailComposeViewController()
        c.mailComposeDelegate = context.coordinator
        if let to = mail.to { c.setToRecipients([to]) }
        c.setSubject(mail.subject)
        c.setMessageBody(mail.body, isHTML: false)
        for p in mail.photos {
            if let d = try? Data(contentsOf: ClinicFiles.url(p)) { c.addAttachmentData(d, mimeType: "image/jpeg", fileName: p) }
        }
        return c
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: dismiss) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let dismiss: DismissAction
        init(dismiss: DismissAction) { self.dismiss = dismiss }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            dismiss()
        }
    }
}

/// Camera for a complaint photo.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ p: CameraPicker) { parent = p }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

private struct ChoiceButton: View {
    let label: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.body).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Theme.brand.opacity(0.12) : Color(.secondarySystemGroupedBackground)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Theme.brand : Color(.separator), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// The complaint, one question after the other, then advice, photos and sending (presented as a sheet).
struct SymptomFlowView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var flow: SymptomFlow
    @State private var tick = 0
    @State private var multi: Set<String> = []

    init(profile: Profile, reports: [SymptomReport]) {
        _flow = State(initialValue: SymptomFlow(recentSameKind: { k in
            recentSymptomCount(reports, profileId: profile.id, kind: k, now: Date())
        }, child: profile.child))
    }

    var body: some View {
        NavigationStack {
            let _ = tick
            Group {
                if let q = flow.next() {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ProgressView(value: flow.progress).tint(Theme.brand)
                            Text(q.title).font(.title2.bold())
                            if q.id == "kind" {
                                Text(tr("Válaszd ki, mi történt. Utána pár rövid kérdés jön, hogy pontosan leírhasd."))
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            if q.id == "teeth" {
                                ToothMapPicker(selected: $multi)
                                Button(tr("Nem tudom / kihagyom")) {
                                    try? flow.answer(["unsure"])
                                    multi = []
                                    tick += 1
                                }
                                .buttonStyle(.bordered).frame(maxWidth: .infinity)
                            }
                            ForEach(q.id == "teeth" ? [] : q.options, id: \.id) { o in
                                ChoiceButton(label: o.label, selected: multi.contains(o.id)) {
                                    if q.multi {
                                        if multi.contains(o.id) { multi.remove(o.id) } else { multi.insert(o.id) }
                                    } else {
                                        try? flow.answer([o.id])
                                        tick += 1
                                    }
                                }
                            }
                            if q.multi {
                                Button(tr("Tovább")) {
                                    try? flow.answer(Array(multi))
                                    multi = []
                                    tick += 1
                                }
                                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity).disabled(multi.isEmpty)
                            }
                        }
                        .padding()
                    }
                } else {
                    SymptomResultView(flow: flow) { dismiss() }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(flow.next() == nil ? tr("Tanács") : tr("Panasz"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if flow.kind != nil {
                        Button(tr("‹ Vissza")) { flow.back(); multi = []; tick += 1 }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Bezárás")) { dismiss() } }
            }
        }
    }
}

struct SymptomResultView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    let flow: SymptomFlow
    let onClose: () -> Void
    @State private var photos: [String] = []
    @State private var note = ""
    @State private var saved: SymptomReport?
    @State private var camera = false
    @State private var picked: PhotosPickerItem?
    @State private var mail: OutgoingMail?
    @State private var visit = false
    @State private var addTask = false

    var body: some View {
        let res = flow.result()
        let p = model.activeProfile
        let clinic = model.data.clinic
        let k = Symptoms.kind(flow.kind ?? "other")
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(k.emoji) \(k.title)").foregroundStyle(.secondary)
                Text("\(res.level.emoji) \(res.level.title)").font(.title3.bold()).foregroundStyle(levelColor(res.level))
                    .frame(maxWidth: .infinity, alignment: .leading).padding()
                    .background(RoundedRectangle(cornerRadius: 16).fill(levelColor(res.level).opacity(0.12)))
                if res.level == .emergency || res.level == .urgent {
                    HStack {
                        if res.level == .emergency {
                            Button(tr("📞 112 hívása")) { if let u = URL(string: "tel://112") { openURL(u) } }
                                .buttonStyle(.borderedProminent).tint(Theme.danger)
                        }
                        if let ph = clinic?.phone, let u = URL(string: "tel://" + ph.filter { $0.isNumber || $0 == "+" }) {
                            Button(tr("📞 Rendelő hívása")) { openURL(u) }.buttonStyle(.bordered)
                        }
                    }
                }
                Card {
                    Text(tr("Mit tehetsz most?")).font(.headline)
                    ForEach(res.advice, id: \.self) { Text("• " + $0).font(.subheadline) }
                    Text(tr("Ez általános tanács, nem orvosi diagnózis. Ha bizonytalan vagy, vagy rosszabbodik, keresd az orvosodat."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Card {
                    Text(tr("📷 Fotó")).font(.headline)
                    Text(res.photo ?? tr("Ha látható a gond, egy fotó sokat segíthet az orvosnak."))
                        .font(.subheadline).foregroundStyle(res.photo != nil ? Theme.brand : .secondary)
                    HStack {
                        Button(tr("Fotó készítése")) { camera = true }.buttonStyle(.bordered)
                        PhotosPicker(selection: $picked, matching: .images) { Text(tr("Galéria")) }.buttonStyle(.bordered)
                    }
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(photos, id: \.self) { name in
                                    ZStack(alignment: .topTrailing) {
                                        if let img = ClinicFiles.image(name) {
                                            Image(uiImage: img).resizable().scaledToFill().frame(width: 96, height: 96).clipShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                        Button { photos.removeAll { $0 == name }; ClinicFiles.delete(name) } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(.white, .black.opacity(0.6))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                TextField(tr("Megjegyzés (nem kötelező)"), text: $note, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                Card {
                    Text(res.suggestMessage ? tr("Elküldöd az orvosodnak?") : tr("Szeretnéd mégis megmutatni az orvosodnak?")).font(.headline)
                    Text(clinic.map { tr("Rendelő: {0}", $0.name) }
                         ?? tr("Ha a DentHubon összekötöd a fiókod a rendelőddel, közvetlenül nekik küldheted, és az orvos a kartonodhoz mentheti."))
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if clinic != nil {
                            Button(tr("📨 Üzenet a rendelőnek")) {
                                let r = save(via: "message")
                                model.data.messages.append(ClinicMessage(profileId: p.id, date: Date(), text: symptomSummary(r).joined(separator: "\n"),
                                                                         photos: r.photos, symptomId: r.id))
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Button(tr("✉️ E-mail")) {
                            let r = save(via: "email")
                            let m = clinicEmail(patientName: p.name, symptom: r, visit: nil)
                            mail = OutgoingMail(to: clinic?.email, subject: m.subject, body: m.body, photos: r.photos)
                        }
                        .buttonStyle(.bordered)
                    }
                    if let via = saved?.sentVia {
                        Text(via == "message" ? tr("✔︎ Elküldve a rendelőnek") : tr("✔︎ E-mail előkészítve")).font(.caption).foregroundStyle(Theme.ok)
                    }
                }
                if res.suggestBooking || clinic != nil {
                    Button(tr("📅 Időpontot kérek")) { _ = save(via: nil); visit = true }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
                Button(tr("💊 Gyógyszer / teendő emlékeztető")) { addTask = true }
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
                Button(tr("Mentés a naplóba és bezárás")) { _ = save(via: nil); onClose() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
            .padding()
        }
        .sheet(isPresented: $camera) { CameraPicker { img in if let n = ClinicFiles.save(img) { photos.append(n) } } }
        .sheet(isPresented: $addTask) { CareTaskSheet(profileId: model.activeProfile.id).environmentObject(model) }
        .sheet(item: $mail) { MailSheet(mail: $0) }
        .navigationDestination(isPresented: $visit) { VisitRequestView(symptomId: saved?.id, onClose: onClose) }
        .onChange(of: picked) { _, item in
            guard let item = item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data), let n = ClinicFiles.save(img) {
                    await MainActor.run { photos.append(n) }
                }
                await MainActor.run { picked = nil }
            }
        }
    }

    private func save(via: String?) -> SymptomReport {
        let p = model.activeProfile
        var r = saved ?? {
            let r = flow.report(profileId: p.id, now: Date(), photos: photos, note: note)
            // Bleeding / sensitivity also count in the care journal.
            if r.kind == "bleeding" || r.kind == "sensitivity" {
                model.addCare(CareEntry(profileId: p.id, date: r.date, sensitivity: r.kind == "sensitivity" ? (r.answer("since").contains("today") ? 1 : 2) : 0,
                                        bleeding: r.kind == "bleeding"))
            }
            return r
        }()
        r.photos = photos
        r.note = note
        if let via = via { r.sentVia = via; r.sentAt = Date() }
        model.addSymptom(r)
        saved = r
        return r
    }
}

private func reasonFor(_ kind: String?) -> String {
    switch kind {
    case "pain", "sensitivity", "swelling", "jaw": return "pain"
    case "bleeding": return "bleeding"
    case "chipped", "knocked", "loose": return "broken"
    case "braces": return "braces"
    case nil: return "checkup"
    default: return "other"
    }
}

/// "Időpontot kérek": only a check-up, or a reason; when; then booking, message, e-mail or a call.
struct VisitRequestView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openURL) private var openURL
    let symptomId: UUID?
    let onClose: () -> Void
    @State private var reason: String?
    @State private var timing: String?
    @State private var parts: Set<String> = []
    @State private var note = ""
    @State private var sent: String?
    @State private var mail: OutgoingMail?

    var body: some View {
        let p = model.activeProfile
        let clinic = model.data.clinic
        let symptom = model.data.symptoms.first { $0.id == symptomId }
        let reasonNow = reason ?? reasonFor(symptom?.kind)
        let timingNow = timing ?? (symptom.map { TriageLevel.byId($0.level).rank >= TriageLevel.urgent.rank } == true ? "asap" : "any")
        Form {
            if let c = clinic { Section { Text("🏥 " + c.name).font(.headline) } }
            Section(tr("Csak kontrollra mennél, vagy van oka?")) {
                Picker(tr("Ok"), selection: Binding(get: { reasonNow }, set: { reason = $0 })) {
                    ForEach(VisitReasons.all, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.inline).labelsHidden()
            }
            if let s = symptom {
                Section(tr("Panasz")) { ForEach(symptomSummary(s), id: \.self) { Text($0).font(.caption) } }
            }
            Section(tr("Mikor lenne jó?")) {
                Picker(tr("Mikor"), selection: Binding(get: { timingNow }, set: { timing = $0 })) {
                    ForEach(VisitReasons.timings, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.segmented)
                ForEach(VisitReasons.dayParts, id: \.0) { d in
                    Toggle(d.1, isOn: Binding(get: { parts.contains(d.0) }, set: { if $0 { parts.insert(d.0) } else { parts.remove(d.0) } }))
                }
                TextField(tr("Megjegyzés (nem kötelező)"), text: $note, axis: .vertical)
            }
            Section {
                if let c = clinic, c.bookingUrl != nil {
                    Button(tr("📅 Online foglalás a rendelőnél")) {
                        let v = request(via: "booking", reason: reasonNow, timing: timingNow, symptom: symptom)
                        if let s = bookingLink(c, v), let u = URL(string: s) { openURL(u) }
                    }
                }
                if clinic != nil {
                    Button(tr("📨 Kérés üzenetben")) {
                        let v = request(via: "message", reason: reasonNow, timing: timingNow, symptom: symptom)
                        model.data.messages.append(ClinicMessage(profileId: p.id, date: Date(), text: visitText(v, patientName: p.name, symptom: symptom),
                                                                 photos: symptom?.photos ?? [], symptomId: symptom?.id, visitId: v.id))
                    }
                }
                Button(tr("✉️ Kérés e-mailben")) {
                    let v = request(via: "email", reason: reasonNow, timing: timingNow, symptom: symptom)
                    let m = clinicEmail(patientName: p.name, symptom: symptom, visit: v)
                    mail = OutgoingMail(to: clinic?.email, subject: m.subject, body: m.body, photos: symptom?.photos ?? [])
                }
                if let ph = clinic?.phone, let u = URL(string: "tel://" + ph.filter { $0.isNumber || $0 == "+" }) {
                    Button(tr("📞 Hívás: {0}", ph)) {
                        _ = request(via: "phone", reason: reasonNow, timing: timingNow, symptom: symptom)
                        openURL(u)
                    }
                }
            } footer: {
                if clinic == nil { Text(tr("Ha a DentHubon összekötöd a fiókod a rendelőddel, innen közvetlenül foglalhatsz időpontot.")) }
                if sent != nil { Text(tr("✔︎ Elmentve – a rendelő visszaigazolja az időpontot.")).foregroundStyle(Theme.ok) }
            }
        }
        .navigationTitle(tr("Időpontkérés"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $mail) { MailSheet(mail: $0) }
    }

    private func request(via: String, reason: String, timing: String, symptom: SymptomReport?) -> VisitRequest {
        var v = VisitRequest(profileId: model.activeProfile.id, created: Date(), reason: reason, note: note, timing: timing,
                             dayParts: VisitReasons.dayParts.map(\.0).filter { parts.contains($0) }, symptomId: symptom?.id)
        v.sentVia = via
        v.sentAt = Date()
        model.addVisit(v)
        sent = via
        return v
    }
}

/// Home: dentist status, "Panaszom van", "Időpontot kérek" and the last check-up if unknown.
struct DentistCard: View {
    @EnvironmentObject var model: AppModel
    @State private var symptom = false
    @State private var visit = false

    var body: some View {
        let p = model.activeProfile
        if model.settings.isOn("dentist_reminders") && p.canRead {
            let st = dentistStatus(lastCheckup: p.lastCheckup, lastCleaning: p.lastCleaning, today: Date())
            Card {
                Text(model.data.clinic.map { "🦷 " + $0.name } ?? tr("🦷 Fogorvos")).font(.subheadline.bold())
                if let m = st.message { Text(m).font(.caption).foregroundStyle(.secondary) }
                if p.lastCheckup == nil {
                    Text(tr("Mikor voltál utoljára fogorvosi kontrollon?")).font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(DentistIntake.options.filter { $0.0 != "unknown" }, id: \.0) { o in
                                Button(o.1) { var q = p; q.lastCheckup = DentistIntake.date(o.0, today: Date()); model.updateProfile(q) }
                                    .buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                }
                HStack {
                    Button(tr("🩺 Panaszom van")) { symptom = true }.buttonStyle(.borderedProminent)
                    Button(tr("📅 Időpontot kérek")) { visit = true }.buttonStyle(.bordered)
                }
                if st.checkupOverdue {
                    Button(tr("Ma voltam kontrollon")) { var q = p; q.lastCheckup = Date(); model.updateProfile(q) }.font(.caption)
                }
            }
            .onAppear { if model.pendingVisit { model.pendingVisit = false; visit = true } }
            .sheet(isPresented: $symptom) { SymptomFlowView(profile: p, reports: model.data.symptoms).environmentObject(model) }
            .sheet(isPresented: $visit) {
                NavigationStack {
                    VisitRequestView(symptomId: nil) { visit = false }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Bezárás")) { visit = false } } }
                }
                .environmentObject(model)
            }
        }
    }
}

/// Home: the brush's battery was running low last time — charge it.
struct ChargeReminderCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let p = model.activeProfile
        if p.chargeReminder != nil && p.brushType.powered {
            Card {
                Text(tr("🔋 Tedd töltőre a fogkefédet!")).font(.subheadline.bold()).foregroundStyle(Theme.warn)
                Text(tr("A legutóbbi fogmosásnál lemerülőben volt az akkumulátora. Töltsd fel a következő mosás előtt."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(tr("Feltöltöttem")) { var q = p; q.chargeReminder = nil; model.updateProfile(q) }.buttonStyle(.bordered)
            }
        }
    }
}

/// Statistics: recorded complaints.
struct SymptomHistoryCard: View {
    @EnvironmentObject var model: AppModel
    @State private var symptom = false
    @State private var open: SymptomReport?
    @State private var mail: OutgoingMail?

    var body: some View {
        let p = model.activeProfile
        let list = model.data.symptoms.filter { $0.profileId == p.id }.sorted { $0.date > $1.date }
        Card {
            Text(tr("Panaszok")).font(.headline)
            if list.isEmpty { Text(tr("Még nincs rögzített panasz.")).font(.caption).foregroundStyle(.secondary) }
            ForEach(list.prefix(8)) { r in
                Button { open = r } label: {
                    Text(TriageLevel.byId(r.level).emoji + " " + symptomSummary(r)[0] + (r.sentVia != nil ? " ✉︎" : ""))
                        .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            Button(tr("🩺 Új panasz")) { symptom = true }.buttonStyle(.bordered)
        }
        .sheet(isPresented: $symptom) { SymptomFlowView(profile: p, reports: model.data.symptoms).environmentObject(model) }
        .sheet(item: $mail) { MailSheet(mail: $0) }
        .sheet(item: $open) { r in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(symptomSummary(r).dropFirst(), id: \.self) { Text($0).font(.subheadline) }
                        ForEach(Array(model.data.followUps.filter { $0.reportId == r.id }.enumerated()), id: \.offset) { _, f in
                            Text(tr("{0}. nap: {1}", f.day, FollowUps.title(f.answer))).font(.caption).foregroundStyle(.secondary)
                        }
                        PhotoTimelineView(reports: photoTimeline(model.data.symptoms, profileId: p.id, kind: r.kind))
                        Button(tr("✉️ Küldés")) {
                            var s = r
                            let m = clinicEmail(patientName: p.name, symptom: s, visit: nil)
                            s.sentVia = "email"
                            s.sentAt = Date()
                            model.addSymptom(s)
                            open = nil
                            let out = OutgoingMail(to: model.data.clinic?.email, subject: m.subject, body: m.body, photos: s.photos)
                            // Present the mail once this sheet is gone.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { mail = out }
                        }
                        .buttonStyle(.borderedProminent).padding(.top)
                    }
                    .padding()
                }
                .navigationTitle(Symptoms.kind(r.kind).title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Bezárás")) { open = nil } } }
            }
        }
    }
}

/// Settings: link code from the clinic (QR / pasted), or the linked clinic.
struct ClinicLinkSection: View {
    @EnvironmentObject var model: AppModel
    @State private var code = ""
    @State private var error = false
    @State private var scanning = false

    var body: some View {
        Section(tr("🏥 Rendelőm")) {
            if let c = model.data.clinic {
                Text(c.name).font(.headline)
                ForEach([c.address, c.phone, c.email].compactMap { $0 }, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                let queued = model.data.messages.filter { $0.status == "queued" }.count
                if queued > 0 { Text(tr("{0} üzenet vár kézbesítésre a DentHubon keresztül.", queued)).font(.caption).foregroundStyle(.secondary) }
                Button(tr("Összekötés megszüntetése"), role: .destructive) { model.data.clinic = nil }
            } else {
                Text(tr("A rendelőd a DentHubon ad egy összekötő QR-kódot vagy linket. Ezzel a rendelő logója megjelenik indításkor, és nekik küldheted a panaszaidat és időpontkéréseidet."))
                    .font(.caption).foregroundStyle(.secondary)
                Button { scanning = true } label: { Label(tr("QR-kód beolvasása"), systemImage: "qrcode.viewfinder") }
                TextField(tr("…vagy illeszd be a linket"), text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onChange(of: code) { _, _ in error = false }
                if error { Text(tr("Ez nem érvényes DentHub összekötő kód.")).font(.caption).foregroundStyle(Theme.danger) }
                if !code.isEmpty {
                    Button(tr("Összekötés")) {
                        if let c = parseClinicLink(code) { model.pendingClinic = c; code = "" } else { error = true }
                    }
                }
            }
        }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScannerView { raw in
                    scanning = false
                    if let c = parseClinicLink(raw) {
                        model.pendingClinic = c
                    } else if let c = parseCareLink(raw) {
                        model.pendingCare = c
                    } else {
                        error = true
                    }
                }
                .ignoresSafeArea()
                .navigationTitle(tr("QR-kód")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { scanning = false } } }
            }
        }
    }
}

/// Start screen with the DentHub-Brush and the linked clinic's logo.
struct ClinicSplashView: View {
    let clinic: ClinicInfo
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("🪥").font(.system(size: 64))
            Text("DentHub-Brush").font(.largeTitle.bold()).foregroundStyle(Theme.brand)
            Text("×").font(.title2).foregroundStyle(.secondary)
            if let s = clinic.logoUrl, s.hasPrefix("https://"), let u = URL(string: s) {
                AsyncImage(url: u) { img in img.resizable().scaledToFit() } placeholder: { Color.clear }
                    .frame(width: 140, height: 140)
            }
            Text(clinic.name).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            onDone()
        }
    }
}

/// After a brushing: "Minden rendben?" when it was unusual, and "+ Egyéb információ" always.
struct BrushingExtrasView: View {
    @EnvironmentObject var model: AppModel
    let profile: Profile
    let record: BrushRecord
    @State private var ok = false
    @State private var symptom = false

    var body: some View {
        let others = model.records(for: profile.id).filter { $0.id != record.id }.sorted { $0.start > $1.start }
        let today = model.records(for: profile.id).filter { Calendar.current.isDateInToday($0.start) }.count
        let anomaly = brushingAnomaly(durationS: record.durationS, recentDurations: others.prefix(10).map(\.durationS),
                                      todayCount: today, perDay: profile.goals.perDay)
        let ask = anomaly != nil && !ok
        VStack(alignment: .leading, spacing: 6) {
            if ask, let a = anomaly { Text(a).font(.subheadline.bold()) }
            HStack {
                if ask { Button(tr("Minden rendben")) { ok = true }.buttonStyle(.bordered) }
                Button(ask ? tr("Valami gond van") : tr("＋ Egyéb információ, panasz")) { symptom = true }.buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $symptom) { SymptomFlowView(profile: profile, reports: model.data.symptoms).environmentObject(model) }
    }
}
