import Foundation
import Security

/// Persists the local-API bearer token in the user's Keychain. The bridge
/// reads it on startup (generating one on first run), clients read it from
/// the same Keychain item to authenticate to the local socket.
///
/// Why Keychain and not e.g. a file in Application Support: the Keychain item
/// can be ACL-bound to specific signed apps (kSecAccessControl), so a random
/// process running under the same user can't read it. For now we use a plain
/// item — codesigning ACL is a follow-up once we ship signed builds.
enum TokenStore {
    static let service = "cz.bicisteadm.SkodaAtlassianBridge"
    static let account = "local-api"

    /// Get the existing token, or generate + store a new one. Idempotent.
    @discardableResult
    static func getOrCreate() -> String {
        if let existing = get() { return existing }
        let token = generate()
        set(token)
        return token
    }

    static func get() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func set(_ token: String) {
        let data = Data(token.utf8)
        // Try update first; if not present, add.
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateAttrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = updateQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }
}
