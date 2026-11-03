import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif
#if canImport(CommonCrypto)
import CommonCrypto
#endif

// Password-protected backup files, care instructions from the clinic, and the "too hard scrubbing"
// note. Same as android/brushcore/.../Backup.kt (tests: BackupTests.swift / BackupTest.kt).

/// Backup file: "DHB1" || salt (16) || PBKDF2 iterations (4, big endian) || nonce (12) ||
/// AES-256-GCM ciphertext with tag. Key = PBKDF2-HMAC-SHA256(password, salt). AAD = "DHB1".
public enum BackupCrypto {
    static let magic = Data("DHB1".utf8)
    public static let iterations = 120_000

    public enum BackupError: Error { case wrongPassword, unsupported }

    public static func key(password: String, salt: Data, iterations: Int) throws -> Data {
        #if canImport(CommonCrypto)
        var out = Data(count: 32)
        let pw = Array(password.utf8).map { Int8(bitPattern: $0) }
        let status = out.withUnsafeMutableBytes { o in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pw, pw.count,
                                     s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations),
                                     o.bindMemory(to: UInt8.self).baseAddress, 32)
            }
        }
        guard status == kCCSuccess else { throw BackupError.unsupported }
        return out
        #else
        throw BackupError.unsupported
        #endif
    }

    public static func seal(_ plain: Data, password: String, iterations: Int = BackupCrypto.iterations,
                            salt: Data? = nil, nonce: Data? = nil) throws -> Data {
        #if canImport(CryptoKit)
        let s = salt ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let n = try nonce.map { try AES.GCM.Nonce(data: $0) } ?? AES.GCM.Nonce()
        let k = SymmetricKey(data: try key(password: password, salt: s, iterations: iterations))
        let box = try AES.GCM.seal(plain, using: k, nonce: n, authenticating: magic)
        var it = UInt32(iterations).bigEndian
        return magic + s + Data(bytes: &it, count: 4) + Data(n) + box.ciphertext + box.tag
        #else
        throw BackupError.unsupported
        #endif
    }

    public static func isBackup(_ d: Data) -> Bool { d.count > 52 && d.prefix(4) == magic }

    public static func open(_ d: Data, password: String) throws -> Data {
        #if canImport(CryptoKit)
        guard isBackup(d) else { throw BackupError.wrongPassword }
        let b = [UInt8](d)
        let salt = Data(b[4..<20])
        let iterations = Int(UInt32(b[20]) << 24 | UInt32(b[21]) << 16 | UInt32(b[22]) << 8 | UInt32(b[23]))
        guard (1_000...5_000_000).contains(iterations) else { throw BackupError.wrongPassword }
        do {
            let k = SymmetricKey(data: try key(password: password, salt: salt, iterations: iterations))
            let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Data(b[24..<36])),
                                            ciphertext: Data(b[36..<(b.count - 16)]), tag: Data(b[(b.count - 16)...]))
            return try AES.GCM.open(box, using: k, authenticating: magic)
        } catch {
            throw BackupError.wrongPassword
        }
        #else
        throw BackupError.unsupported
        #endif
    }

    /// At least 8 characters; nil when fine, else what is wrong.
    public static func passwordProblem(_ p: String) -> String? { p.count < 8 ? tr("Legalább 8 karakteres jelszót adj meg.") : nil }
}

/// What a backup file carries: the app's data as JSON plus the complaint photos.
public struct BackupPayload: Codable, Equatable {
    public var format = "denthub-backup-1"
    /// "full" (everything) or "profile" (one profile for another family member's phone)
    public var kind = "full"
    public var platform: String
    public var createdMs: Int64
    public var data: String
    /// photo file name -> base64 JPEG
    public var photos: [String: String] = [:]

    public init(kind: String, platform: String, createdMs: Int64, data: String, photos: [String: String]) {
        self.kind = kind; self.platform = platform; self.createdMs = createdMs; self.data = data; self.photos = photos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "denthub-backup-1"
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "full"
        platform = try c.decode(String.self, forKey: .platform)
        createdMs = try c.decode(Int64.self, forKey: .createdMs)
        data = try c.decode(String.self, forKey: .data)
        photos = try c.decodeIfPresent([String: String].self, forKey: .photos) ?? [:]
    }
}

public func encodeBackup(_ p: BackupPayload, password: String) throws -> Data {
    try BackupCrypto.seal(try JSONEncoder().encode(p), password: password)
}

public func decodeBackup(_ file: Data, password: String) throws -> BackupPayload {
    try JSONDecoder().decode(BackupPayload.self, from: try BackupCrypto.open(file, password: password))
}

// MARK: - Care instructions from the clinic

public struct CareInstruction: Codable, Equatable {
    public var title: String
    public var times: [String]
    public var days: Int
    public var clinic: String?
    public init(title: String, times: [String], days: Int, clinic: String? = nil) {
        self.title = title; self.times = times; self.days = days; self.clinic = clinic
    }
}

/// `denthub://care?d=<base64url JSON>` from the clinic (QR / link): a care task to add after the treatment.
public func parseCareLink(_ text: String) -> CareInstruction? {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let prefix = "denthub://care?d="
    guard t.hasPrefix(prefix) else { return nil }
    var b64 = String(t.dropFirst(prefix.count)).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while b64.hasSuffix("=") { b64.removeLast() }
    while b64.count % 4 != 0 { b64 += "=" }
    guard let d = Data(base64Encoded: b64), let c = try? JSONDecoder().decode(CareInstruction.self, from: d),
          !c.title.trimmingCharacters(in: .whitespaces).isEmpty, (1...60).contains(c.days), !c.times.isEmpty, c.times.count <= 8,
          c.times.allSatisfy({ $0.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil }) else { return nil }
    return c
}

public func careLinkCode(_ c: CareInstruction) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = .sortedKeys
    let b64 = ((try? enc.encode(c)) ?? Data()).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    return "denthub://care?d=" + b64
}

// MARK: - Scrubbing force

/// Manual brush: the scrubbing was clearly louder than this person's usual (from the same phone, so
/// placement mostly cancels out). Loud scrubbing usually means pressing too hard, which harms the gums.
public func scrubNote(brushDb: Double?, history: [Double], manual: Bool) -> String? {
    guard manual, let db = brushDb, history.count >= 5 else { return nil }
    let usual = Stats.median(Array(history.suffix(15)))
    return db >= usual + 6
        ? tr("Ma a szokásosnál jóval erősebben sikáltál. A túl erős súrolás sértheti az ínyt és a fogzománcot: finoman, kis körökkel moss.")
        : nil
}
