import SwiftUI
import PTAIServices
import PTCore
import PTUI

/// A central hub for configuring all AI providers (OpenAI, Anthropic, Gemini,
/// Azure, Volcengine, plus user-defined custom endpoints). Users tap a row to
/// edit the details for that provider.
public struct AIProviderCenterView: View {
    @State private var viewModel: SettingsViewModel
    @State private var customProviders: [CustomProviderEntry]
    @State private var showAddCustom = false
    @State private var newCustomName: String = ""
    @State private var pendingDeleteOffsets: IndexSet?

    private func localized(_ key: String) -> String {
        AppLocalization.string(key)
    }

    @MainActor
    public init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
        _customProviders = State(initialValue: Self.loadCustomProviders())
    }

    public var body: some View {
        Form {
            builtInSection
            customSection
            addCustomSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.ai_providers"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddCustom) {
            addCustomSheet
        }
        .confirmationDialog(
            localized("settings.ai_provider.delete_confirmation"),
            isPresented: Binding(
                get: { pendingDeleteOffsets != nil },
                set: { if !$0 { pendingDeleteOffsets = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let offsets = pendingDeleteOffsets {
                    customProviders.remove(atOffsets: offsets)
                    Self.saveCustomProviders(customProviders)
                }
                pendingDeleteOffsets = nil
            }
            Button(String(localized: "common.cancel"), role: .cancel) { pendingDeleteOffsets = nil }
        }
    }

    // MARK: - Sections

    private var builtInSection: some View {
        Section {
            ForEach(SupportedProvider.allCases.filter { $0 != .custom }, id: \.rawValue) { provider in
                NavigationLink {
                    AIProviderDetailView(provider: provider, viewModel: viewModel)
                } label: {
                    providerRow(for: provider, displayName: ProviderFactory.displayName(for: provider))
                }
            }
        } header: {
            Text("ai.providers.builtin")
        } footer: {
            Text("ai.providers.config_hint")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        if !customProviders.isEmpty {
            Section(String(localized: "ai.providers.custom")) {
                ForEach(customProviders) { entry in
                    NavigationLink {
                        AIProviderDetailView(
                            provider: .custom,
                            customProviderID: entry.id,
                            viewModel: viewModel
                        )
                    } label: {
                        customRow(for: entry)
                    }
                }
                .onDelete(perform: deleteCustom)
            }
        }
    }

    private var addCustomSection: some View {
        Section {
            Button {
                newCustomName = ""
                showAddCustom = true
            } label: {
                Label(String(localized: "ai.providers.add_custom"), systemImage: "plus.circle")
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func providerRow(for provider: SupportedProvider, displayName: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            providerIcon(for: provider)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(providerTint(for: provider).opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AppSpacing.xs) {
                    Text(displayName)
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(Morandi.primaryText)
                    if !apiKey(for: provider.rawValue).isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Morandi.sage)
                    }
                }
                Text(currentModel(for: provider))
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    ForEach(capabilityBadges(for: provider), id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Morandi.sage.opacity(0.15))
                            )
                            .foregroundStyle(Morandi.sage)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func customRow(for entry: CustomProviderEntry) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "wrench.adjustable")
                .font(.system(size: 16))
                .foregroundStyle(Morandi.lavender)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Morandi.lavender.opacity(0.18))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(Morandi.primaryText)
                Text(entry.baseURL.isEmpty ? localized("ai.providers.no_base_url") : entry.baseURL)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Add Custom Sheet

    private var addCustomSheet: some View {
        NavigationStack {
            Form {
                Section(String(localized: "common.name")) {
                    TextField(localized("ai.providers.custom_name_placeholder"), text: $newCustomName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle(String(localized: "ai.providers.add_custom"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { showAddCustom = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        addCustomProvider()
                        showAddCustom = false
                    }
                    .disabled(newCustomName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private func apiKey(for id: String) -> String {
        viewModel.loadAPIKey(for: id)
    }

    private func currentModel(for provider: SupportedProvider) -> String {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        let key = "ai_model_for_\(provider.rawValue)"
        if let saved = defaults.string(forKey: key), !saved.isEmpty { return saved }
        return ProviderFactory.defaultModels(for: provider).first ?? "(\(localized("common.default")))"
    }

    private func capabilityBadges(for provider: SupportedProvider) -> [String] {
        switch provider {
        case .openai:
            return [
                localized("settings.ai_provider.capability.chat"),
                localized("settings.ai_provider.capability.tools"),
                localized("settings.ai_provider.capability.vision"),
                localized("settings.ai_provider.capability.stream"),
            ]
        case .anthropic:
            return [
                localized("settings.ai_provider.capability.chat"),
                localized("settings.ai_provider.capability.tools"),
                localized("settings.ai_provider.capability.vision"),
                localized("settings.ai_provider.capability.think"),
            ]
        case .gemini:
            return [
                localized("settings.ai_provider.capability.chat"),
                localized("settings.ai_provider.capability.tools"),
                localized("settings.ai_provider.capability.vision"),
            ]
        case .azure, .volcengine:
            return [
                localized("settings.ai_provider.capability.chat"),
                localized("settings.ai_provider.capability.tools"),
            ]
        case .custom:
            return [localized("settings.ai_provider.capability.chat")]
        }
    }

    @ViewBuilder
    private func providerIcon(for provider: SupportedProvider) -> some View {
        let symbol: String = {
            switch provider {
            case .openai: return "brain.head.profile"
            case .anthropic: return "sparkle"
            case .gemini: return "circle.hexagongrid"
            case .azure: return "cloud"
            case .volcengine: return "flame"
            case .custom: return "wrench.adjustable"
            }
        }()
        Image(systemName: symbol)
            .font(.system(size: 16))
            .foregroundStyle(providerTint(for: provider))
    }

    private func providerTint(for provider: SupportedProvider) -> Color {
        switch provider {
        case .openai: return Morandi.sage
        case .anthropic: return Morandi.dustyRose
        case .gemini: return Morandi.powder
        case .azure: return Morandi.mist
        case .volcengine: return Morandi.clay
        case .custom: return Morandi.lavender
        }
    }

    // MARK: - Custom provider persistence

    private func addCustomProvider() {
        let entry = CustomProviderEntry(
            id: "custom_\(UUID().uuidString.prefix(8))",
            displayName: newCustomName.trimmingCharacters(in: .whitespaces),
            baseURL: ""
        )
        customProviders.append(entry)
        Self.saveCustomProviders(customProviders)
    }

    private func deleteCustom(at offsets: IndexSet) {
        pendingDeleteOffsets = offsets
    }

    public static func loadCustomProviders() -> [CustomProviderEntry] {
        CustomProviderStore.load()
    }

    public static func saveCustomProviders(_ entries: [CustomProviderEntry]) {
        CustomProviderStore.save(entries)
        StoredAIProviderCatalog.postConfigurationDidChange()
    }
}

/// Simple persisted record for a user-defined custom AI provider.
public struct CustomProviderEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var baseURL: String

    public init(id: String, displayName: String, baseURL: String) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
    }
}
