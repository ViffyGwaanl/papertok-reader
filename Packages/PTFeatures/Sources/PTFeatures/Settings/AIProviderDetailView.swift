import SwiftUI
import PTAIServices
import PTCore
import PTNetworking
import PTUI

/// Detailed editor for a single AI provider's configuration (API key, base URL,
/// model, optional Azure deployment info, custom headers, etc.) plus a
/// "Test Connection" button that issues a minimal ping to the provider.
public struct AIProviderDetailView: View {
    let provider: SupportedProvider
    /// For custom providers, identifies which user-defined entry is being edited.
    let customProviderID: String?
    let viewModel: SettingsViewModel

    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var selectedModel: String = ""
    @State private var deploymentName: String = ""
    @State private var apiVersion: String = "2024-02-15-preview"
    @State private var customHeadersText: String = ""
    @State private var testStatus: TestStatus = .idle
    @State private var isSaved = false

    private enum TestStatus: Equatable {
        case idle
        case testing
        case success(String)
        case failure(String)
    }

    public init(provider: SupportedProvider, customProviderID: String? = nil, viewModel: SettingsViewModel) {
        self.provider = provider
        self.customProviderID = customProviderID
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            apiKeySection
            endpointSection
            modelSection
            if provider == .azure { azureSection }
            if provider == .custom { customHeadersSection }
            capabilitiesSection
            testSection
            saveSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(titleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: loadValues)
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            SecureField("API Key", text: $apiKey)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        } header: {
            Text("Authentication")
        } footer: {
            Text("Stored securely in the device Keychain.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var endpointSection: some View {
        Section("Endpoint") {
            TextField("Base URL (optional override)", text: $baseURL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    private var modelSection: some View {
        Section("Model") {
            let models = ProviderFactory.defaultModels(for: provider)
            if models.isEmpty {
                TextField("Model ID", text: $selectedModel)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            } else {
                Picker("Model", selection: $selectedModel) {
                    ForEach(models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                    if !models.contains(selectedModel) && !selectedModel.isEmpty {
                        Text(selectedModel).tag(selectedModel)
                    }
                }
                .foregroundStyle(Morandi.primaryText)

                TextField("Or enter custom model ID", text: $selectedModel)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .font(AppTypography.caption)
            }
        }
    }

    private var azureSection: some View {
        Section("Azure") {
            TextField("Deployment Name", text: $deploymentName)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
            TextField("API Version", text: $apiVersion)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    private var customHeadersSection: some View {
        Section {
            TextEditor(text: $customHeadersText)
                .frame(minHeight: 100)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Morandi.primaryText)
        } header: {
            Text("Custom Headers")
        } footer: {
            Text("One header per line, format: Name: Value")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var capabilitiesSection: some View {
        Section("Capabilities") {
            HStack(spacing: AppSpacing.xs) {
                ForEach(capabilityBadges, id: \.self) { badge in
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Morandi.sage.opacity(0.15)))
                        .foregroundStyle(Morandi.sage)
                }
                Spacer()
            }
        }
    }

    private var testSection: some View {
        Section {
            Button {
                testConnection()
            } label: {
                HStack {
                    if testStatus == .testing {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text("Test Connection")
                }
                .foregroundStyle(Morandi.accent)
            }
            .disabled(testStatus == .testing)

            switch testStatus {
            case .idle, .testing:
                EmptyView()
            case .success(let msg):
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Morandi.sage)
                    Text(msg)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.sage)
                }
            case .failure(let msg):
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Morandi.destructive)
                    Text(msg)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.destructive)
                }
            }
        }
    }

    private var saveSection: some View {
        Section {
            Button {
                saveValues()
            } label: {
                Text("Save")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Morandi.accent)
            }

            if isSaved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Morandi.sage)
                    Text("Saved")
                        .foregroundStyle(Morandi.sage)
                }
            }

            if !apiKey.isEmpty {
                Button("Remove API Key", role: .destructive) {
                    apiKey = ""
                    viewModel.saveAPIKey("", for: storageID)
                }
            }
        }
    }

    // MARK: - Title / Capability helpers

    private var titleText: String {
        if provider == .custom, let id = customProviderID {
            let entries = AIProviderCenterView.loadCustomProviders()
            return entries.first(where: { $0.id == id })?.displayName ?? "Custom Provider"
        }
        return ProviderFactory.displayName(for: provider)
    }

    private var storageID: String {
        if provider == .custom, let id = customProviderID { return id }
        return provider.rawValue
    }

    private var capabilityBadges: [String] {
        switch provider {
        case .openai: return ["CHAT", "TOOLS", "VISION", "STREAM"]
        case .anthropic: return ["CHAT", "TOOLS", "VISION", "THINK"]
        case .gemini: return ["CHAT", "TOOLS", "VISION"]
        case .azure: return ["CHAT", "TOOLS"]
        case .volcengine: return ["CHAT", "TOOLS"]
        case .custom: return ["CHAT"]
        }
    }

    // MARK: - Persistence

    private func loadValues() {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        apiKey = viewModel.loadAPIKey(for: storageID)
        baseURL = defaults.string(forKey: "ai_base_url_\(storageID)") ?? ""
        selectedModel = defaults.string(forKey: "ai_model_for_\(storageID)")
            ?? ProviderFactory.defaultModels(for: provider).first
            ?? ""
        deploymentName = defaults.string(forKey: "ai_azure_deployment_\(storageID)") ?? ""
        apiVersion = defaults.string(forKey: "ai_azure_api_version_\(storageID)") ?? "2024-02-15-preview"
        customHeadersText = defaults.string(forKey: "ai_custom_headers_\(storageID)") ?? ""
    }

    private func saveValues() {
        let defaults = UserDefaults(suiteName: "group.ai.papertok.paperreader") ?? .standard
        viewModel.saveAPIKey(apiKey, for: storageID)
        defaults.set(baseURL, forKey: "ai_base_url_\(storageID)")
        defaults.set(selectedModel, forKey: "ai_model_for_\(storageID)")
        defaults.set(deploymentName, forKey: "ai_azure_deployment_\(storageID)")
        defaults.set(apiVersion, forKey: "ai_azure_api_version_\(storageID)")
        defaults.set(customHeadersText, forKey: "ai_custom_headers_\(storageID)")

        if provider == .custom, let id = customProviderID {
            var entries = AIProviderCenterView.loadCustomProviders()
            if let idx = entries.firstIndex(where: { $0.id == id }) {
                entries[idx].baseURL = baseURL
                AIProviderCenterView.saveCustomProviders(entries)
            }
        }
        isSaved = true
    }

    private func parseCustomHeaders() -> [String: String] {
        var headers: [String: String] = [:]
        for line in customHeadersText.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0]] = parts[1]
            }
        }
        return headers
    }

    // MARK: - Connection Test

    private func testConnection() {
        testStatus = .testing
        let key = apiKey
        let base = URL(string: baseURL)
        let deploy = deploymentName
        let ver = apiVersion
        let headers = parseCustomHeaders()
        let model = selectedModel.isEmpty
            ? (ProviderFactory.defaultModels(for: provider).first ?? "gpt-4o-mini")
            : selectedModel
        let kind = provider

        Task {
            do {
                let config = ProviderConfig(
                    apiKey: key.isEmpty ? nil : key,
                    baseURL: base,
                    customHeaders: headers,
                    deploymentName: deploy.isEmpty ? nil : deploy,
                    apiVersion: ver.isEmpty ? nil : ver
                )
                let client = try ProviderFactory.makeProvider(kind: kind, config: config)
                let request = ChatRequest(
                    messages: [.user("ping")],
                    model: model,
                    maxTokens: 1
                )
                _ = try await client.complete(request)
                await MainActor.run {
                    testStatus = .success("Connected")
                }
            } catch {
                await MainActor.run {
                    testStatus = .failure(error.localizedDescription)
                }
            }
        }
    }
}
