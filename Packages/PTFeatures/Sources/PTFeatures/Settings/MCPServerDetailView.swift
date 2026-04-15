import SwiftUI
import PTAIServices
import PTCore
import PTUI

public struct MCPServerDetailView: View {
    @State private var viewModel: MCPServerDetailViewModel
    @State private var didLoad: Bool = false
    @State private var runningTool: MCPToolSummary?
    @State private var nameText: String = ""
    @State private var urlText: String = ""
    @State private var apiKeyText: String = ""
    @State private var commandText: String = ""
    @State private var argumentsText: String = ""
    @State private var envRows: [KeyValueRow] = []
    @State private var headerRows: [KeyValueRow] = []

    private let serverId: String?
    private let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        serverId: String?,
        store: MCPServerStore = MCPServerStore(),
        onDismiss: @escaping () -> Void = {}
    ) {
        self.serverId = serverId
        self.onDismiss = onDismiss
        _viewModel = State(initialValue: MCPServerDetailViewModel(store: store))
    }

    public var body: some View {
        Form {
            generalSection
            connectionSection
            if viewModel.draft.transportType == .httpSSE {
                authSection
            }
            if viewModel.isSaved {
                toolsSection
            }
            diagnosticsSection
            if let error = viewModel.connectionError {
                Section {
                    Text(error)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.destructive)
                }
            }
        }
        .navigationTitle(
            viewModel.isNew
                ? String(localized: "settings.mcp.detail.title_new")
                : String(localized: "settings.mcp.detail.title_edit")
        )
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "common.cancel")) {
                    onDismiss()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "settings.mcp.save_button")) {
                    Task { await saveTapped() }
                }
            }
        }
        .task {
            if !didLoad {
                await viewModel.load(serverId: serverId)
                hydrateLocalFields()
                didLoad = true
            }
        }
        .sheet(item: $runningTool) { tool in
            MCPToolRunSheet(
                toolName: tool.name,
                initialArgs: tool.parametersJSON ?? "{}",
                result: viewModel.toolRunResult,
                errorMessage: viewModel.toolRunError
            ) { args in
                await viewModel.runTool(name: tool.name, argumentsJSON: args)
            }
        }
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section(String(localized: "settings.mcp.general.section")) {
            TextField(
                String(localized: "settings.mcp.general.name.placeholder"),
                text: $nameText
            )
            .onChange(of: nameText) { _, newValue in viewModel.updateName(newValue) }

            Picker(String(localized: "settings.mcp.general.transport"), selection: Binding(
                get: { viewModel.draft.transportType },
                set: { viewModel.updateTransport($0) }
            )) {
                Text("settings.mcp.transport.http_sse").tag(MCPTransportType.httpSSE)
                Text("settings.mcp.transport.stdio").tag(MCPTransportType.stdio)
            }
            .pickerStyle(.segmented)

            Toggle(String(localized: "settings.mcp.general.enabled"), isOn: Binding(
                get: { viewModel.draft.isEnabled },
                set: { viewModel.updateEnabled($0) }
            ))
        }
    }

    private var connectionSection: some View {
        Section(String(localized: "settings.mcp.connection.section")) {
            switch viewModel.draft.transportType {
            case .httpSSE:
                TextField(
                    String(localized: "settings.mcp.connection.url"),
                    text: $urlText
                )
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onChange(of: urlText) { _, v in viewModel.updateURL(v) }
                if !urlText.isEmpty && URL(string: urlText) == nil {
                    Text("settings.mcp.connection.url.invalid")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.destructive)
                }
            case .stdio:
                TextField(
                    String(localized: "settings.mcp.connection.command"),
                    text: $commandText
                )
                .autocorrectionDisabled()
                .onChange(of: commandText) { _, v in viewModel.updateCommand(v) }

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("settings.mcp.connection.arguments")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    TextEditor(text: $argumentsText)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 80)
                        .onChange(of: argumentsText) { _, v in
                            let lines = v.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                            viewModel.updateArguments(lines.filter { !$0.isEmpty })
                        }
                }

                KeyValueEditor(
                    title: String(localized: "settings.mcp.connection.environment"),
                    addLabel: String(localized: "settings.mcp.connection.env.add"),
                    keyPlaceholder: String(localized: "settings.mcp.connection.env.key"),
                    valuePlaceholder: String(localized: "settings.mcp.connection.env.value"),
                    rows: $envRows
                )
                .onChange(of: envRows) { _, newRows in
                    viewModel.updateEnvironment(KeyValueRow.dictionary(from: newRows))
                }
            }
        }
    }

    private var authSection: some View {
        Section(String(localized: "settings.mcp.auth.section")) {
            SecureField(
                String(localized: "settings.mcp.auth.api_key.placeholder"),
                text: $apiKeyText
            )
            .onChange(of: apiKeyText) { _, v in viewModel.updateAPIKey(v) }

            KeyValueEditor(
                title: String(localized: "settings.mcp.auth.custom_headers"),
                addLabel: String(localized: "settings.mcp.auth.headers.add"),
                keyPlaceholder: String(localized: "settings.mcp.connection.env.key"),
                valuePlaceholder: String(localized: "settings.mcp.connection.env.value"),
                rows: $headerRows
            )
            .onChange(of: headerRows) { _, newRows in
                viewModel.updateCustomHeaders(KeyValueRow.dictionary(from: newRows))
            }
        }
    }

    private var toolsSection: some View {
        Section(String(localized: "settings.mcp.tools.section")) {
            Button {
                Task { await viewModel.connectAndListTools() }
            } label: {
                HStack {
                    if viewModel.isConnecting {
                        ProgressView()
                        Text("settings.mcp.tools.connecting")
                    } else {
                        Image(systemName: "link")
                        Text("settings.mcp.tools.connect_button")
                    }
                }
            }
            .disabled(viewModel.isConnecting)

            ForEach(viewModel.tools) { tool in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(AppTypography.body.weight(.medium))
                        if let desc = tool.description {
                            Text(desc)
                                .font(AppTypography.caption2)
                                .foregroundStyle(Morandi.secondaryText)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                    Button(String(localized: "settings.mcp.tools.test_run")) {
                        viewModel.clearToolRunResult()
                        runningTool = tool
                    }
                    .buttonStyle(.bordered)
                    .font(AppTypography.caption)
                }
            }
        }
    }

    private var diagnosticsSection: some View {
        Section(String(localized: "settings.mcp.diagnostics.section")) {
            HStack {
                Text("settings.mcp.diagnostics.last_attempt")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                Spacer()
                Text(lastAttemptText)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.primaryText)
            }
            HStack {
                Text("settings.mcp.tools.section")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                Spacer()
                Text(toolCountText)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.primaryText)
            }
            if let err = viewModel.connectionError {
                HStack(alignment: .top) {
                    Text("settings.mcp.diagnostics.last_error")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    Spacer()
                    Text(err)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.destructive)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    // MARK: - Helpers

    private var lastAttemptText: String {
        guard let date = viewModel.lastConnectionAttempt else {
            return String(localized: "settings.mcp.diagnostics.never")
        }
        return date.formatted(.relative(presentation: .numeric))
    }

    private var toolCountText: String {
        if viewModel.tools.isEmpty {
            return String(localized: "settings.mcp.tools.not_connected")
        }
        return AppLocalization.format(
            "settings.mcp.tools.connected_format",
            locale: .autoupdatingCurrent,
            viewModel.tools.count
        )
    }

    private func hydrateLocalFields() {
        nameText = viewModel.draft.name
        urlText = viewModel.draft.url
        apiKeyText = viewModel.draft.apiKey ?? ""
        commandText = viewModel.draft.command ?? ""
        argumentsText = viewModel.draft.arguments.joined(separator: "\n")
        envRows = KeyValueRow.rows(from: viewModel.draft.environment)
        headerRows = KeyValueRow.rows(from: viewModel.draft.customHeaders)
    }

    private func saveTapped() async {
        do {
            try await viewModel.save()
            onDismiss()
            dismiss()
        } catch {
            // connectionError already populated by view model
        }
    }
}

