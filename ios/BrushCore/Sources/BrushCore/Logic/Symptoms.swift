import Foundation

// Complaints, step-by-step questions, triage, the doctor's summary, visit requests and the linked
// clinic. Same as android/brushcore/.../Symptoms.kt (tests: SymptomsTests.swift / SymptomsTest.kt).
// The advice is general first aid and guidance, not a diagnosis.

/// One answered question (kept in order).
public struct SymptomAnswer: Codable, Equatable {
    public var question: String
    public var options: [String]
    public init(question: String, options: [String]) { self.question = question; self.options = options }
}

/// One recorded complaint with the answers to its questions.
public struct SymptomReport: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var date: Date
    public var kind: String
    public var answers: [SymptomAnswer] = []
    public var level: String
    /// File names of the photos in the app's photo folder.
    public var photos: [String] = []
    public var note = ""
    public var sentAt: Date? = nil
    /// "message" (clinic inbox) or "email"
    public var sentVia: String? = nil

    public init(profileId: String, date: Date, kind: String, answers: [SymptomAnswer], level: String,
                photos: [String] = [], note: String = "") {
        self.profileId = profileId; self.date = date; self.kind = kind; self.answers = answers
        self.level = level; self.photos = photos; self.note = note
    }

    public func answer(_ q: String) -> [String] { answers.first { $0.question == q }?.options ?? [] }
}

public struct SymptomOption: Equatable, Hashable {
    public let id: String
    public let label: String
}

public struct SymptomQuestion: Equatable {
    public let id: String
    public let title: String
    public let options: [SymptomOption]
    public var multi = false
}

public enum TriageLevel: String, CaseIterable {
    case selfCare = "self_care", monitor, soon, urgent, emergency

    public var rank: Int { TriageLevel.allCases.firstIndex(of: self)! }

    public var title: String {
        switch self {
        case .selfCare: return tr("Otthon kezelhető")
        case .monitor: return tr("Figyeld meg")
        case .soon: return tr("Pár napon belül nézesse meg a fogorvos")
        case .urgent: return tr("Még ma keresd a fogorvosodat")
        case .emergency: return tr("Azonnali ellátás kell")
        }
    }

    public var emoji: String {
        switch self {
        case .selfCare: return "🟢"
        case .monitor: return "🟡"
        case .soon: return "🟠"
        case .urgent: return "🔴"
        case .emergency: return "🚨"
        }
    }

    public static func byId(_ id: String) -> TriageLevel { TriageLevel(rawValue: id) ?? .monitor }
}

public struct TriageResult: Equatable {
    public let level: TriageLevel
    public let advice: [String]
    /// What to photograph, or nil when a photo does not help.
    public let photo: String?
    public let suggestMessage: Bool
    public let suggestBooking: Bool
}

public enum Symptoms {
    public struct Kind: Equatable {
        public let id: String
        public let emoji: String
        public let title: String
    }

    public static var kinds: [Kind] {
        [
            Kind(id: "bleeding", emoji: "🩸", title: tr("Vérzik az ínyem")),
            Kind(id: "pain", emoji: "😖", title: tr("Fáj a fogam")),
            Kind(id: "sensitivity", emoji: "🥶", title: tr("Érzékeny a fogam")),
            Kind(id: "swelling", emoji: "😮", title: tr("Duzzanat (íny, arc)")),
            Kind(id: "stuck", emoji: "🦴", title: tr("Valami beszorult a fogaim közé")),
            Kind(id: "chipped", emoji: "🦷", title: tr("Letört egy darab (fog, tömés, korona)")),
            Kind(id: "knocked", emoji: "💥", title: tr("Kiesett egy fogam (baleset)")),
            Kind(id: "loose", emoji: "〰️", title: tr("Mozog egy fogam")),
            Kind(id: "sore", emoji: "⚪", title: tr("Afta vagy seb a számban")),
            Kind(id: "injury", emoji: "🩹", title: tr("Ráharaptam / megsérült a szám")),
            Kind(id: "jaw", emoji: "🫦", title: tr("Állkapocs, rágás közbeni fájdalom")),
            Kind(id: "breath", emoji: "💨", title: tr("Rossz lehelet vagy rossz íz")),
            Kind(id: "braces", emoji: "🔩", title: tr("Fogszabályzó gond")),
            Kind(id: "other", emoji: "📝", title: tr("Egyéb")),
        ]
    }

