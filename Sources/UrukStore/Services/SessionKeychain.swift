import Foundation
import Security

/// What's actually needed to reconstruct an authenticated session:
/// Apple's dsid + authToken pair, plus the plain account/team fields
/// (all public, non-sensitive). Anisette data deliberately isn't part
/// of this — it's short-lived and re-fetched fresh whenever a session
/// is restored, rather than cached alongside the token.
struct PersistedSession: Codable {
    let appleID: String
    let accountIdentifier: String
    let firstName: String
    let lastName: String
    let teamName: String
    let teamIdentifier: String
    let teamType: Int16
    let dsid: String
    let authToken: String
}

enum SessionKeychain {
    private static let service = "com.urukstore.session"
    private static let account = "current"

    static func save(_ session: PersistedSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> PersistedSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PersistedSession.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
