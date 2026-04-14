import Foundation
import CryptoKit
import PTCore
import PTNetworking

/// A serialised snapshot of the user's AI-related settings. Safe to write to
/// disk or a remote WebDAV share. API key material is stored in
/// `encryptedSecrets` and only decrypted on-device with a user passphrase.
public struct AISettingsSnapshot: Codable, Sendable, Equatable {
    public struct ProviderEntry: Codable, Sendable, Equatable {
        public var id: String
        public var displayName: String
        public var modelName: String
        public var baseURL: String?

        public init(
            id: String,
            displayName: String,
            modelName: String,
            baseURL: String? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.modelName = modelName
            self.baseURL = baseURL
        }
    }

    public var version: Int
    public var providers: [ProviderEntry]
    public var quickPrompts: [QuickPrompt]
    public var systemPrompt: String
    public var exportedAt: Date
    /// Base64 envelope of encrypted API keys (sealed with AES-GCM).
    public var encryptedSecrets: String?

    public init(
        version: Int = 1,
        providers: [ProviderEntry] = [],
        quickPrompts: [QuickPrompt] = [],
        systemPrompt: String = "",
        exportedAt: Date = Date(),
        encryptedSecrets: String? = nil
    ) {
        self.version = version
        self.providers = providers
        self.quickPrompts = quickPrompts
        self.systemPrompt = systemPrompt
        self.exportedAt = exportedAt
        self.encryptedSecrets = encryptedSecrets
    }
}

/// Errors thrown by `AISettingsSyncService`.
public enum AISettingsSyncError: Error, LocalizedError, Sendable {
    case encryptionFailed
    case decryptionFailed
    case invalidPassphrase

    public var errorDescription: String? {
        switch self {
        case .encryptionFailed:
            return AppLocalization.string("errors.sync.ai_settings_encryption_failed")
        case .decryptionFailed:
            return AppLocalization.string("errors.sync.ai_settings_decryption_failed")
        case .invalidPassphrase:
            return AppLocalization.string("errors.sync.ai_settings_invalid_passphrase")
        }
    }
}

