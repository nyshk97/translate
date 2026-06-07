import Foundation
import Security

/// API キーを macOS Keychain に保存・読み出しする薄いラッパ。
/// service は固定。account でキー種別を分ける。
enum KeychainStore {
    static let service = "com.d0ne1s.translate"

    enum Account: String {
        case groq = "groq-api-key"
        case gemini = "gemini-api-key"
    }

    static func get(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: Account) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        // 既存なら更新、無ければ追加
        if SecItemCopyMatching(base as CFDictionary, nil) == errSecSuccess {
            let attrs: [String: Any] = [kSecValueData as String: data]
            return SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecSuccess
        } else {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
    }

    @discardableResult
    static func delete(_ account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}