    public static func kind(_ id: String) -> Kind { kinds.first { $0.id == id } ?? kinds[kinds.count - 1] }

    private static func o(_ id: String, _ label: String) -> SymptomOption { SymptomOption(id: id, label: label) }
    private static var yesNo: [SymptomOption] { [o("yes", tr("Igen")), o("no", tr("Nem"))] }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    public static func question(_ id: String) -> SymptomQuestion? {
        func q(_ title: String, _ opts: [SymptomOption], multi: Bool = false) -> SymptomQuestion {
            SymptomQuestion(id: id, title: title, options: opts, multi: multi)
        }
        switch id {
        case "jaw": return q(tr("Melyik fogsoron?"), [o("upper", tr("Felső")), o("lower", tr("Alsó")), o("both", tr("Mindkettő")), o("unsure", tr("Nem tudom"))])
        case "side": return q(tr("Melyik oldalon?"), [o("left", tr("Bal")), o("right", tr("Jobb")), o("front", tr("Elöl")), o("several", tr("Több helyen"))])
        case "zone": return q(tr("Melyik fogaknál?"), [o("front", tr("Elülső fogak")), o("middle", tr("Szemfog, kisőrlők")), o("back", tr("Hátsó őrlőfogak")), o("unsure", tr("Nem tudom"))])
        case "pain": return q(tr("Mennyire fáj?"), [o("none", tr("Nem fáj")), o("mild", tr("Enyhén")), o("moderate", tr("Közepesen")), o("severe", tr("Erősen")), o("unbearable", tr("Elviselhetetlenül"))])
        case "since": return q(tr("Mióta tart?"), [o("today", tr("Ma kezdődött")), o("days", tr("Pár napja")), o("week", tr("Egy hete vagy régebben")), o("recurring", tr("Visszatérő"))])
        case "trigger": return q(tr("Mikor érzed? (több is lehet)"), [o("cold", tr("Hidegre")), o("hot", tr("Melegre")), o("sweet", tr("Édesre")), o("chewing", tr("Rágáskor, harapáskor")), o("spontaneous", tr("Magától is")), o("night", tr("Éjjel"))], multi: true)
        case "bleed_when": return q(tr("Mikor vérzik? (több is lehet)"), [o("brushing", tr("Fogmosáskor")), o("flossing", tr("Fogselyemnél")), o("eating", tr("Evéskor")), o("spontaneous", tr("Magától"))], multi: true)
        case "bleed_amount": return q(tr("Mennyire vérzik?"), [o("drops", tr("Pár csepp")), o("lot", tr("Sokat")), o("nonstop", tr("Nem áll el"))])
        case "swelling_also": return q(tr("Duzzadt is a környéke?"), yesNo)
        case "swell_where": return q(tr("Hol duzzadt? (több is lehet)"), [o("gum", tr("Íny")), o("face", tr("Arc")), o("lip", tr("Ajak")), o("under_jaw", tr("Áll alatt, nyakon"))], multi: true)
        case "fever": return q(tr("Lázas vagy, rossz a közérzeted?"), yesNo)
        case "breathing": return q(tr("Nehezen nyelsz vagy veszel levegőt?"), yesNo)
        case "stuck_tried": return q(tr("Próbáltad már fogselyemmel vagy fogközkefével?"), [o("still", tr("Igen, de még ott van")), o("not_yet", tr("Még nem"))])
        case "what_broke": return q(tr("Mi tört le?"), [o("tooth", tr("Fog")), o("filling", tr("Tömés")), o("crown", tr("Korona, híd")), o("denture", tr("Fogsor"))])
        case "sharp": return q(tr("Éles a széle, sérti a nyelved vagy az arcod?"), yesNo)
        case "piece": return q(tr("Megvan a letört darab?"), yesNo)
        case "tooth_type": return q(tr("Milyen fog esett ki?"), [o("permanent", tr("Maradó fog (felnőtt)")), o("baby", tr("Tejfog (gyerek)"))])
        case "minutes": return q(tr("Mennyi ideje történt?"), [o("lt30", tr("Fél órán belül")), o("lt60", tr("Fél–egy órája")), o("gt60", tr("Több mint egy órája"))])
        case "wound_bleed": return q(tr("Elállt a vérzés (10–15 perc nyomás után)?"), [o("stopped", tr("Igen")), o("slowing", tr("Csillapodik")), o("not_stopping", tr("Nem áll el")), o("none", tr("Nem vérzett"))])
        case "wound_deep": return q(tr("Mély vagy 1 cm-nél hosszabb a seb?"), yesNo)
        case "injury_cause": return q(tr("Mi történt?"), [o("bite", tr("Ráharaptam")), o("hit", tr("Ütés, esés")), o("burn", tr("Megégettem (forró étel)")), o("wire", tr("Fogszabályzó drót sértette"))])
        case "sore_where": return q(tr("Hol van?"), [o("tongue", tr("Nyelv")), o("cheek", tr("Arc belső oldala")), o("gum", tr("Íny")), o("lip", tr("Ajak")), o("palate", tr("Szájpadlás"))])
        case "sore_weeks": return q(tr("Mióta van?"), [o("lt1", tr("Egy hétnél rövidebb ideje")), o("1to2", tr("1–2 hete")), o("gt2", tr("Több mint 2 hete"))])
        case "loose_cause": return q(tr("Mi okozhatta?"), [o("injury", tr("Ütés, baleset")), o("slowly", tr("Lassan kezdett mozogni")), o("changing", tr("Gyerek, fogváltás"))])
        case "jaw_sym": return q(tr("Mit érzel? (több is lehet)"), [o("click", tr("Kattog, ropog")), o("chew_pain", tr("Rágáskor fáj")), o("open", tr("Nem tudom nagyra nyitni")), o("morning", tr("Reggel fáj, fogcsikorgatás"))], multi: true)
        case "taste": return q(tr("Rossz ízt vagy gennyet érzel a szádban?"), yesNo)
        case "braces_issue": return q(tr("Mi a gond?"), [o("wire", tr("Szúr a drót")), o("bracket", tr("Levált egy bracket")), o("adjust", tr("Fáj az utánállítás után")), o("aligner", tr("Eltört a sín, aligner"))])
        default: return nil
        }
    }

