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
        .navigationTitle("API Keys")
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
                Text("No keys configured. Tap + to add one.")
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
            Text("Keys (\(entries.count))")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await testAll() }
            } label: {
                Label("Test All Keys", systemImage: "checkmark.circle")
                    .foregroundStyle(Morandi.accent)
            }
            .disabled(testingAll || entries.isEmpty)

            Button {
                clearCooldowns()
            } label: {
                Label("Clear All Cooldowns", systemImage: "snowflake")
                    .foregroundStyle(Morandi.powder)
            }
            .disabled(entries.isEmpty)

            Button {
                resetStats()
            } label: {
                Label("Reset Statistics", systemImage: "arrow.counterclockwise")
                    .foregroundStyle(Morandi.clay)
            }
            .disabled(entries.isEmpty)

            Button {
                showingBulkImport = true
            } label: {
                Label("Bulk Import…", systemImage: "tray.and.arrow.down")
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
        globalMessage = "Cooldowns cleared."
    }

    private func resetStats() {
        for i in entries.indices {
            entries[i].failureCount = 0
            entries[i].lastTestedAt = nil
            entries[i].lastTestStatus = .untested
            entries[i].cooldownUntil = nil
        }
        APIKeyStore.save(entries, providerId: providerId)
        globalMessage = "Statistics reset."
    }

    private func testAll() async {
        testingAll = true
        defer { testingAll = false }
        for entry in entries {
            await testKey(entry)
        }
        globalMessage = "Test complete."
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
        case .untested: return "Untested"
        case .success:
            if let d = entry.lastTestedAt {
                return "OK • \(Self.relativeFormatter.localizedString(for: d, relativeTo: Date()))"
            }
            return "OK"
        case .failed:
            return "Failed (\(entry.failureCount))"
        case .cooldown:
            if let until = entry.cooldownUntil {
                return "Cooldown until \(Self.timeFormatter.string(from: until))"
            }
            return "Cooldown"
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
                Section("Name") {
                    TextField("e.g. Personal", text: $name)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
                Section("API Key") {
                    HStack {
                        Group {
                            if showSecret {
                                TextField("sk-…", text: $secret)
                            } else {
                                SecureField("sk-…", text: $secret)
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
                    Toggle("Enabled", isOn: $enabled)
                        .tint(Morandi.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(existing == nil ? "Add API Key" : "Edit API Key")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
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
                    Text("Paste keys")
                } footer: {
                    Text("One key per line. CSV form 'name,key' is also supported. Imported keys are enabled by default.")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("Bulk Import")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { performImport() }
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
                name = "Key \(i + 1)"
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
