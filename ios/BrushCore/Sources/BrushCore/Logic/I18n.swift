import Foundation

/// UI language. Source strings are Hungarian; English comes from en.json
/// (shared with Android and the web, generated from i18n/strings.json).
/// Placeholders: {0}, {1}… An English entry may be {"one": …, "other": …},
/// chosen by the first numeric argument.
public enum I18n {
    public private(set) static var lang = "hu"

    private static let en: [String: Any] = {
        guard let url = Bundle.module.url(forResource: "en", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }()

    /// pref: "hu", "en", or "" / nil for the device language.
    public static func resolve(_ pref: String?) -> String {
        if pref == "hu" || pref == "en" { return pref! }
        return (Locale.preferredLanguages.first ?? "en").hasPrefix("hu") ? "hu" : "en"
    }

    public static func setLanguage(_ pref: String?) { lang = resolve(pref) }

    public static var locale: Locale { Locale(identifier: lang == "hu" ? "hu_HU" : "en_US") }

    public static func has(_ key: String) -> Bool { en[key] != nil }

    public static func t(_ key: String, _ args: [Any]) -> String {
        var s = key
        if lang != "hu" {
            if let v = en[key] as? String {
                s = v
            } else if let forms = en[key] as? [String: String] {
                let n = args.lazy.compactMap { a -> Double? in
                    if let i = a as? Int { return Double(i) }
                    if let d = a as? Double { return d }
                    return nil
                }.first
                s = (n == 1 ? forms["one"] : nil) ?? forms["other"] ?? key
            }
        }
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: "\(a)") }
        return s
    }

    /// 2026.05.10. / May 10, 2026
    public static func date(_ d: Date, calendar: Calendar = .current) -> String {
        if lang == "hu" {
            let c = calendar.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d.%02d.%02d.", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}

public func tr(_ key: String, _ args: Any...) -> String { I18n.t(key, args) }
