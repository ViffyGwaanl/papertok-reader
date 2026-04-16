import Foundation
import Testing

@Suite("Localization guardrails")
struct LocalizationGuardrailTests {
    // MARK: - Localizable.xcstrings

    @Test("every Localizable.xcstrings key has a zh-Hans translation with state translated")
    func allXcstringsKeysHaveZhHansTranslation() throws {
        let catalog = try loadCatalog(named: "Localizable.xcstrings")
        let missing = keysWithoutTranslation(
            in: catalog,
            language: "zh-Hans",
            allowNeedsReview: false
        )
        #expect(
            missing.isEmpty,
            Comment(rawValue: "Keys missing zh-Hans translation:\n" + missing.sorted().joined(separator: "\n"))
        )
    }

    @Test("every Localizable.xcstrings key has a zh-Hant translation (needs_review allowed)")
    func allXcstringsKeysHaveZhHantTranslation() throws {
        let catalog = try loadCatalog(named: "Localizable.xcstrings")
        let missing = keysWithoutTranslation(
            in: catalog,
            language: "zh-Hant",
            allowNeedsReview: true
        )
        #expect(
            missing.isEmpty,
            Comment(rawValue: "Keys missing zh-Hant translation:\n" + missing.sorted().joined(separator: "\n"))
        )
    }

    // MARK: - AppShortcuts.xcstrings

    @Test("every AppShortcuts.xcstrings key has a zh-Hans translation with state translated")
    func allAppShortcutsKeysHaveZhHansTranslation() throws {
        let catalog = try loadCatalog(named: "AppShortcuts.xcstrings")
        let missing = keysWithoutTranslation(
            in: catalog,
            language: "zh-Hans",
            allowNeedsReview: false
        )
        #expect(
            missing.isEmpty,
            Comment(rawValue: "AppShortcuts keys missing zh-Hans translation:\n" + missing.sorted().joined(separator: "\n"))
        )
    }

    @Test("every AppShortcuts.xcstrings key has a zh-Hant translation (needs_review allowed)")
    func allAppShortcutsKeysHaveZhHantTranslation() throws {
        let catalog = try loadCatalog(named: "AppShortcuts.xcstrings")
        let missing = keysWithoutTranslation(
            in: catalog,
            language: "zh-Hant",
            allowNeedsReview: true
        )
        #expect(
            missing.isEmpty,
            Comment(rawValue: "AppShortcuts keys missing zh-Hant translation:\n" + missing.sorted().joined(separator: "\n"))
        )
    }

    // MARK: - Helpers

    private func loadCatalog(named filename: String) throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent(filename)
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json ?? [:]
    }

    private func keysWithoutTranslation(
        in catalog: [String: Any],
        language: String,
        allowNeedsReview: Bool
    ) -> [String] {
        guard let strings = catalog["strings"] as? [String: Any] else { return [] }
        var missing: [String] = []

        for (key, value) in strings {
            guard let entry = value as? [String: Any] else {
                missing.append(key)
                continue
            }
            guard let localizations = entry["localizations"] as? [String: Any] else {
                missing.append(key)
                continue
            }
            guard let langEntry = localizations[language] as? [String: Any] else {
                missing.append(key)
                continue
            }

            // A localization can be a simple stringUnit or contain variations (plurals).
            if let stringUnit = langEntry["stringUnit"] as? [String: Any] {
                let state = stringUnit["state"] as? String ?? ""
                if state == "translated" { continue }
                if allowNeedsReview && state == "needs_review" { continue }
                missing.append(key)
            } else if langEntry["variations"] != nil {
                // Plural/device variations -- presence is sufficient.
                continue
            } else {
                missing.append(key)
            }
        }

        return missing
    }
}
