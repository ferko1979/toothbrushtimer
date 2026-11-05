import BrushCore
import EventKit
import EventKitUI
import SwiftUI

// Messenger with the linked clinic, appointment offers / confirmations, calendar and reminders.
// Same as android/app/.../MessengerScreens.kt. Delivery through DentHub needs its server
// (docs/DENTHUB-API.md): until then app messages wait ("queued"), e-mails go out right away, and
// every e-mail is also kept here as a message.

/// The system "new event" sheet with the appointment filled in (iOS 17: no calendar permission needed).
struct CalendarEventSheet: UIViewControllerRepresentable {
    let appointment: Appointment
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let vc = EKEventEditViewController()
        vc.eventStore = store
        let e = EKEvent(eventStore: store)
        e.title = Messaging.title(appointment)
        if let start = Messaging.startOf(appointment) {
            e.startDate = start
            e.endDate = start.addingTimeInterval(Double(appointment.durationMin) * 60)
        }
        e.location = appointment.address ?? appointment.clinicName
        e.notes = [appointment.clinicName, appointment.doctor, appointment.note.isEmpty ? nil : appointment.note].compactMap { $0 }.joined(separator: "\n")
        e.addAlarm(EKAlarm(relativeOffset: -24 * 3600))
        e.addAlarm(EKAlarm(relativeOffset: -2 * 3600))
        vc.event = e
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { dismiss() }
    }
}

/// Home: 💬 with the number of unread clinic messages; shown once there is a conversation or a linked clinic.
struct MessagesButton: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var router: AppRouter

    var body: some View {
        let p = model.activeProfile
        Group {
            let unread = Messaging.unread(model.data.messages, profileId: p.id)
            Button { router.messagesRequest = UUID() } label: {
                Image(systemName: unread > 0 ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    .font(.title2)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Text("\(unread)").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(4).background(Circle().fill(Theme.danger)).offset(x: 8, y: -8)
                        }
                    }
            }
            .accessibilityLabel(tr("Üzenetek"))
        }
    }
}

/// Home: the next appointment.
struct UpcomingAppointmentCard: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        if let a = Messaging.upcoming(model.data.appointments, profileId: model.activeProfile.id, now: Date()).first {
            AppointmentCard(appointment: a, compact: true)
        }
    }
}

struct AppointmentCard: View {
    @EnvironmentObject var model: AppModel
    let appointment: Appointment
    var compact = false
    @State private var calendar: Appointment?
    @State private var mail: OutgoingMail?