    /// The questions of a complaint, in order; later ones may depend on earlier answers.
    public static func questionsFor(_ kind: String, _ a: [SymptomAnswer]) -> [String] {
        let yes = { (q: String) in a.first { $0.question == q }?.options.contains("yes") == true }
        switch kind {
        case "bleeding": return ["jaw", "side", "bleed_when", "bleed_amount", "since"]
        case "pain": return ["jaw", "side", "zone", "pain", "trigger", "since", "swelling_also"] + (yes("swelling_also") ? ["fever", "breathing"] : [])
        case "sensitivity": return ["jaw", "side", "trigger", "since"]
        case "swelling": return ["swell_where", "jaw", "side", "pain", "fever", "breathing"]
        case "stuck": return ["jaw", "side", "stuck_tried", "pain"]
        case "chipped": return ["what_broke", "jaw", "side", "zone", "pain", "sharp", "piece"]
        case "knocked": return ["tooth_type", "minutes", "wound_bleed"]
        case "loose": return ["loose_cause", "jaw", "side", "pain"]
        case "sore": return ["sore_where", "sore_weeks", "pain"]
        case "injury": return ["injury_cause", "sore_where", "wound_bleed", "wound_deep", "pain"]
        case "jaw": return ["jaw_sym", "side", "since"]
        case "breath": return ["since", "taste"]
        case "braces": return ["braces_issue", "pain"]
        default: return ["since", "pain"]
        }
    }

    /// A short label of a question for the summary ("Fogsor: Felső").
    public static func shortLabel(_ q: String) -> String {
        switch q {
        case "jaw": return tr("Fogsor")
        case "side": return tr("Oldal")
        case "zone": return tr("Fogak")
        case "pain": return tr("Fájdalom")
        case "since": return tr("Mióta")
        case "trigger": return tr("Kiváltó ok")
        case "bleed_when": return tr("Mikor vérzik")
        case "bleed_amount": return tr("Vérzés mértéke")
        case "swelling_also": return tr("Duzzanat")
        case "swell_where": return tr("Duzzanat helye")
        case "fever": return tr("Láz, rossz közérzet")
        case "breathing": return tr("Nyelési/légzési nehézség")
        case "stuck_tried": return tr("Fogselyem")
        case "what_broke": return tr("Mi tört le")
        case "sharp": return tr("Éles szél")
        case "piece": return tr("Megvan a darab")
        case "tooth_type": return tr("Fog")
        case "minutes": return tr("Ideje")
        case "wound_bleed": return tr("Vérzés")
        case "wound_deep": return tr("Mély seb")
        case "injury_cause", "loose_cause": return tr("Ok")
        case "sore_where": return tr("Hely")
        case "sore_weeks": return tr("Mióta")
        case "jaw_sym": return tr("Tünetek")
        case "taste": return tr("Rossz íz, genny")
        case "braces_issue": return tr("Gond")
        default: return q
        }
    }
}

