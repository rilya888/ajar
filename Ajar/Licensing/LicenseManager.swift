import CryptoKit
import Foundation
import Observation
import Security

/// Two failures, two sentences. Anything the user can't act on isn't worth a third case.
enum LicenseError: LocalizedError, Equatable {
    case unreadableKey
    case badSignature

    var errorDescription: String? {
        switch self {
        case .unreadableKey:
            return "That doesn't look like an Ajar license key. Copy the whole key from your purchase email, including the dot."
        case .badSignature:
            return "This key isn't valid for Ajar. Check for a missing character, or reply to your purchase email."
        }
    }
}

/// Offline licensing (Paddle Billing, docs/release/licensing.md): a webhook-driven Worker signs
/// `email|order-id` with the owner's Ed25519 private key and mails the buyer
/// `base64(payload).base64(signature)`. The app verifies it locally against the public half.
///
/// There is no network code in this file, and that is the point: no activation server, no
/// activation limit, no "no Wi-Fi → lost Pro" class of failure, no deactivation endpoint. The
/// price is that a refunded key can't be revoked — cheaper than running a server for tens of sales.
enum LicenseVerifier {
    /// The owner's real signing key. Its private half lives outside this repo, held as a secret
    /// on the Cloudflare Worker that signs purchase emails (docs/TODO.md, Paddle webhook).
    static let publicKeyBase64 = "zMrCJ27t/M1H/UCQBjaA3CX+ydrMB2O1De93CcLFC/U="

    /// Returns the buyer's email on success. Order id is verified as present but not used —
    /// no hardware binding, no activation count, nothing to look it up against.
    static func verify(_ key: String, publicKeyBase64: String = Self.publicKeyBase64) throws -> String {
        let parts = key.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".")
        guard parts.count == 2,
              let payloadData = Data(base64Encoded: String(parts[0])),
              let signature = Data(base64Encoded: String(parts[1])),
              let payload = String(data: payloadData, encoding: .utf8)
        else { throw LicenseError.unreadableKey }

        let fields = payload.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count == 2, !fields[0].isEmpty, !fields[1].isEmpty else {
            throw LicenseError.unreadableKey
        }

        guard let raw = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              publicKey.isValidSignature(signature, for: payloadData)
        else { throw LicenseError.badSignature }

        return String(fields[0])
    }
}

/// Holds the activated key. Verification runs again at every launch, so a key edited straight
/// into the Keychain doesn't grant Pro.
@Observable
final class LicenseManager {
    private(set) var email: String?
    @ObservationIgnored private let store: KeychainItem

    var hasLicense: Bool { email != nil }

    init(store: KeychainItem = .licenseKey) {
        self.store = store
        if let key = store.read(), let email = try? LicenseVerifier.verify(key) {
            self.email = email
        }
    }

    /// Same call behind both "Activate" and "Restore": with no server, restoring a purchase is
    /// re-entering the key that was mailed to you.
    func activate(_ key: String) throws {
        let email = try LicenseVerifier.verify(key)
        store.write(key.trimmingCharacters(in: .whitespacesAndNewlines))
        self.email = email
    }

    func deactivate() {
        store.delete()
        email = nil
    }
}

/// One generic-password item. Not a keychain wrapper — three calls, no query building.
struct KeychainItem {
    let service: String
    let account: String

    static let licenseKey = KeychainItem(service: "com.quietunit.ajar", account: "license-key")

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func read() -> String? {
        var query = self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) {
        SecItemDelete(query as CFDictionary)
        var query = self.query
        query[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
