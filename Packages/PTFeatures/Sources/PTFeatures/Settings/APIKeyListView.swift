import SwiftUI
import PTAIServices
import PTCore
import PTNetworking
import PTUI

// MARK: - Model

public struct APIKeyEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var enabled: Bool
    public var lastTestedAt: Date?
    public var lastTestStatus: TestStatus
    public var failureCount: Int
    public var cooldownUntil: Date?

    public enum TestStatus: String, Codable, Sendable {
        case untested, success, failed, cooldown
    }

    public init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        lastTestedAt: Date? = nil,
        lastTestStatus: TestStatus = .untested,
        failureCount: Int = 0,
        cooldownUntil: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.lastTestedAt = lastTestedAt
        self.lastTestStatus = lastTestStatus
        self.failureCount = failureCount
        self.cooldownUntil = cooldownUntil
    }
}

// MARK: - Store

/// Persistence helper for ``APIKeyEntry`` records and their secrets.
///
/// Metadata (id, name, status, etc.) lives in the shared `UserDefaults` group
/// keyed by `api_keys_<providerId>`. Secret values are stored in the Keychain
/// under `provider_<providerId>_key_<entryId>`.
public enum APIKeyStore {
    private static let metadataKeyPrefix = "api_keys_"

    public static func metadataKey(providerId: String) -> String {
        metadataKeyPrefix + providerId
    }

    public static func secretKey(providerId: String, entryId: UUID) -> String {
        "provider_\(providerId)_key_\(entryId.uuidString)"
    }

    public static func load(providerId: String) -> [APIKeyEntry] {
        let defaults = AppConfig.groupDefaults
        guard let data = defaults.data(forKey: metadataKey(providerId: providerId)),
              let entries = try? JSONDecoder().decode([APIKeyEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public static func save(_ entries: [APIKeyEntry], providerId: String) {
        let defaults = AppConfig.groupDefaults
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: metadataKey(providerId: providerId))
        }
    }

    public static func loadSecret(providerId: String, entryId: UUID) -> String {
        (try? KeychainService.load(key: secretKey(providerId: providerId, entryId: entryId))) ?? ""
    }

    public static func saveSecret(_ secret: String, providerId: String, entryId: UUID) {
        let key = secretKey(providerId: providerId, entryId: entryId)
        if secret.isEmpty {
            try? KeychainService.delete(key: key)
        } else {
            try? KeychainService.save(key: key, value: secret)
        }
    }

    public static func deleteSecret(providerId: String, entryId: UUID) {
        try? KeychainService.delete(key: secretKey(providerId: providerId, entryId: entryId))
    }

    /// Round-robin selection of the next usable enabled key, advancing the
    /// stored cursor in ``UserDefaults``. Returns nil when no key is usable.
    public static func nextEnabled(providerId: String) -> APIKeyEntry? {
        let entries = load(providerId: providerId)
        let usable = entries.enumerated().filter { (_, e) in
            e.enabled && !isInCooldown(e)
        }
        guard !usable.isEmpty else { return nil }
        let cursorKey = "api_keys_cursor_\(providerId)"
        let defaults = AppConfig.groupDefaults
        let prev = defaults.integer(forKey: cursorKey)
        let next = (prev + 1) % usable.count
        defaults.set(next, forKey: cursorKey)
        return usable[next].element
    }

    /// Convenience wrapper that returns the secret string of the next
    /// round-robin enabled key, or nil if none are usable.
    public static func nextEnabledSecret(providerId: String) -> String? {
        guard let entry = nextEnabled(providerId: providerId) else { return nil }
        let secret = loadSecret(providerId: providerId, entryId: entry.id)
        return secret.isEmpty ? nil : secret
    }

    public static func isInCooldown(_ entry: APIKeyEntry) -> Bool {
        if let until = entry.cooldownUntil { return until > Date() }
        return false
    }
}

// MARK: - List View

@MainActor
public struct APIKeyListView: View {
    let providerId: String

    @State private var entries: [APIKeyEntry] = []
    @State private var showingAdd = false
    @State private var showingBulkImport = false
    @State private var editingEntry: APIKeyEntry?
    @State private var testingAll = false
    @State private var globalMessage: String?

    public init(providerId: String) {
        self.providerId = providerId
    }