/// Step by step: complaint, then its questions; `result()` once `next()` is nil.
public final class SymptomFlow {
    /// The same complaint in the last 30 days (before this one).
    public let recentSameKind: (String) -> Int
    public let child: Bool
    public private(set) var kind: String?
    public private(set) var answers: [SymptomAnswer] = []

    public init(recentSameKind: @escaping (String) -> Int = { _ in 0 }, child: Bool = false) {
        self.recentSameKind = recentSameKind
        self.child = child
    }

    public func next() -> SymptomQuestion? {
        guard let k = kind else {
            return SymptomQuestion(id: "kind", title: tr("Mi a gond?"),
                                   options: Symptoms.kinds.map { SymptomOption(id: $0.id, label: "\($0.emoji) \($0.title)") })
        }
        let done = Set(answers.map(\.question))
        guard let id = Symptoms.questionsFor(k, answers).first(where: { !done.contains($0) }) else { return nil }
        return Symptoms.question(id)
    }

    public enum FlowError: Error { case finished, invalid }

    public func answer(_ ids: [String]) throws {
        guard let q = next() else { throw FlowError.finished }
        guard !ids.isEmpty, ids.allSatisfy({ id in q.options.contains { $0.id == id } }) else { throw FlowError.invalid }
        if q.id == "kind" {
            kind = ids[0]
            answers = []
        } else {
            answers.append(SymptomAnswer(question: q.id, options: q.multi ? ids : [ids[0]]))
        }
    }

    /// One step back; false when already at the first question.
    @discardableResult
    public func back() -> Bool {
        if !answers.isEmpty { answers.removeLast(); return true }
        if kind != nil { kind = nil; return true }
        return false
    }

    /// 0…1 for a progress bar.
    public var progress: Double {
        guard let k = kind else { return 0 }
        let total = Symptoms.questionsFor(k, answers).count + 1
        return Double(answers.count + 1) / Double(total)
    }

    public func result() -> TriageResult {
        triage(kind ?? "other", answers, recentSameKind: kind.map(recentSameKind) ?? 0, child: child)
    }

    public func report(profileId: String, now: Date, photos: [String] = [], note: String = "") -> SymptomReport {
        SymptomReport(profileId: profileId, date: now, kind: kind ?? "other", answers: answers,
                      level: result().level.rawValue, photos: photos, note: note)
    }
}