/// Syncs AI provider configuration, quick prompts, and the system prompt
/// to/from a WebDAV server. API keys are encrypted with a user-supplied
/// passphrase using AES-GCM (via CryptoKit).
public actor AISettingsSyncService {
    /// Remote filename for the AI settings snapshot.
    public static let remoteFilename = "ai_settings.json"

    private let defaults: UserDefaults
    private let remoteFolder: String
    private let passphraseProvider: @Sendable () async -> String?

    public init(
        defaults: UserDefaults = AppConfig.groupDefaults,
        remoteFolder: String = "/PaperTok",
        passphraseProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.defaults = defaults
        self.remoteFolder = remoteFolder
        self.passphraseProvider = passphraseProvider
    }

    // MARK: - Export / Import

    /// Build a snapshot from the current UserDefaults/keychain state.
    public func exportSettings() async throws -> AISettingsSnapshot {
        let providers = readProviders()
        let prompts = readQuickPrompts()
        let systemPrompt = defaults.string(forKey: Keys.systemPrompt) ?? ""

        var snapshot = AISettingsSnapshot(
            providers: providers,
            quickPrompts: prompts,
            systemPrompt: systemPrompt
        )

        if let passphrase = await passphraseProvider(),
           !passphrase.isEmpty {
            let secrets = readSecrets(providers: providers)
            if !secrets.isEmpty {
                snapshot.encryptedSecrets = try Self.encrypt(
                    data: try Self.jsonEncoder.encode(secrets),
                    passphrase: passphrase
                )
            }
        }

        return snapshot
    }

    /// Restore settings from a snapshot, overwriting the local state.
    public func importSettings(_ snapshot: AISettingsSnapshot) async throws {
        try writeProviders(snapshot.providers)
        try writeQuickPrompts(snapshot.quickPrompts)
        defaults.set(snapshot.systemPrompt, forKey: Keys.systemPrompt)

        if let envelope = snapshot.encryptedSecrets,
           let passphrase = await passphraseProvider(),
           !passphrase.isEmpty {
            do {
                let data = try Self.decrypt(envelope: envelope, passphrase: passphrase)
                let secrets = try Self.jsonDecoder.decode([String: String].self, from: data)
                try writeSecrets(secrets)
            } catch {
                throw AISettingsSyncError.decryptionFailed
            }
        }
    }

    // MARK: - Remote

    /// Upload the current settings to `<remoteFolder>/ai_settings.json`.
    public func syncToRemote(webdav: WebDAVClient) async throws {
        try await webdav.mkdirAll(remoteFolder)
        let snapshot = try await exportSettings()
        let data = try Self.jsonEncoder.encode(snapshot)
        try await webdav.put(Self.remotePath(folder: remoteFolder), data: data)
    }

    /// Download settings from the remote and apply them locally.
    public func syncFromRemote(webdav: WebDAVClient) async throws {
        let path = Self.remotePath(folder: remoteFolder)
        guard await webdav.exists(path) else { return }
        let data = try await webdav.get(path)
        let snapshot = try Self.jsonDecoder.decode(AISettingsSnapshot.self, from: data)
        try await importSettings(snapshot)
    }

    // MARK: - Storage helpers

    private enum Keys {
        static let providers = "ai_providers_snapshot"
        static let quickPrompts = "ai_quick_prompts_snapshot"
        static let systemPrompt = "ai_system_prompt"
    }

    private func readProviders() -> [AISettingsSnapshot.ProviderEntry] {
        guard let data = defaults.data(forKey: Keys.providers) else { return [] }
        return (try? Self.jsonDecoder.decode([AISettingsSnapshot.ProviderEntry].self, from: data)) ?? []
    }

    private func writeProviders(_ providers: [AISettingsSnapshot.ProviderEntry]) throws {
        let data = try Self.jsonEncoder.encode(providers)
        defaults.set(data, forKey: Keys.providers)
    }

    private func readQuickPrompts() -> [QuickPrompt] {
        guard let data = defaults.data(forKey: Keys.quickPrompts) else {
            return QuickPrompt.builtIn
        }
        return (try? Self.jsonDecoder.decode([QuickPrompt].self, from: data)) ?? QuickPrompt.builtIn
    }

    private func writeQuickPrompts(_ prompts: [QuickPrompt]) throws {
        let data = try Self.jsonEncoder.encode(prompts)
        defaults.set(data, forKey: Keys.quickPrompts)
    }

    private func readSecrets(providers: [AISettingsSnapshot.ProviderEntry]) -> [String: String] {
        var out: [String: String] = [:]
        for provider in providers {
            let key = "ai_apikey_\(provider.id)"
            if let value = (try? KeychainService.load(key: key)) ?? nil, !value.isEmpty {
                out[provider.id] = value
            }
        }
        return out
    }

    private func writeSecrets(_ secrets: [String: String]) throws {
        for (id, value) in secrets {
            try KeychainService.save(key: "ai_apikey_\(id)", value: value)
        }
    }

    // MARK: - Crypto

    private static func deriveKey(passphrase: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(passphrase.utf8))
        return SymmetricKey(data: Data(digest))
    }

    private static func encrypt(data: Data, passphrase: String) throws -> String {
        let key = deriveKey(passphrase: passphrase)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw AISettingsSyncError.encryptionFailed
        }
        return combined.base64EncodedString()
    }

    private static func decrypt(envelope: String, passphrase: String) throws -> Data {
        guard let data = Data(base64Encoded: envelope) else {
            throw AISettingsSyncError.decryptionFailed
        }
        let key = deriveKey(passphrase: passphrase)
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private static func remotePath(folder: String) -> String {
        let trimmed = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        return "\(trimmed)/\(remoteFilename)"
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
