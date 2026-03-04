import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing a single API token string.
enum KeychainHelper {

    private static let service = "com.sentinel.api"
    private static let account = "simpletex-token"

    // MARK: - Public API

    /// Saves (or updates) the token in the Keychain.
    @discardableResult
    static func save(token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Try updating first; if the item doesn't exist yet, add it.
        let query = baseQuery()
        let status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
    }

    /// Reads the stored token, or `nil` if none exists.
    static func loadToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Removes the token from the Keychain.
    @discardableResult
    static func delete() -> Bool {
        SecItemDelete(baseQuery() as CFDictionary) == errSecSuccess
    }

    // MARK: - Private

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