    var body: some View {
        let a = appointment
        Card {
            Text(a.status == "offered" ? tr("📅 Időpont-ajánlat") : a.status == "requested" ? tr("📅 Időpontkérés elküldve")
                 : a.status == "cancelled" ? tr("📅 Lemondott időpont") : tr("📅 Fogorvosi időpont"))
                .font(.subheadline.bold()).foregroundStyle(a.status == "offered" ? Theme.warn : Theme.brand)
            Text(Messaging.when(a)).font(.title3.bold())
            Text([VisitReasons.title(a.reason), a.doctor, a.clinicName].compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if !a.note.isEmpty && !compact { Text(a.note).font(.caption) }
            HStack {
                if a.status == "offered" {
                    Button(tr("Elfogadom")) {
                        var ok = a
                        ok.status = "confirmed"
                        ok.calendarAdded = true
                        model.putAppointment(ok)
                        mail = model.sendClinicMessage(Messaging.acceptText(ok), to: "admin", alsoEmail: false, appointmentId: ok.id)
                        calendar = ok
                    }.buttonStyle(.borderedProminent)
                    Button(tr("Másikat kérek")) {
                        var no = a
                        no.status = "cancelled"
                        model.putAppointment(no)
                        mail = model.sendClinicMessage(Messaging.declineText(a), to: "admin", alsoEmail: false, appointmentId: a.id)
                    }.buttonStyle(.bordered)
                } else if a.status == "confirmed" {
                    Button(a.calendarAdded ? tr("📅 Újra a naptárba") : tr("📅 Naptárba")) {
                        var c = a
                        c.calendarAdded = true
                        model.putAppointment(c)
                        calendar = c
                    }.buttonStyle(.bordered)
                    if !compact {
                        Button(tr("Lemondás"), role: .destructive) {
                            var no = a
                            no.status = "cancelled"
                            model.putAppointment(no)
                            mail = model.sendClinicMessage(tr("❌ Le kell mondanom az időpontot: {0}", Messaging.when(a)), to: "admin",
                                                           alsoEmail: true, appointmentId: a.id)
                        }
                    }
                }
            }
            if a.status == "confirmed" && model.settings.isOn("appointment_reminders", platform: .ios) {
                Text(tr("Emlékeztető előtte egy nappal és két órával.")).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $calendar) { CalendarEventSheet(appointment: $0).ignoresSafeArea() }
        .sheet(item: $mail) { MailSheet(mail: $0) }
    }
}

/// The conversation with the clinic: bubbles, delivery state, appointment cards, composer.
struct MessengerView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var to = "doctor"
    @State private var text = ""
    @State private var alsoEmail = false
    @State private var mail: OutgoingMail?
    @State private var gotAppointment = false
    @State private var visit = false
    @State private var complaint = false

    var body: some View {
        let p = model.activeProfile
        let clinic = model.data.clinic
        let thread = Messaging.thread(model.data.messages, profileId: p.id)
        let appToApp = clinic?.allowsMessaging == true && model.settings.isOn("app_messaging", platform: .ios)
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            if clinic == nil {
                                Card {
                                    Text(tr("Még nincs összekötött rendelő")).font(.headline)
                                    Text(tr("A rendelőd a DentHubon ad egy összekötő QR-kódot vagy linket (Beállítások › Rendelőm). Utána itt írhatsz az orvosnak vagy a recepciónak, és itt jönnek az időpont-ajánlatok. A telefonon kapott időpontot már most felveheted: „Időpontot kaptam”."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else if thread.isEmpty {
                                Card {
                                    Text(tr("Írj a rendelődnek")).font(.headline)
                                    Text(tr("Kérdés, panasz vagy időpontkérés – az orvosnak vagy a recepciónak. A sürgős panaszt a „Panaszom van” kérdéseivel küldd, fotóval."))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(thread) { m in bubble(m).id(m.id) }
                            if let a = Messaging.upcoming(model.data.appointments, profileId: p.id, now: Date()).first {
                                AppointmentCard(appointment: a)
                            }
                        }
                        .padding()
                    }
                    .onAppear { model.markRead(p.id); if let last = thread.last { proxy.scrollTo(last.id, anchor: .bottom) } }
                    .onChange(of: thread.count) { _, _ in if let last = thread.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
                }
                composer(clinic: clinic, appToApp: appToApp)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(clinic?.name ?? tr("Üzenetek"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Bezárás")) { dismiss() } }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(clinic?.name ?? tr("Üzenetek")).font(.headline)
                        Text(clinic == nil ? tr("Nincs összekötött rendelő") : appToApp ? tr("DentHub üzenetküldő · e-mail")
                             : clinic?.email != nil ? tr("E-mailben megy, itt is megmarad") : tr("A rendelő még nem fogad üzenetet"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .sheet(item: $mail) { MailSheet(mail: $0) }
            .sheet(isPresented: $gotAppointment) { AppointmentEntryView().environmentObject(model) }
            .sheet(isPresented: $visit) { NavigationStack { VisitRequestView(symptomId: nil) { visit = false } }.environmentObject(model) }
            .sheet(isPresented: $complaint) { SymptomFlowView(profile: p, reports: model.data.symptoms).environmentObject(model) }
        }
    }

    private func bubble(_ m: ClinicMessage) -> some View {
        let mine = m.fromPatient
        return VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 3) {
                if !mine || m.recipient == "admin" {
                    Text(Recipients.title(m.recipient)).font(.caption2).foregroundStyle(mine ? .white.opacity(0.8) : .secondary)
                }
                Text(m.text).foregroundStyle(mine ? .white : .primary)
                if !m.photos.isEmpty { Text(tr("📷 {0} fotó", m.photos.count)).font(.caption).foregroundStyle(mine ? .white : .secondary) }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(mine ? Theme.brand : Color(.secondarySystemGroupedBackground)))
            .frame(maxWidth: 300, alignment: mine ? .trailing : .leading)
            Text(m.date.formatted(date: .abbreviated, time: .shortened) + (mine ? " · " + Messaging.statusText(m) : ""))
                .font(.caption2).foregroundStyle(.secondary)
            if !mine, let id = m.appointmentId, let a = model.data.appointments.first(where: { $0.id == id }), a.status == "offered" {
                AppointmentCard(appointment: a)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }

    private func composer(clinic: ClinicInfo?, appToApp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Recipients.all, id: \.0) { r in ChoiceChip(title: r.1, selected: to == r.0) { to = r.0 } }
                    ChoiceChip(title: tr("📅 Időpont kérése"), selected: false) { visit = true }
                    ChoiceChip(title: tr("Időpontot kaptam"), selected: false) { gotAppointment = true }
                    ChoiceChip(title: tr("🩺 Panasz"), selected: false) { complaint = true }
                }
            }
            HStack {
                TextField(tr("Üzenet…"), text: $text, axis: .vertical).lineLimit(1...5).textFieldStyle(.roundedBorder)
                Button(tr("Küldés")) {
                    mail = model.sendClinicMessage(text.trimmingCharacters(in: .whitespacesAndNewlines), to: to, alsoEmail: alsoEmail)
                    text = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || clinic == nil || (clinic?.email == nil && !appToApp))
            }
            if appToApp && clinic?.email != nil { Toggle(tr("E-mailben is"), isOn: $alsoEmail).font(.caption) }
        }
        .padding(10)
        .background(Color(.systemBackground))
    }
}

/// "Időpontot kaptam": the patient enters an appointment they got by phone or at the desk.
struct AppointmentEntryView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!)!
    @State private var reason = "checkup"
    @State private var doctor = ""
    @State private var calendar: Appointment?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(tr("Időpont"), selection: $date, in: Date()...)
                Picker(tr("Ok"), selection: $reason) {
                    ForEach(VisitReasons.all, id: \.0) { Text($0.1).tag($0.0) }
                }
                TextField(tr("Orvos (nem kötelező)"), text: $doctor)
            }
            .navigationTitle(tr("Időpontot kaptam"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Mégse")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr("Mentés és naptárba")) {
                        let c = model.data.clinic
                        let a = Appointment(profileId: model.activeProfile.id, start: Messaging.format(date), reason: reason,
                                            clinicName: c?.name, doctor: doctor.isEmpty ? nil : doctor, address: c?.address,
                                            status: "confirmed", calendarAdded: true)
                        model.putAppointment(a)
                        calendar = a
                    }
                }
            }
            .sheet(item: $calendar, onDismiss: { dismiss() }) { CalendarEventSheet(appointment: $0).ignoresSafeArea() }
        }
    }
}
