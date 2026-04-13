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
    @State private var showAPIKey = false
    @State private var originalApiKey: String = ""
    @State private var originalBaseURL: String = ""
    @State private var originalModel: String = ""
    @State private var showDeleteConfirmation = false

    // Generation defaults
    @State private var temperature: Double = 0.7
    @State private var topP: Double = 1.0
    @State private var maxTokensText: String = "4096"
    @State private var presencePenalty: Double = 0.0
    @State private var frequencyPenalty: Double = 0.0
    @State private var stopSequencesText: String = ""
    @State private var advancedExpanded: Bool = false

    // Provider-specific
    @State private var includeThoughts: Bool = true
    @State private var safetySettings: String = "default" // default | strict | relaxed
    @State private var reasoningEffort: String = "medium" // minimal | low | medium | high
    @State private var returnReasoningSummary: Bool = false
    @State private var usePreviousResponseId: Bool = false

    // Failover policy
    @State private var failureThreshold: Int = 3
    @State private var authCooldownSeconds: Int = 900
    @State private var rateLimitCooldownSeconds: Int = 60
    @State private var serviceCooldownSeconds: Int = 300

    // Multi-key count for navigation badge
    @State private var apiKeyCount: Int = 0

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
            multiKeySection
            endpointSection
            modelSection
            if provider == .azure { azureSection }
            if provider == .custom { customHeadersSection }
            capabilitiesSection
            generationDefaultsSection
            providerSpecificSection
            failoverPolicySection
            testSection
            saveSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(titleText)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if hasUnsavedChanges {
                ToolbarItem(placement: .automatic) {
                    Text("settings.ai_provider.unsaved")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Morandi.clay.opacity(0.25)))
                        .foregroundStyle(Morandi.clay)
                }
            }
        }
        .confirmationDialog(
            "Delete this custom provider?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Provider", role: .destructive) { deleteCustomProvider() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: loadValues)
    }

    private func deleteCustomProvider() {
        guard let id = customProviderID else { return }
        var entries = AIProviderCenterView.loadCustomProviders()
        entries.removeAll { $0.id == id }
        AIProviderCenterView.saveCustomProviders(entries)
        viewModel.saveAPIKey("", for: storageID)
    }

    // MARK: - Sections

    private var apiKeySection: some View {
        Section {
            HStack(spacing: AppSpacing.sm) {
                Group {
                    if showAPIKey {
                        TextField("API Key", text: $apiKey)
                    } else {
                        SecureField("API Key", text: $apiKey)
                    }
                }
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

                Button {
                    showAPIKey.toggle()
                } label: {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(Morandi.secondaryText)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(showAPIKey ? "Hide API key" : "Show API key")
            }

            if let url = getApiKeyURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Text("settings.ai_provider.get_api_key")
                            .font(AppTypography.caption)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(Morandi.accent)
                }
            }
        } header: {
            Text("common.authentication")
        } footer: {
            Text("ai.providers.keychain_short")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var getApiKeyURL: URL? {
        switch provider {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini: return URL(string: "https://aistudio.google.com/app/apikey")
        case .azure: return URL(string: "https://portal.azure.com/")
        case .volcengine: return URL(string: "https://console.volcengine.com/ark")
        case .custom: return nil
        }
    }

    private var hasUnsavedChanges: Bool {
        apiKey != originalApiKey || baseURL != originalBaseURL || selectedModel != originalModel
    }

    private var isValid: Bool {
        if provider == .custom {
            return !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var endpointSection: some View {
        Section(String(localized: "common.endpoint")) {
            TextField("Base URL (optional override)", text: $baseURL)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
        }
    }

    private var modelSection: some View {
        Section(String(localized: "common.model")) {
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
        Section(String(localized: "ai.providers.azure")) {
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
            Text("ai.providers.custom_headers")
        } footer: {
            Text("ai.providers.headers_hint")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var capabilitiesSection: some View {
        Section(String(localized: "ai.capabilities")) {
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
                    Text("sync.test_connection")
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
                Text("common.save")
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(isValid ? Morandi.accent : Morandi.tertiaryText)
            }
            .disabled(!isValid)

            if isSaved {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Morandi.sage)
                    Text("common.saved")
                        .foregroundStyle(Morandi.sage)
                }
            }

            if !apiKey.isEmpty {
                Button(String(localized: "ai.providers.remove_api_key"), role: .destructive) {
                    apiKey = ""
                    originalApiKey = ""
                    viewModel.saveAPIKey("", for: storageID)
                }
            }

            if provider == .custom, customProviderID != nil {
                Button("Delete Provider", role: .destructive) {
                    showDeleteConfirmation = true
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

    // MARK: - Multi-key Section

    private var multiKeySection: some View {
        Section {
            NavigationLink {
                APIKeyListView(providerId: storageID)
            } label: {
                HStack {
                    Image(systemName: "key.horizontal.fill")
                        .foregroundStyle(Morandi.lavender)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage API Keys")
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.primaryText)
                        Text("\(apiKeyCount) key\(apiKeyCount == 1 ? "" : "s") configured")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    Spacer()
                }
            }
        } footer: {
            Text("Add multiple API keys for round-robin rotation, automatic failover and per-key cooldowns.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    // MARK: - Generation Defaults

    private var generationDefaultsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $advancedExpanded) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    sliderRow(
                        title: "Temperature",
                        value: $temperature,
                        range: 0.0...2.0,
                        step: 0.05,
                        format: "%.2f"
                    )
                    sliderRow(
                        title: "Top P",
                        value: $topP,
                        range: 0.0...1.0,
                        step: 0.01,
                        format: "%.2f"
                    )
                    HStack {
                        Text("Max Tokens")
                            .foregroundStyle(Morandi.primaryText)
                        Spacer()
                        TextField("4096", text: $maxTokensText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    sliderRow(
                        title: "Presence Penalty",
                        value: $presencePenalty,
                        range: -2.0...2.0,
                        step: 0.1,
                        format: "%.1f"
                    )
                    sliderRow(
                        title: "Frequency Penalty",
                        value: $frequencyPenalty,
                        range: -2.0...2.0,
                        step: 0.1,
                        format: "%.1f"
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stop Sequences")
                            .font(AppTypography.subheadline)
                            .foregroundStyle(Morandi.primaryText)
                        TextField("comma,separated,sequences", text: $stopSequencesText)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                            .font(AppTypography.caption)
                    }
                    Button {
                        resetGenerationDefaults()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.clay)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            } label: {
                Label("Advanced", systemImage: "slider.horizontal.3")
                    .foregroundStyle(Morandi.primaryText)
            }
        } header: {
            Text("Generation Defaults")
        } footer: {
            Text("These values are sent with every chat request unless overridden by a tool or prompt.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(AppTypography.subheadline)
                    .foregroundStyle(Morandi.primaryText)
                Spacer()
                Text(String(format: format, value.wrappedValue))
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(Morandi.secondaryText)
            }
            Slider(value: value, in: range, step: step)
                .tint(Morandi.accent)
        }
    }

    private func resetGenerationDefaults() {
        temperature = 0.7
        topP = 1.0
        maxTokensText = "4096"
        presencePenalty = 0.0
        frequencyPenalty = 0.0
        stopSequencesText = ""
    }

    // MARK: - Provider-Specific

    @ViewBuilder
    private var providerSpecificSection: some View {
        switch provider {
        case .gemini:
            Section("Gemini Options") {
                Toggle("Include Thinking Steps", isOn: $includeThoughts)
                    .tint(Morandi.accent)
                Picker("Safety Settings", selection: $safetySettings) {
                    Text("Default").tag("default")
                    Text("Strict").tag("strict")
                    Text("Relaxed").tag("relaxed")
                }
            }
        case .openai, .anthropic:
            Section("Reasoning") {
                Picker("Reasoning Effort", selection: $reasoningEffort) {
                    Text("Minimal").tag("minimal")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                }
                Toggle("Return Reasoning Summary", isOn: $returnReasoningSummary)
                    .tint(Morandi.accent)
                if provider == .openai {
                    Toggle("Use Previous Response ID", isOn: $usePreviousResponseId)
                        .tint(Morandi.accent)
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Failover Policy

    private var failoverPolicySection: some View {
        Section {
            Picker("Failure Threshold", selection: $failureThreshold) {
                ForEach(1...10, id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            cooldownPicker(title: "Auth Cooldown (401)", selection: $authCooldownSeconds)
            cooldownPicker(title: "Rate Limit Cooldown (429)", selection: $rateLimitCooldownSeconds)
            cooldownPicker(title: "Service Cooldown (5xx)", selection: $serviceCooldownSeconds)
        } header: {
            Text("Failover Policy")
        } footer: {
            Text("After N consecutive failures the key is marked failed; cooldowns control how long until it is retried.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private static let cooldownOptions: [(Int, String)] = [
        (60, "1 min"),
        (300, "5 min"),
        (900, "15 min"),
        (3600, "1 hour"),
        (21600, "6 hours"),
        (86400, "24 hours")
    ]

    @ViewBuilder
    private func cooldownPicker(title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Self.cooldownOptions, id: \.0) { (seconds, label) in
                Text(label).tag(seconds)
            }
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
        originalApiKey = apiKey
        originalBaseURL = baseURL
        originalModel = selectedModel

        // Generation defaults
        let id = storageID
        if defaults.object(forKey: "ai_temperature_\(id)") != nil {
            temperature = defaults.double(forKey: "ai_temperature_\(id)")
        }
        if defaults.object(forKey: "ai_top_p_\(id)") != nil {
            topP = defaults.double(forKey: "ai_top_p_\(id)")
        }
        maxTokensText = defaults.string(forKey: "ai_max_tokens_\(id)") ?? "4096"
        if defaults.object(forKey: "ai_presence_penalty_\(id)") != nil {
            presencePenalty = defaults.double(forKey: "ai_presence_penalty_\(id)")
        }
        if defaults.object(forKey: "ai_frequency_penalty_\(id)") != nil {
            frequencyPenalty = defaults.double(forKey: "ai_frequency_penalty_\(id)")
        }
        stopSequencesText = defaults.string(forKey: "ai_stop_sequences_\(id)") ?? ""

        // Provider-specific
        if defaults.object(forKey: "ai_include_thoughts_\(id)") != nil {
            includeThoughts = defaults.bool(forKey: "ai_include_thoughts_\(id)")
        }
        safetySettings = defaults.string(forKey: "ai_safety_\(id)") ?? "default"
        reasoningEffort = defaults.string(forKey: "ai_reasoning_effort_\(id)") ?? "medium"
        returnReasoningSummary = defaults.bool(forKey: "ai_reasoning_summary_\(id)")
        usePreviousResponseId = defaults.bool(forKey: "ai_prev_response_id_\(id)")

        // Failover
        if defaults.object(forKey: "ai_failure_threshold_\(id)") != nil {
            failureThreshold = defaults.integer(forKey: "ai_failure_threshold_\(id)")
        }
        if defaults.object(forKey: "ai_cooldown_auth_\(id)") != nil {
            authCooldownSeconds = defaults.integer(forKey: "ai_cooldown_auth_\(id)")
        }
        if defaults.object(forKey: "ai_cooldown_rate_\(id)") != nil {
            rateLimitCooldownSeconds = defaults.integer(forKey: "ai_cooldown_rate_\(id)")
        }
        if defaults.object(forKey: "ai_cooldown_service_\(id)") != nil {
            serviceCooldownSeconds = defaults.integer(forKey: "ai_cooldown_service_\(id)")
        }

        apiKeyCount = APIKeyStore.load(providerId: id).count
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
        // Generation defaults
        let id = storageID
        defaults.set(temperature, forKey: "ai_temperature_\(id)")
        defaults.set(topP, forKey: "ai_top_p_\(id)")
        defaults.set(maxTokensText, forKey: "ai_max_tokens_\(id)")
        defaults.set(presencePenalty, forKey: "ai_presence_penalty_\(id)")
        defaults.set(frequencyPenalty, forKey: "ai_frequency_penalty_\(id)")
        defaults.set(stopSequencesText, forKey: "ai_stop_sequences_\(id)")

        defaults.set(includeThoughts, forKey: "ai_include_thoughts_\(id)")
        defaults.set(safetySettings, forKey: "ai_safety_\(id)")
        defaults.set(reasoningEffort, forKey: "ai_reasoning_effort_\(id)")
        defaults.set(returnReasoningSummary, forKey: "ai_reasoning_summary_\(id)")
        defaults.set(usePreviousResponseId, forKey: "ai_prev_response_id_\(id)")

        defaults.set(failureThreshold, forKey: "ai_failure_threshold_\(id)")
        defaults.set(authCooldownSeconds, forKey: "ai_cooldown_auth_\(id)")
        defaults.set(rateLimitCooldownSeconds, forKey: "ai_cooldown_rate_\(id)")
        defaults.set(serviceCooldownSeconds, forKey: "ai_cooldown_service_\(id)")

        isSaved = true
        originalApiKey = apiKey
        originalBaseURL = baseURL
        originalModel = selectedModel
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