    public var body: some View {
        Form {
            keysSection
            actionsSection
            if let msg = globalMessage {
                Section {
                    Text(msg)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.api_keys.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingEntry = nil
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            APIKeyEditSheet(
                providerId: providerId,
                existing: editingEntry
            ) { saved in
                upsert(saved)
            }
        }
        .sheet(isPresented: $showingBulkImport) {
            BulkImportSheet(providerId: providerId) { newEntries in
                entries.append(contentsOf: newEntries)
                APIKeyStore.save(entries, providerId: providerId)
            }
        }
        .onAppear { reload() }
    }

    private var keysSection: some View {
        Section {
            if entries.isEmpty {
                Text("settings.api_keys.empty")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            } else {
                ForEach(entries) { entry in
                    APIKeyRow(
                        entry: entry,
                        onToggleEnabled: { toggleEnabled(entry) },
                        onTest: { Task { await testKey(entry) } },
                        onEdit: {
                            editingEntry = entry
                            showingAdd = true
                        }
                    )
                }
                .onDelete(perform: deleteKeys)
            }
        } header: {
            Text(AppLocalization.format("settings.api_keys.count_format", locale: .autoupdatingCurrent, entries.count))
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await testAll() }
            } label: {
                Label("settings.api_keys.test_all", systemImage: "checkmark.circle")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(testingAll || entries.isEmpty)

            Button {
                clearCooldowns()
            } label: {
                Label("settings.api_keys.clear_cooldowns", systemImage: "snowflake")
                    .foregroundStyle(Morandi.powder)
            }
            .disabled(entries.isEmpty)

            Button {
                resetStats()
            } label: {
                Label("settings.api_keys.reset_statistics", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(Morandi.clay)
            }
            .disabled(entries.isEmpty)

            Button {
                showingBulkImport = true
            } label: {
                Label("settings.api_keys.bulk_import", systemImage: "tray.and.arrow.down")
                    .foregroundStyle(Morandi.lavender)
            }
        }
    }

    // MARK: - Actions

    private func reload() {
        entries = APIKeyStore.load(providerId: providerId)
    }

    private func upsert(_ saved: APIKeyEntry) {
        if let idx = entries.firstIndex(where: { $0.id == saved.id }) {
            entries[idx] = saved
        } else {
            entries.append(saved)
        }
        APIKeyStore.save(entries, providerId: providerId)
    }

    private func deleteKeys(_ offsets: IndexSet) {
        for idx in offsets {
            APIKeyStore.deleteSecret(providerId: providerId, entryId: entries[idx].id)
        }
        entries.remove(atOffsets: offsets)
        APIKeyStore.save(entries, providerId: providerId)
    }

    private func toggleEnabled(_ entry: APIKeyEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].enabled.toggle()
        APIKeyStore.save(entries, providerId: providerId)
    }

    private func clearCooldowns() {
        for i in entries.indices {
            entries[i].cooldownUntil = nil
            entries[i].failureCount = 0
            if entries[i].lastTestStatus == .cooldown {
                entries[i].lastTestStatus = .untested
            }
        }
        APIKeyStore.save(entries, providerId: providerId)
        globalMessage = String(localized: "settings.api_keys.cooldowns_cleared")
    }

    private func resetStats() {
        for i in entries.indices {
            entries[i].failureCount = 0
            entries[i].lastTestedAt = nil
            entries[i].lastTestStatus = .untested
            entries[i].cooldownUntil = nil
        }
        APIKeyStore.save(entries, providerId: providerId)
        globalMessage = String(localized: "settings.api_keys.statistics_reset")
    }

    private func testAll() async {
        testingAll = true
        defer { testingAll = false }
        for entry in entries {
            await testKey(entry)
        }
        globalMessage = String(localized: "settings.api_keys.test_complete")
    }

    private func testKey(_ entry: APIKeyEntry) async {
        let secret = APIKeyStore.loadSecret(providerId: providerId, entryId: entry.id)
        let success = await pingProvider(apiKey: secret)
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx].lastTestedAt = Date()
        if success {
            entries[idx].lastTestStatus = .success
            entries[idx].failureCount = 0
        } else {
            entries[idx].lastTestStatus = .failed
            entries[idx].failureCount += 1
        }
        APIKeyStore.save(entries, providerId: providerId)
    }

    private func pingProvider(apiKey: String) async -> Bool {
        guard let kind = SupportedProvider(rawValue: providerId) ?? Self.kindFromCustomId(providerId) else {
            return false
        }
        do {
            let config = ProviderConfig(apiKey: apiKey.isEmpty ? nil : apiKey)
            let client = try ProviderFactory.makeProvider(kind: kind, config: config)
            let req = ChatRequest(
                messages: [.user("ping")],
                model: ProviderFactory.defaultModels(for: kind).first ?? "gpt-4o-mini",
                maxTokens: 1
            )
            _ = try await client.complete(req)
            return true
        } catch {
            return false
        }
    }