/// Rules behind the advice. Order: emergencies first, then the complaint, then pain and recurrence.
// swiftlint:disable:next cyclomatic_complexity function_body_length
public func triage(_ kind: String, _ a: [SymptomAnswer], recentSameKind: Int = 0, child: Bool = false) -> TriageResult {
    func has(_ q: String, _ v: String) -> Bool { a.first { $0.question == q }?.options.contains(v) == true }
    var level = TriageLevel.selfCare
    var advice: [String] = []
    var photo: String?
    func atLeast(_ l: TriageLevel) { if l.rank > level.rank { level = l } }
    let closePhoto = tr("Fotózd le közelről, jó fényben (pl. a telefon lámpájával).")

    if has("breathing", "yes") {
        atLeast(.emergency)
        advice.append(tr("Duzzanat mellett nehezített nyelés vagy légzés: azonnal hívd a 112-t, vagy menj sürgősségi ügyeletre!"))
    }
    if has("fever", "yes") {
        atLeast(.urgent)
        advice.append(tr("Láz és duzzanat együtt fertőzésre utalhat: még ma beszélj a fogorvosoddal vagy az ügyelettel."))
    }

    switch kind {
    case "bleeding":
        if has("bleed_amount", "nonstop") {
            atLeast(.urgent)
            advice.append(tr("Nyomd tiszta gézzel 10–15 percig. Ha így sem áll el, keresd még ma a fogorvost vagy az ügyeletet."))
        } else if has("bleed_amount", "lot") || has("bleed_when", "spontaneous") {
            atLeast(.soon)
        } else if has("since", "week") || has("since", "recurring") {
            atLeast(.soon)
        }
        advice.append(tr("Ínyvérzésnél is moss fogat: puha fogkefével, gyengéden, az ínyszélnél is, és használj naponta fogselymet."))
        advice.append(tr("A gyulladt íny 1–2 hét rendszeres tisztítással általában megnyugszik. Ha nem, nézesse meg a fogorvos."))
    case "pain":
        let triggers = a.first { $0.question == "trigger" }?.options ?? []
        if has("trigger", "spontaneous") || has("trigger", "night") {
            atLeast(.urgent)
            advice.append(tr("A magától vagy éjjel jelentkező fogfájás gyulladásra utalhat: még ma keresd a fogorvosodat."))
        } else if triggers.allSatisfy({ $0 == "cold" || $0 == "sweet" }) && (has("pain", "mild") || has("pain", "none")) {
            advice.append(tr("Rövid, hidegre vagy édesre jelentkező fájdalom gyakran érzékenység: próbálj érzékeny fogakra való fogkrémet."))
        }
        if has("swelling_also", "yes") {
            atLeast(.urgent)
            photo = tr("Fotózd le a duzzadt részt és az arcod szemből.")
        }
        if has("trigger", "chewing") { advice.append(tr("Ha harapáskor fáj, rágj a másik oldalon, és kerüld a kemény ételt.")) }
        advice.append(tr("Fájdalomcsillapítót csak a betegtájékoztató szerint szedj. Ne melegítsd az arcod, és ne tegyél gyógyszert közvetlenül az ínyre."))
    case "sensitivity":
        if has("since", "week") || has("since", "recurring") || has("trigger", "spontaneous") { atLeast(.soon) }
        advice.append(tr("Használj érzékeny fogakra való fogkrémet, és moss puha fogkefével, erős nyomás nélkül."))
        advice.append(tr("Savas étel vagy ital után várj fél órát a fogmosással."))
    case "swelling":
        if has("swell_where", "face") || has("swell_where", "under_jaw") {
            atLeast(.urgent)
            photo = tr("Fotózd le az arcod szemből és oldalról.")
        } else {
            atLeast(.soon)
            photo = closePhoto
        }
        advice.append(tr("Kívülről hideg borogatást tehetsz rá (10 perc, aztán szünet). Ne melegítsd!"))
    case "stuck":
        if has("stuck_tried", "still") { atLeast(.monitor) }
        advice.append(tr("Óvatosan próbáld fogselyemmel vagy fogközkefével, és öblíts langyos sós vízzel."))
        advice.append(tr("Ne piszkáld hegyes tárggyal (fogpiszkáló, tű), mert megsértheted az ínyt."))
        advice.append(tr("Ha 1–2 nap múlva is ott van vagy fáj, nézesse meg a fogorvos."))
    case "chipped":
        atLeast(.soon)
        photo = closePhoto
        if has("sharp", "yes") { advice.append(tr("Az éles szélre ideiglenesen tehetsz fogszabályzó-viaszt vagy cukormentes rágót, hogy ne sértse a nyelved.")) }
        if has("piece", "yes") { advice.append(tr("A letört darabot tedd el tisztán, tejben vagy nedves tasakban, és vidd magaddal.")) }
        advice.append(tr("Rágj a másik oldalon, és kerüld a nagyon hideg, meleg vagy kemény ételt."))
    case "knocked":
        if has("tooth_type", "baby") {
            atLeast(.soon)
            advice.append(tr("Tejfogat ne próbálj visszahelyezni. Nyomd a sebet tiszta gézzel, és nézesse meg a fogorvos."))
        } else {
            atLeast(.emergency)
            advice.append(tr("A fogat a koronájánál fogd, ne a gyökerénél. Ha szennyezett, 10 másodpercig öblítsd tejjel vagy sós vízzel."))
            advice.append(tr("Ha tudod, óvatosan tedd vissza a helyére, és harapj rá egy gézre. Ha nem, tartsd tejben."))
            advice.append(tr("Azonnal indulj fogorvoshoz vagy ügyeletre: az első 30–60 perc a legfontosabb."))
        }
    case "loose":
        if has("loose_cause", "injury") {
            atLeast(.urgent)
            advice.append(tr("Ütés után mozgó fogat még ma nézessen meg a fogorvos."))
        } else if has("loose_cause", "changing") || child {
            advice.append(tr("Fogváltáskor a tejfog mozgása természetes. Hagyd, hogy magától kiessen."))
        } else {
            atLeast(.soon)
            advice.append(tr("Felnőttkorban a lassan meglazuló fog fogágybetegség jele lehet: kérj időpontot."))
        }
    case "sore":
        photo = closePhoto
        if has("sore_weeks", "gt2") {
            atLeast(.soon)
            advice.append(tr("A 2 hétnél tovább tartó sebet mindenképp nézesse meg orvos."))
        } else {
            advice.append(tr("Az afta általában 7–14 nap alatt magától gyógyul. Öblíts sós vízzel, kerüld a fűszeres és savas ételt."))
        }
    case "injury":
        photo = closePhoto
        if has("wound_bleed", "not_stopping") || has("wound_deep", "yes") {
            atLeast(.urgent)
            advice.append(tr("Ha a vérzés 15 perc nyomás után sem áll el, vagy mély a seb, még ma keress orvost; varrni kellhet."))
        }
        if has("injury_cause", "burn") {
            advice.append(tr("Égésnél öblíts hideg vízzel, és egy-két napig egyél langyos, puha ételt."))
        } else if has("injury_cause", "wire") {
            atLeast(.soon)
            advice.append(tr("A szúró drótra tegyél fogszabályzó-viaszt, és szólj a fogszabályzó orvosodnak."))
        } else if has("injury_cause", "hit") {
            atLeast(.soon)
            advice.append(tr("Ütés után nézd meg, nem mozog-e vagy tört-e le fog. Ha igen, menj fogorvoshoz még ma."))
        }
        advice.append(tr("Öblíts langyos sós vízzel, nyomd tiszta gézzel 10–15 percig, kívülről tegyél rá hideg borogatást."))
        advice.append(tr("A kisebb harapásos seb pár nap alatt begyógyul. Ha nő, gennyes vagy nem javul, szólj az orvosodnak."))
    case "jaw":
        atLeast(has("jaw_sym", "open") ? .soon : .monitor)
        advice.append(tr("Egyél puhább ételt, kerüld a rágógumit, és tegyél meleg borogatást a rágóizmokra."))
        if has("jaw_sym", "morning") { advice.append(tr("A reggeli fájdalom éjszakai fogcsikorgatásra utalhat: kérdezd a fogorvosod a harapásemelő sínről.")) }
    case "breath":
        if has("taste", "yes") {
            atLeast(.soon)
            advice.append(tr("A rossz íz vagy genny fertőzésre utalhat: kérj időpontot."))
        } else if has("since", "recurring") || has("since", "week") {
            atLeast(.soon)
        }
        advice.append(tr("Tisztítsd a nyelved is, használj fogselymet, és igyál elég vizet."))
    case "braces":
        if has("braces_issue", "adjust") {
            advice.append(tr("Utánállítás után 2–3 napig normális a feszülő fájdalom. Egyél puha ételt."))
        } else if has("braces_issue", "wire") {
            atLeast(.soon)
            advice.append(tr("A szúró drótra tegyél fogszabályzó-viaszt, és szólj a fogszabályzó orvosodnak."))
        } else {
            atLeast(.soon)
            advice.append(tr("Szólj a fogszabályzó orvosodnak; a levált darabot vagy a sínt tedd el."))
        }
        photo = closePhoto
    default:
        atLeast(.monitor)
    }

    if has("pain", "severe") || has("pain", "unbearable") {
        atLeast(.urgent)
    } else if has("pain", "moderate") {
        atLeast(.soon)
    }
    if recentSameKind >= 2 {
        atLeast(.soon)
        advice.append(tr("30 napon belül már {0}. alkalommal jelzed ezt a panaszt: érdemes megnézetni.", recentSameKind + 1))
    }
    var seen = Set<String>()
    let unique = advice.filter { seen.insert($0).inserted }
    let serious = level.rank >= TriageLevel.soon.rank
    return TriageResult(level: level, advice: unique, photo: photo, suggestMessage: serious || kind == "other", suggestBooking: serious)
}

