import Foundation
import Security

final class KeychainService {
    private let serviceName = "ru.mzhukov.TAClient"
    private let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String

    private var memory: [Key: String]?

    init(inMemory: Bool = false) {
        #if DEBUG
        let testing = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || ProcessInfo.processInfo.arguments.contains("--connection-fixture")
        memory = inMemory || testing ? [:] : nil
        #else
        memory = inMemory ? [:] : nil
        #endif
    }

    enum Key: String {
        case sessionCookies = "session_cookies_v1"
        case authToken = "auth_token"
        case serverURL = "server_url"
    }

    private func baseQuery(for key: Key) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key.rawValue,
        ]
        if let accessGroup, !accessGroup.contains("$(") { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    @discardableResult
    func save(_ value: String, for key: Key) -> Bool {
        if memory != nil { memory?[key] = value; return true }
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        let values: [String: Any] = [kSecValueData as String: data,
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    func load(for key: Key) -> String? {
        if let memory { return memory[key] }
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(for key: Key) {
        if memory != nil { memory?[key] = nil; return }
        let query = baseQuery(for: key)
        SecItemDelete(query as CFDictionary)
    }

    func clearAll() {
        delete(for: .sessionCookies)
        delete(for: .authToken)
        delete(for: .serverURL)
    }
}