    private static func kindFromCustomId(_ id: String) -> SupportedProvider? {
        id.hasPrefix("custom_") ? .custom : nil
    }
}

// MARK: - Row

@MainActor
struct APIKeyRow: View {
    let entry: APIKeyEntry
    let onToggleEnabled: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(Morandi.primaryText)
                Text(statusText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
            }
            Spacer()

            Button {
                onTest()
            } label: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Morandi.accent)
            }
            .buttonStyle(.borderless)

            Toggle("", isOn: Binding(
                get: { entry.enabled },
                set: { _ in onToggleEnabled() }
            ))
            .labelsHidden()
            .tint(Morandi.accent)
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private var statusColor: Color {
        switch entry.lastTestStatus {
        case .untested: return Morandi.tertiaryText
        case .success: return Morandi.success
        case .failed: return Morandi.destructive
        case .cooldown: return Morandi.warning
        }
    }

    private var statusText: String {
        switch entry.lastTestStatus {
        case .untested:
            return String(localized: "settings.api_keys.status.untested")
        case .success:
            if let d = entry.lastTestedAt {
                return AppLocalization.format(
                    "settings.api_keys.status.ok_relative_format",
                    locale: .autoupdatingCurrent,
                    Self.relativeFormatter.localizedString(for: d, relativeTo: Date())
                )
            }
            return String(localized: "settings.api_keys.status.ok")
        case .failed:
            return AppLocalization.format(
                "settings.api_keys.status.failed_count_format",
                locale: .autoupdatingCurrent,
                entry.failureCount
            )
        case .cooldown:
            if let until = entry.cooldownUntil {
                return AppLocalization.format(
                    "settings.api_keys.status.cooldown_until_format",
                    locale: .autoupdatingCurrent,
                    Self.timeFormatter.string(from: until)
                )
            }
            return String(localized: "settings.api_keys.status.cooldown")
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = .autoupdatingCurrent
        return f
    }()
}

// MARK: - Edit Sheet

@MainActor
struct APIKeyEditSheet: View {
    let providerId: String
    let existing: APIKeyEntry?
    let onSave: (APIKeyEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var secret: String = ""
    @State private var enabled: Bool = true
    @State private var showSecret = false

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "common.name")) {
                    TextField(String(localized: "settings.api_keys.name_placeholder"), text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                Section(String(localized: "settings.api_keys.secret_section")) {
                    HStack {
                        Group {
                            if showSecret {
                                TextField(String(localized: "settings.api_keys.secret_placeholder"), text: $secret)
                            } else {
                                SecureField(String(localized: "settings.api_keys.secret_placeholder"), text: $secret)
                            }
                        }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        Button {
                            showSecret.toggle()
                        } label: {
                            Image(systemName: showSecret ? "eye.slash" : "eye")
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section {
                    Toggle("common.enabled", isOn: $enabled)
                        .tint(Morandi.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(String(localized: existing == nil ? "settings.api_keys.add_title" : "settings.api_keys.edit_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let e = existing {
                    name = e.name
                    enabled = e.enabled
                    secret = APIKeyStore.loadSecret(providerId: providerId, entryId: e.id)
                }
            }
        }
    }

    private func save() {
        let entry = APIKeyEntry(
            id: existing?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            enabled: enabled,
            lastTestedAt: existing?.lastTestedAt,
            lastTestStatus: existing?.lastTestStatus ?? .untested,
            failureCount: existing?.failureCount ?? 0,
            cooldownUntil: existing?.cooldownUntil
        )
        APIKeyStore.saveSecret(secret, providerId: providerId, entryId: entry.id)
        onSave(entry)
        dismiss()
    }
}

// MARK: - Bulk Import

@MainActor
struct BulkImportSheet: View {
    let providerId: String
    let onImport: ([APIKeyEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .font(.system(.footnote, design: .monospaced))
                } header: {
                    Text("settings.api_keys.bulk_import_header")
                } footer: {
                    Text("settings.api_keys.bulk_import_footer")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(String(localized: "settings.api_keys.bulk_import_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.import") { performImport() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func performImport() {
        var imported: [APIKeyEntry] = []
        let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
        for (i, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let (name, secret): (String, String)
            if parts.count == 2 {
                name = parts[0]
                secret = parts[1]
            } else {
                name = AppLocalization.format(
                    "settings.api_keys.bulk_import_generated_name_format",
                    locale: .autoupdatingCurrent,
                    i + 1
                )
                secret = parts[0]
            }
            let entry = APIKeyEntry(name: name)
            APIKeyStore.saveSecret(secret, providerId: providerId, entryId: entry.id)
            imported.append(entry)
        }
        onImport(imported)
        dismiss()
    }
}