public func recentSymptomCount(_ reports: [SymptomReport], profileId: String, kind: String, now: Date, days: Int = 30) -> Int {
    reports.filter {
        let age = now.timeIntervalSince($0.date)
        return $0.profileId == profileId && $0.kind == kind && age >= 0 && age <= Double(days) * 86_400
    }.count
}

/// Readable lines for the doctor (message, e-mail, report).
public func symptomSummary(_ r: SymptomReport, calendar: Calendar = .current) -> [String] {
    let k = Symptoms.kind(r.kind)
    let c = calendar.dateComponents([.hour, .minute], from: r.date)
    var out = ["\(I18n.date(r.date, calendar: calendar)) \(String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)) – \(k.emoji) \(k.title)"]
    for ans in r.answers {
        guard let q = Symptoms.question(ans.question) else { continue }
        let labels = ans.options.compactMap { id in q.options.first { $0.id == id }?.label }
        out.append("\(Symptoms.shortLabel(ans.question)): \(labels.joined(separator: ", "))")
    }
    out.append(tr("Besorolás: {0}", TriageLevel.byId(r.level).title))
    let note = r.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty { out.append(tr("Megjegyzés: {0}", note)) }
    if !r.photos.isEmpty { out.append(tr("Fotók: {0} db", r.photos.count)) }
    return out
}

