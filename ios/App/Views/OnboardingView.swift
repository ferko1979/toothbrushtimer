import BrushCore
import SwiftUI

/// Renders OnboardingFlow questions one by one (also used to add a child later).
struct QuestionFlowView: View {
    let flow: OnboardingFlow
    /// Stop when the flow asks "add another child?" (used when adding one child from Settings).
    var stopAtMore = false
    let onFinish: () -> Void

    @State private var question: OnboardingQuestion?
    @State private var text = ""
    @State private var age = 5
    @State private var selected: String?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let q = question {
                if !q.text.isEmpty {
                    Text(q.text).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
                }
                switch q.kind {
                case .choice:
                    ForEach(0..<q.options.count, id: \.self) { i in
                        let opt = q.options[i]
                        Button { selected = opt.0 } label: {
                            Text(opt.1).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                                .background(RoundedRectangle(cornerRadius: 16)
                                    .stroke(selected == opt.0 ? Theme.brand : Color(.systemGray4), lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                case .text:
                    TextField(tr("Név"), text: $text).textFieldStyle(.roundedBorder).font(.title3)
                        .submitLabel(.done)
                        .onSubmit { submit(q) }
                case .number:
                    Picker(tr("Életkor"), selection: $age) {
                        ForEach(1...17, id: \.self) { Text(tr("{0} éves", $0)).tag($0) }
                    }.pickerStyle(.wheel)
                case .avatar:
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                        ForEach(0..<q.options.count, id: \.self) { i in
                            let opt = q.options[i]
                            Button { selected = opt.0 } label: {
                                AvatarCircle(emoji: opt.1, size: 78, selected: selected == opt.0)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                if let e = error { Text(e).foregroundStyle(Theme.danger).font(.footnote) }
                Spacer()
                Button(q.pictureOnly ? "✔︎" : tr("Tovább")) { submit(q) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .disabled((q.kind == .choice || q.kind == .avatar) && selected == nil)
            }
        }
        .padding()
        .background(question?.pictureOnly == true
                    ? LinearGradient(colors: [Theme.kidTop, Theme.kidBottom], startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Color(.systemBackground)], startPoint: .top, endPoint: .bottom))
        .onAppear { load() }
    }

    private func load() {
        question = flow.nextQuestion()
        selected = question?.defaultValue
        text = ""
        error = nil
        if question == nil || (stopAtMore && question?.id == "more") { onFinish() }
    }

    private func submit(_ q: OnboardingQuestion) {
        let value: String
        switch q.kind {
        case .choice, .avatar: value = selected ?? ""
        case .text: value = text
        case .number: value = String(age)
        }
        do {
            try flow.answer(value)
            load()
        } catch {
            self.error = tr("Kérlek, ellenőrizd a választ.")
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var step = 0
    @State private var name = ""
    @State private var flow = OnboardingFlow()
    @State private var brushType: BrushType = .manual
    @State private var goals = Goals()
    @State private var micOK = false
    @State private var notifOK = false
    @State private var lastVisit: String?
    @State private var lastCleaning: String?
    @State private var wantVisit = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: QuestionFlowView(flow: flow) { step = 2 }
                case 2: brushTypeStep
                case 3: goalsStep
                case 4: dentistStep
                default: permissionsStep
                }
            }
            .animation(.default, value: step)
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Picker("Nyelv / Language", selection: Binding(get: { I18n.lang }, set: { model.data.settings.language = $0 })) {
                Text("Magyar").tag("hu")
                Text("English").tag("en")
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 240)
            .frame(maxWidth: .infinity, alignment: .trailing)
            Spacer()
            Text("🪥").font(.system(size: 70))
            Text(tr("Üdv!")).font(.largeTitle.bold())
            Text(tr("Az app a hang alapján méri a fogmosásod idejét: a víz elzárásától az öblítésig. Hangfelvétel nem készül, minden a telefonodon marad."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            TextField(tr("Hogy szólíthatunk?"), text: $name).textFieldStyle(.roundedBorder).font(.title3)
                .submitLabel(.done)
                .onSubmit(startFlow)
            Spacer()
            Button(tr("Tovább"), action: startFlow).buttonStyle(.borderedProminent).controlSize(.large)
        }.padding()
    }

    private func startFlow() {
        flow = OnboardingFlow(adultName: name.trimmingCharacters(in: .whitespaces).isEmpty ? tr("Én") : name)
        step = 1
    }

    private var brushTypeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Milyen fogkefét használsz?")).font(.title2.bold())
            Picker(tr("Fogkefe"), selection: $brushType) {
                Text(tr("Kézi")).tag(BrushType.manual)
                Text(tr("Szónikus")).tag(BrushType.electric)
                Text(tr("Forgófejes")).tag(BrushType.oscillating)
            }.pickerStyle(.segmented)
            Text(brushType.title).font(.headline)
            Text(brushType.info).foregroundStyle(.secondary)
            Spacer()
            Button(tr("Tovább")) { step = 3 }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Mi a célod?")).font(.title2.bold())
            Text(tr("A fogorvosok naponta kétszer 2 percet javasolnak.")).foregroundStyle(.secondary)
            Stepper(tr("Naponta {0}×", goals.perDay), value: Binding(get: { goals.perDay }, set: { goals = Goals(perDay: $0, targetS: goals.targetS) }), in: 1...4)
            Stepper(tr("Célidő: {0}", formatClock(goals.targetS)), value: Binding(get: { goals.targetS }, set: { goals = Goals(perDay: goals.perDay, targetS: $0) }), in: 30...300, step: 15)
            ForEach(goals.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warn) }
            Spacer()
            Button(tr("Tovább")) { step = 4 }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private var dentistStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("🦷 Fogorvos")).font(.title2.bold())
                Text(tr("Ebből tudjuk, mikor esedékes a következő kontroll és fogkő-eltávolítás. Szólunk, ha itt az ideje."))
                    .foregroundStyle(.secondary)
                Text(tr("Mikor voltál utoljára fogorvosi kontrollon?")).font(.headline)
                ForEach(DentistIntake.options, id: \.0) { o in
                    Button { lastVisit = o.0 } label: {
                        Text(o.1).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading).padding(.horizontal, 12)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(lastVisit == o.0 ? Theme.brand : Color(.separator), lineWidth: lastVisit == o.0 ? 2 : 1))
                    }
                    .buttonStyle(.plain)
                }
                Text(tr("És fogkő-eltávolításon?")).font(.headline)
                Picker(tr("És fogkő-eltávolításon?"), selection: Binding(get: { lastCleaning ?? "" }, set: { lastCleaning = $0 })) {
                    ForEach(DentistIntake.options, id: \.0) { Text($0.1).tag($0.0) }
                }
                .pickerStyle(.menu)
                Toggle(tr("Szeretnék időpontot kérni (kontroll vagy panasz miatt)"), isOn: $wantVisit)
                Button(lastVisit == nil ? tr("Kihagyom") : tr("Tovább")) { step = 5 }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Engedélyek")).font(.title2.bold())
            Card {
                Text(tr("🎙️ Mikrofon")).font(.headline)
                Text(tr("A fogmosás felismeréséhez. A hang csak a telefonon, a memóriában dolgozódik fel.")).font(.subheadline).foregroundStyle(.secondary)
                Button(micOK ? tr("Engedélyezve ✔︎") : tr("Engedélyezés")) { AudioCapture.requestPermission { micOK = $0 } }.disabled(micOK)
            }
            Card {
                Text(tr("🔔 Emlékeztetők")).font(.headline)
                Text(tr("Reggel ébredés után és 15 perccel lefekvés előtt. A Beállításokban módosítható.")).font(.subheadline).foregroundStyle(.secondary)
                Button(notifOK ? tr("Engedélyezve ✔︎") : tr("Engedélyezés")) { NotificationScheduler.requestAuthorization { notifOK = $0 } }.disabled(notifOK)
            }
            Spacer()
            Button(tr("Kezdjük!")) { finish() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private func finish() {
        var profiles = flow.profiles()
        profiles[0].brushType = brushType
        profiles[0].goals = goals
        profiles[0].lastCheckup = lastVisit.flatMap { DentistIntake.date($0, today: Date()) }
        profiles[0].lastCleaning = lastCleaning.flatMap { DentistIntake.date($0, today: Date()) }
        model.pendingVisit = wantVisit
        model.data.profiles = profiles
        model.data.activeProfileId = "me"
        model.data.onboarded = true
        model.pushContextToWatch()
        NotificationScheduler.reschedule(model: model)
    }
}
