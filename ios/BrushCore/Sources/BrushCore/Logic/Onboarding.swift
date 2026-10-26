import Foundation

/// First-run questions (onboarding.py): alone or with children? Per child:
/// name, age, "can they read yet?" (default no under 6, skipped from 9), avatar.
public struct OnboardingQuestion: Equatable {
    public enum Kind: Equatable { case choice, text, number, avatar }
    public let id: String
    public let text: String
    public let kind: Kind
    public let options: [(String, String)]
    public let defaultValue: String?
    public let pictureOnly: Bool

    public static func == (a: OnboardingQuestion, b: OnboardingQuestion) -> Bool {
        a.id == b.id && a.text == b.text && a.kind == b.kind && a.pictureOnly == b.pictureOnly
            && a.defaultValue == b.defaultValue && a.options.map { $0.0 } == b.options.map { $0.0 }
    }
}

public enum OnboardingError: Error, Equatable { case invalid(String), finished }

public final class OnboardingFlow {
    struct Child { var name = ""; var age: Int?; var canRead: Bool?; var avatar: String? }

    public static let assumeNonReaderUnder = 6
    public static let assumeReaderFrom = 9

    public var adultName: String
    private var mode: String?      // "alone" / "family"
    private var children: [Child] = []
    private var askMore = false
    private var done = false

    public init(adultName: String = "Én") { self.adultName = adultName }

    public func nextQuestion() -> OnboardingQuestion? {
        guard let mode = mode else {
            return OnboardingQuestion(id: "mode", text: "Egyedül használod az appot, vagy a gyerekeid fogmosását is mérnéd?",
                                      kind: .choice, options: [("alone", "Csak magamnak"), ("family", "A gyerekeimnek is")],
                                      defaultValue: nil, pictureOnly: false)
        }
        if mode == "alone" || done { return nil }
        if askMore {
            return OnboardingQuestion(id: "more", text: "Szeretnél még egy gyereket hozzáadni?", kind: .choice,
                                      options: [("yes", "Igen"), ("no", "Nem, kész")], defaultValue: nil, pictureOnly: false)
        }
        let c = children[children.count - 1]
        if c.name.isEmpty {
            return OnboardingQuestion(id: "child_name", text: "Hogy hívják a gyermeked?", kind: .text, options: [], defaultValue: nil, pictureOnly: false)
        }
        guard let age = c.age else {
            return OnboardingQuestion(id: "child_age", text: "Hány éves \(c.name)?", kind: .number, options: [], defaultValue: nil, pictureOnly: false)
        }
        guard let reads = c.canRead else {
            return OnboardingQuestion(id: "child_reads", text: "Tud már \(c.name) önállóan olvasni?", kind: .choice,
                                      options: [("yes", "Igen"), ("no", "Még nem")],
                                      defaultValue: age < OnboardingFlow.assumeNonReaderUnder ? "no" : nil, pictureOnly: false)
        }
        let taken = Set(children.dropLast().compactMap { $0.avatar })
        let opts = Avatar.all.filter { !taken.contains($0.id) }.map { ($0.id, $0.emoji) }
        return OnboardingQuestion(id: "child_avatar",
                                  text: reads ? "\(c.name), válaszd ki a képedet! Erről fogod megismerni magad." : "",
                                  kind: .avatar, options: opts, defaultValue: nil, pictureOnly: !reads)
    }

    public func answer(_ value: String) throws {
        guard let q = nextQuestion() else { throw OnboardingError.finished }
        switch q.id {
        case "mode":
            guard value == "alone" || value == "family" else { throw OnboardingError.invalid(value) }
            mode = value
            if value == "family" { children.append(Child()) }
        case "more":
            if value == "yes" { children.append(Child()); askMore = false } else { done = true }
        case "child_name":
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty else { throw OnboardingError.invalid("empty name") }
            children[children.count - 1].name = v
        case "child_age":
            guard let a = Int(value), (1...17).contains(a) else { throw OnboardingError.invalid("age") }
            children[children.count - 1].age = a
            if a >= OnboardingFlow.assumeReaderFrom { children[children.count - 1].canRead = true }
        case "child_reads":
            children[children.count - 1].canRead = (value == "yes")
        case "child_avatar":
            guard q.options.contains(where: { $0.0 == value }) else { throw OnboardingError.invalid("avatar") }
            children[children.count - 1].avatar = value
            askMore = true
        default:
            break
        }
    }

    public func profiles() -> [Profile] {
        var out = [Profile(id: "me", name: adultName)]
        var i = 1
        for c in children where c.avatar != nil {
            out.append(Profile(id: "child\(i)", name: c.name, child: true, age: c.age, canRead: c.canRead ?? false, avatar: c.avatar))
            i += 1
        }
        return out
    }
}
