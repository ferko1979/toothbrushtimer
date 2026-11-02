import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

// "View on the web" link: the web page shows a QR code with a one-time session id
// and its ECDH P-256 public key; the phone encrypts a statistics snapshot to that
// key and posts it to the relay, which only ever sees ciphertext. Spec: web/PROTOCOL.md.
// 1:1 port of android/brushcore/.../WebLink.kt.

public struct WebGoals: Codable, Equatable { public let perDay: Int; public let targetS: Double }

public struct WebDay: Codable, Equatable {
    public let d: String
    public let n: Int
    public let avgS: Double
    public let goalHits: Int
    public let tapOff: Int
    public let floss, mouthwash, interdental, tongue: Bool
    public let sens: Int
    public let bleed: Bool
}

public struct WebInsight: Codable, Equatable { public let text: String; public let alert: Bool }

public struct WebReport: Codable, Equatable {
    public let title: String
    public let subtitle: String
    public let sections: [ReportSection]
}

public struct WebProfile: Codable, Equatable {
    public let name: String
    public let child: Bool
    public let avatar: String
    public let goals: WebGoals
    public let streak: Int
    public let stickers: Int
    public let orthodontic: Bool
    public let days: [WebDay]
    public let insights: [WebInsight]
    public let report: WebReport
}

public struct WebSnapshot: Codable, Equatable {
    public var v = 1
    public let generated: String
    public let locale: String
    public let profiles: [WebProfile]
    public var lang = "hu"
}

public enum WebLink {
    public static let info = "fogmosas-web-v1"
    public static let snapshotDays = 90

    public struct Pairing: Equatable {
        public let base: String
        public let host: String
        public let sid: String
        public let webPublicKey: Data
        public var uploadURL: URL { URL(string: "\(base)/api/relay/\(sid)")! }
    }

    public static func b64(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func unb64(_ s: String) -> Data? {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return Data(base64Encoded: t)
    }

    /// Parses the QR text https://host[:port][/prefix]/l#<sid>.<publicKey>; nil if it is not ours.
    public static func parse(_ qr: String) -> Pairing? {
        guard let c = URLComponents(string: qr.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme, let host = c.host, let frag = c.fragment else { return nil }
        let local = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && local) else { return nil }
        let path = c.percentEncodedPath
        guard path.hasSuffix("/l") else { return nil }
        let parts = frag.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts[0].count == 22,
              parts[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              let key = unb64(parts[1]), key.count == 65, key.first == 4 else { return nil }
        let port = c.port.map { ":\($0)" } ?? ""
        return Pairing(base: "\(scheme)://\(host)\(port)\(path.dropLast(2))", host: host, sid: parts[0], webPublicKey: key)
    }

    #if canImport(CryptoKit)
    public enum SealError: Error { case badKey }

    /// Envelope: phone public key (65) || nonce (12) || AES-256-GCM ciphertext with tag. AAD = session id.
    public static func seal(webPublicKey: Data, sid: String, plaintext: Data,
                            ephemeral: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey(),
                            nonce: Data? = nil) throws -> Data {
        let peer: P256.KeyAgreement.PublicKey
        do { peer = try P256.KeyAgreement.PublicKey(x963Representation: webPublicKey) } catch { throw SealError.badKey }
        let secret = try ephemeral.sharedSecretFromKeyAgreement(with: peer)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data(sid.utf8), sharedInfo: Data(info.utf8),
                                                 outputByteCount: 32)
        let n = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let box = try AES.GCM.seal(plaintext, using: key, nonce: n, authenticating: Data(sid.utf8))
        return ephemeral.publicKey.x963Representation + Data(n) + box.ciphertext + box.tag
    }
    #endif

    public static func snapshotJSON(_ s: WebSnapshot) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(s)
    }

    public static func profileSnapshot(_ p: Profile, records: [BrushRecord], care: [CareEntry], today: Date,
                                       flossTracked: Bool = true, coach: Coach = Coach()) -> WebProfile {
        let cal = coach.calendar
        let t0 = cal.startOfDay(for: today)
        let start = cal.date(byAdding: .day, value: -(snapshotDays - 1), to: t0)!
        let byDay = Dictionary(grouping: records) { cal.startOfDay(for: $0.start) }
        let careByDay = careDays(care, calendar: cal)
        let keys = Set(byDay.keys).union(careByDay.keys).filter { $0 >= start && $0 <= t0 }.sorted()
        let days: [WebDay] = keys.map { d in
            let rs = byDay[d] ?? []
            let c = careByDay[d]
            let avg = rs.isEmpty ? 0 : (rs.map(\.durationS).reduce(0, +) / Double(rs.count) * 10).rounded() / 10
            let comps = cal.dateComponents([.year, .month, .day], from: d)
            return WebDay(d: String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0),
                          n: rs.count, avgS: avg, goalHits: rs.filter { $0.durationS >= p.goals.targetS }.count,
                          tapOff: rs.filter(\.tapOff).count, floss: c?.floss ?? false, mouthwash: c?.mouthwash ?? false,
                          interdental: c?.interdental ?? false, tongue: c?.tongue ?? false, sens: c?.sensitivity ?? 0,
                          bleed: c?.bleeding ?? false)
        }
        let rep = dentistReport(profile: p, records: records, entries: care, today: today, days: 30, coach: coach)
        return WebProfile(name: p.name, child: p.child, avatar: p.avatarEmoji,
                          goals: WebGoals(perDay: p.goals.perDay, targetS: p.goals.targetS),
                          streak: coach.perfectStreak(records, goals: p.goals, today: today),
                          stickers: stickers(records, goals: p.goals, coach: coach).stickers, orthodontic: p.orthodontic,
                          days: days, insights: careInsights(care, today: today, flossTracked: flossTracked, calendar: cal).map { WebInsight(text: $0.text, alert: $0.alert) },
                          report: WebReport(title: rep.title, subtitle: rep.subtitle, sections: rep.sections))
    }

    public static func snapshot(_ profiles: [WebProfile], now: Date, locale: String) -> WebSnapshot {
        let f = ISO8601DateFormatter()
        return WebSnapshot(generated: f.string(from: now), locale: locale, profiles: profiles, lang: I18n.lang)
    }
}
