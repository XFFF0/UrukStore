import Foundation
import Security

/// Apple only hands back a certificate's private key once, at the moment
/// it's created — asking for the certificate again later (e.g. next app
/// launch) returns the public certificate only. So the private key has to
/// be cached locally the first time, keyed by the certificate's serial
/// number, or every relaunch would look like a "lost" certificate and
/// force a revoke-and-recreate cycle.
enum CertificateKeychain {
    private static let service = "com.urukstore.certificate-private-keys"

    static func savePrivateKey(_ data: Data, forSerialNumber serialNumber: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serialNumber
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func privateKey(forSerialNumber serialNumber: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: serialNumber,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }
}