/// After a brushing: a reason to ask "Minden rendben?" (much shorter/longer than usual, or unusually often).
public func brushingAnomaly(durationS: Double, recentDurations: [Double], todayCount: Int, perDay: Int) -> String? {
    if recentDurations.count >= 5 {
        let m = Stats.median(recentDurations)
        if durationS < 0.6 * m { return tr("Rövidebb volt a fogmosás a szokásosnál. Minden rendben?") }
        if durationS > 1.6 * m { return tr("Hosszabb volt a fogmosás a szokásosnál. Minden rendben?") }
    }
    if todayCount >= perDay + 2 { return tr("Ma a szokásosnál többször mostál fogat. Minden rendben?") }
    return nil
}

// MARK: - Dentist visit

public enum VisitReasons {
    public static var all: [(String, String)] {
        [("checkup", tr("Csak kontroll")), ("cleaning", tr("Fogkő-eltávolítás, tisztítás")), ("pain", tr("Fájdalom")),
         ("bleeding", tr("Ínyvérzés")), ("broken", tr("Letört fog vagy tömés")), ("cosmetic", tr("Esztétika, fehérítés")),
         ("braces", tr("Fogszabályozás")), ("other", tr("Egyéb ok"))]
    }
    public static func title(_ id: String) -> String { all.first { $0.0 == id }?.1 ?? id }
    public static var timings: [(String, String)] {
        [("asap", tr("Amint lehet")), ("week", tr("A héten")), ("month", tr("Egy hónapon belül")), ("any", tr("Mindegy"))]
    }
    public static var dayParts: [(String, String)] {
        [("morning", tr("Délelőtt")), ("afternoon", tr("Délután")), ("evening", tr("Este"))]
    }
}

public struct VisitRequest: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var created: Date
    public var reason: String
    public var note = ""
    public var timing = "any"
    public var dayParts: [String] = []
    public var symptomId: UUID? = nil
    public var sentAt: Date? = nil
    public var sentVia: String? = nil

    public init(profileId: String, created: Date, reason: String, note: String = "", timing: String = "any",
                dayParts: [String] = [], symptomId: UUID? = nil) {
        self.profileId = profileId; self.created = created; self.reason = reason; self.note = note
        self.timing = timing; self.dayParts = dayParts; self.symptomId = symptomId
    }
}

public func visitText(_ v: VisitRequest, patientName: String, symptom: SymptomReport? = nil) -> String {
    var lines = [tr("Időpontkérés – {0}", patientName), tr("Ok: {0}", VisitReasons.title(v.reason)),
                 tr("Mikor: {0}", VisitReasons.timings.first { $0.0 == v.timing }?.1 ?? v.timing)]
    if !v.dayParts.isEmpty {
        lines.append(tr("Napszak: {0}", v.dayParts.compactMap { d in VisitReasons.dayParts.first { $0.0 == d }?.1 }.joined(separator: ", ")))
    }
    let note = v.note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty { lines.append(tr("Megjegyzés: {0}", note)) }
    if let s = symptom { lines.append(""); lines += symptomSummary(s) }
    return lines.joined(separator: "\n")
}

