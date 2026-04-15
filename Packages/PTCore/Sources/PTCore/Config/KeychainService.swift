import Foundation
import Security

public enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

/// Protocol wrapper around a Keychain backend so tests can substitute an in-memory stub.
public protocol KeychainServing: Sendable {
    func save(_ value: String, forKey key: String) throws
    func load(forKey key: String) -> String?
    func delete(forKey key: String) throws
}

/// Default Keychain-backed implementation of `KeychainServing`.
public struct SystemKeychainService: KeychainServing {
    public static let shared = SystemKeychainService()
    public init() {}

    public func save(_ value: String, forKey key: String) throws {
        try KeychainService.save(key: key, value: value)
    }

    public func load(forKey key: String) -> String? {
        (try? KeychainService.load(key: key)) ?? nil
    }

    public func delete(forKey key: String) throws {
        try KeychainService.delete(key: key)
    }
}

public enum KeychainService {
    private static let service = AppConfig.bundleId

    public static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.saveFailed(errSecParam)
        }

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    public static func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }

        return String(data: data, encoding: .utf8)
    }

    public static func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
