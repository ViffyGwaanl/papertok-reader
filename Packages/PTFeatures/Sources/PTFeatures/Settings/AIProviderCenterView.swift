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

    private static let customProvidersKey = "ai_custom_providers"

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
        .navigationTitle("AI Providers")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddCustom) {
            addCustomSheet
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
            Text("Built-in Providers")
        } footer: {
            Text("Configure API keys, models, and endpoints for each provider. Keys are stored securely in the device Keychain.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    @ViewBuilder
    private var customSection: some View {
        if !customProviders.isEmpty {
            Section("Custom Providers") {
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
                Label("Add Custom Provider", systemImage: "plus.circle")
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
                Text(entry.baseURL.isEmpty ? "No base URL" : entry.baseURL)
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
                Section("Name") {
                    TextField("e.g. MyGateway", text: $newCustomName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
            }
            .scrollContentBackground(.hidden)
            .background(Morandi.background)
            .navigationTitle("Add Custom Provider")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddCustom = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
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
        return ProviderFactory.defaultModels(for: provider).first ?? "(default)"
    }

    private func capabilityBadges(for provider: SupportedProvider) -> [String] {
        switch provider {
        case .openai: return ["CHAT", "TOOLS", "VISION", "STREAM"]
        case .anthropic: return ["CHAT", "TOOLS", "VISION", "THINK"]
        case .gemini: return ["CHAT", "TOOLS", "VISION"]
        case .azure: return ["CHAT", "TOOLS"]
        case .volcengine: return ["CHAT", "TOOLS"]
        case .custom: return ["CHAT"]
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
        customProviders.remove(atOffsets: offsets)
        Self.saveCustomProviders(customProviders)
    }

    public static func loadCustomProviders() -> [CustomProviderEntry] {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        guard let data = defaults.data(forKey: customProvidersKey),
              let entries = try? JSONDecoder().decode([CustomProviderEntry].self, from: data) else {
            return []
        }
        return entries
    }

    public static func saveCustomProviders(_ entries: [CustomProviderEntry]) {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: customProvidersKey)
        }
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
