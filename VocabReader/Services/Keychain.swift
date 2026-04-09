import Foundation
import Security

struct KeychainStore {
    let service: String
    let defaults: UserDefaults
    let fallbackPrefix: String

    @discardableResult
    func save(_ value: String, key: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        guard updateStatus == errSecItemNotFound else {
            defaults.set(value, forKey: fallbackKey(for: key))
            return true
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
            defaults.removeObject(forKey: fallbackKey(for: key))
            return true
        }

        defaults.set(value, forKey: fallbackKey(for: key))
        return true
    }

    func load(key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        return defaults.string(forKey: fallbackKey(for: key))
    }

    func delete(key: String) {
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: fallbackKey(for: key))
    }

    private func baseQuery(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
    }

    private func fallbackKey(for key: String) -> String {
        fallbackPrefix + key
    }
}

enum Keychain {
    static let appStore = KeychainStore(
        service: "com.vocabreader.secure-storage",
        defaults: .standard,
        fallbackPrefix: "com.vocabreader.secure-storage.fallback."
    )

    @discardableResult
    static func save(_ value: String, key: String) -> Bool {
        appStore.save(value, key: key)
    }

    static func load(key: String) -> String? {
        appStore.load(key: key)
    }

    static func delete(key: String) {
        appStore.delete(key: key)
    }
}