/// Onboarding: "Mikor voltál utoljára fogorvosnál?" -> an approximate date.
public enum DentistIntake {
    public static var options: [(String, String)] {
        [("lt6m", tr("Fél éven belül")), ("6to12", tr("Fél–egy éve")), ("gt1y", tr("Több mint egy éve")), ("unknown", tr("Nem emlékszem"))]
    }
    public static func date(_ option: String, today: Date, calendar: Calendar = .current) -> Date? {
        switch option {
        case "lt6m": return calendar.date(byAdding: .month, value: -3, to: today)
        case "6to12": return calendar.date(byAdding: .month, value: -9, to: today)
        case "gt1y": return calendar.date(byAdding: .month, value: -18, to: today)
        default: return nil
        }
    }
}

// MARK: - Linked clinic

/// The clinic the patient linked in DentHub: shown next to the DentHub logo, gets messages and bookings.
public struct ClinicInfo: Codable, Equatable {
    public var id: String
    public var name: String
    public var logoUrl: String? = nil
    public var email: String? = nil
    public var phone: String? = nil
    public var bookingUrl: String? = nil
    public var address: String? = nil

    public init(id: String, name: String, logoUrl: String? = nil, email: String? = nil, phone: String? = nil,
                bookingUrl: String? = nil, address: String? = nil) {
        self.id = id; self.name = name; self.logoUrl = logoUrl; self.email = email; self.phone = phone
        self.bookingUrl = bookingUrl; self.address = address
    }
}

/// A message to the clinic. Delivered by DentHub once the account is linked; until then it waits ("queued").
public struct ClinicMessage: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var profileId: String
    public var date: Date
    public var text: String
    public var photos: [String] = []
    public var symptomId: UUID? = nil
    public var visitId: UUID? = nil
    public var fromPatient = true
    public var status = "queued"

    public init(profileId: String, date: Date, text: String, photos: [String] = [], symptomId: UUID? = nil, visitId: UUID? = nil) {
        self.profileId = profileId; self.date = date; self.text = text; self.photos = photos
        self.symptomId = symptomId; self.visitId = visitId
    }
}

/// The link code from the clinic (QR or text): `denthub://link?d=<base64url JSON of ClinicInfo>` or
/// `https://…/link#<same>`. Returns nil when it is not a valid code.
public func parseClinicLink(_ text: String) -> ClinicInfo? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload: String
    if t.hasPrefix("denthub://link?d=") {
        payload = String(t.dropFirst("denthub://link?d=".count))
    } else if let r = t.range(of: "/link#") {
        payload = String(t[r.upperBound...])
    } else {
        return nil
    }
    var b64 = payload.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.hasSuffix("=") { b64.removeLast() }
    while b64.count % 4 != 0 { b64 += "=" }
    guard let data = Data(base64Encoded: b64), let c = try? JSONDecoder().decode(ClinicInfo.self, from: data),
          !c.id.isEmpty, !c.name.isEmpty else { return nil }
    return c
}

public func clinicLinkCode(_ c: ClinicInfo) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    let data = (try? enc.encode(c)) ?? Data()
    let b64 = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "denthub://link?d=" + b64
}

/// Booking link with the reason and timing, when the clinic has online booking.
public func bookingLink(_ c: ClinicInfo, _ v: VisitRequest?) -> String? {
    guard let base = c.bookingUrl else { return nil }
    guard let v = v else { return base }
    return base + (base.contains("?") ? "&" : "?") + "reason=\(v.reason)&timing=\(v.timing)"
}

/// E-mail to the clinic: subject and body.
public func clinicEmail(patientName: String, symptom: SymptomReport?, visit: VisitRequest?) -> (subject: String, body: String) {
    let subject: String
    if let s = symptom {
        subject = tr("DentHub-Brush: {0} – {1}", Symptoms.kind(s.kind).title, patientName)
    } else if visit != nil {
        subject = tr("DentHub-Brush: időpontkérés – {0}", patientName)
    } else {
        subject = tr("DentHub-Brush: üzenet – {0}", patientName)
    }
    var lines = [tr("Tisztelt Doktor Úr/Nő!"), ""]
    if let v = visit { lines.append(visitText(v, patientName: patientName)); lines.append("") }
    if let s = symptom { lines += symptomSummary(s) }
    lines += ["", tr("Üdvözlettel: {0}", patientName), tr("(A DentHub-Brush appból küldve.)")]
    return (subject, lines.joined(separator: "\n"))
}
