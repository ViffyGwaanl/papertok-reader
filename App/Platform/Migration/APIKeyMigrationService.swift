import Foundation
import PTCore
import PTFeatures

/// One-shot migration that promotes legacy single-key storage
/// (`ai_api_key_<provider>` in the Keychain) into the new multi-key
/// ``APIKeyStore`` format. Runs on every launch but short-circuits
/// after the first successful run via a UserDefaults flag.
public enum APIKeyMigrationService {
    private static let migratedFlagKey = "api_key_migration_v1_done"

    /// Known built-in provider identifiers whose legacy keys should be
    /// migrated. Custom providers are not migrated automatically because
    /// their IDs are user-generated.
    private static let knownProviderIds: [String] = [
        "openai",
        "anthropic",
        "gemini",
        "azure",
        "volcengine"
    ]

    public static func migrateIfNeeded() {
        let defaults = AppConfig.groupDefaults
        guard !defaults.bool(forKey: migratedFlagKey) else { return }

        for providerId in knownProviderIds {
            let oldKey = "ai_api_key_\(providerId)"

            // Only migrate when: old key exists & non-empty & new store is empty.
            guard let oldValue = try? KeychainService.load(key: oldKey) ?? nil,
                  !oldValue.isEmpty else { continue }

            // Never overwrite existing multi-key entries.
            guard APIKeyStore.load(providerId: providerId).isEmpty else { continue }

            let entry = APIKeyEntry(
                id: UUID(),
                name: "Migrated Key",
                enabled: true,
                lastTestedAt: nil,
                lastTestStatus: .untested,
                failureCount: 0,
                cooldownUntil: nil
            )
            APIKeyStore.saveSecret(oldValue, providerId: providerId, entryId: entry.id)
            APIKeyStore.save([entry], providerId: providerId)

            // Tidy up the legacy keychain entry. Best-effort; ignore failures.
            try? KeychainService.delete(key: oldKey)
        }

        defaults.set(true, forKey: migratedFlagKey)
    }
}
