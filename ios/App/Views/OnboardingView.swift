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
                    TextField("Név", text: $text).textFieldStyle(.roundedBorder).font(.title3)
                case .number:
                    Picker("Életkor", selection: $age) {
                        ForEach(1...17, id: \.self) { Text("\($0) éves").tag($0) }
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
                Button(q.pictureOnly ? "✔︎" : "Tovább") { submit(q) }
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
            self.error = "Kérlek, ellenőrizd a választ."
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

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: welcome
                case 1: QuestionFlowView(flow: flow) { step = 2 }
                case 2: brushTypeStep
                case 3: goalsStep
                default: permissionsStep
                }
            }
            .animation(.default, value: step)
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🪥").font(.system(size: 70))
            Text("Üdv!").font(.largeTitle.bold())
            Text("Az app a hang alapján méri a fogmosásod idejét: a víz elzárásától az öblítésig. Hangfelvétel nem készül, minden a telefonodon marad.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            TextField("Hogy szólíthatunk?", text: $name).textFieldStyle(.roundedBorder).font(.title3)
            Spacer()
            Button("Tovább") {
                flow = OnboardingFlow(adultName: name.trimmingCharacters(in: .whitespaces).isEmpty ? "Én" : name)
                step = 1
            }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding()
    }

    private var brushTypeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Milyen fogkefét használsz?").font(.title2.bold())
            Picker("Fogkefe", selection: $brushType) {
                Text("Kézi").tag(BrushType.manual)
                Text("Elektromos").tag(BrushType.electric)
            }.pickerStyle(.segmented)
            Text(brushType == .electric
                 ? "Elektromos fogkefénél a motor zúgását is figyeljük, és az első 3 fogmosásból megtanuljuk a fogkeféd hangját."
                 : "Kézi fogkefénél a súrolás ritmusát figyeljük. Más zúgását (pl. valaki más elektromos fogkeféjét) figyelmen kívül hagyjuk.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Tovább") { step = 3 }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mi a célod?").font(.title2.bold())
            Text("A fogorvosok naponta kétszer 2 percet javasolnak.").foregroundStyle(.secondary)
            Stepper("Naponta \(goals.perDay)×", value: Binding(get: { goals.perDay }, set: { goals = Goals(perDay: $0, targetS: goals.targetS) }), in: 1...4)
            Stepper("Célidő: \(formatClock(goals.targetS))", value: Binding(get: { goals.targetS }, set: { goals = Goals(perDay: goals.perDay, targetS: $0) }), in: 30...300, step: 15)
            ForEach(goals.warnings, id: \.self) { Text($0).font(.footnote).foregroundStyle(Theme.warn) }
            Spacer()
            Button("Tovább") { step = 4 }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Engedélyek").font(.title2.bold())
            Card {
                Text("🎙️ Mikrofon").font(.headline)
                Text("A fogmosás felismeréséhez. A hang csak a telefonon, a memóriában dolgozódik fel.").font(.subheadline).foregroundStyle(.secondary)
                Button(micOK ? "Engedélyezve ✔︎" : "Engedélyezés") { AudioCapture.requestPermission { micOK = $0 } }.disabled(micOK)
            }
            Card {
                Text("🔔 Emlékeztetők").font(.headline)
                Text("Reggel ébredés után és 15 perccel lefekvés előtt. A Beállításokban módosítható.").font(.subheadline).foregroundStyle(.secondary)
                Button(notifOK ? "Engedélyezve ✔︎" : "Engedélyezés") { NotificationScheduler.requestAuthorization { notifOK = $0 } }.disabled(notifOK)
            }
            Spacer()
            Button("Kezdjük!") { finish() }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }.padding()
    }

    private func finish() {
        var profiles = flow.profiles()
        profiles[0].brushType = brushType
        profiles[0].goals = goals
        model.data.profiles = profiles
        model.data.activeProfileId = "me"
        model.data.onboarded = true
        model.pushContextToWatch()
        NotificationScheduler.reschedule(model: model)
    }
}
