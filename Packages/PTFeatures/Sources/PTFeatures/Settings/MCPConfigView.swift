import SwiftUI
import PTAIServices
import PTUI

/// Settings screen for configuring MCP (Model Context Protocol) servers.
///
/// Allows adding, editing, removing, and toggling MCP server connections.
/// Displays connection status and discovered tools for each server.
public struct MCPConfigView: View {
    @State private var configs: [MCPServerConfig]
    @State private var statuses: [String: MCPConnectionStatus] = [:]
    @State private var showAddSheet = false
    @State private var editingConfig: MCPServerConfig?

    private let store: MCPConfigStore

    public init(store: MCPConfigStore = MCPConfigStore()) {
        self.store = store
        _configs = State(initialValue: store.loadConfigs())
    }

    public var body: some View {
        List {
            if configs.isEmpty {
                emptySection
            } else {
                serversSection
            }

            addSection
        }
        .navigationTitle(String(localized: "settings.mcp_servers"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showAddSheet) {
            MCPServerEditSheet(
                config: nil,
                onSave: { newConfig in
                    configs.append(newConfig)
                    save()
                }
            )
        }
        .sheet(item: $editingConfig) { config in
            MCPServerEditSheet(
                config: config,
                onSave: { updated in
                    if let idx = configs.firstIndex(where: { $0.id == updated.id }) {
                        configs[idx] = updated
                        save()
                    }
                }
            )
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: AppSpacing.md) {
                Image(systemName: "server.rack")
                    .font(.system(size: 36))
                    .foregroundStyle(Morandi.tertiaryText)
                Text("ai.mcp.empty")
                    .font(AppTypography.body)
                    .foregroundStyle(Morandi.secondaryText)
                Text("ai.mcp.add_hint")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.lg)
        }
    }

    private var serversSection: some View {
        Section(String(localized: "common.servers")) {
            ForEach(configs) { config in
                MCPServerRow(
                    config: config,
                    status: statuses[config.id] ?? .disconnected,
                    onToggle: { enabled in
                        toggleServer(id: config.id, enabled: enabled)
                    },
                    onEdit: {
                        editingConfig = config
                    },
                    onTest: {
                        testConnection(config: config)
                    }
                )
            }
            .onDelete(perform: deleteServers)
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showAddSheet = true
            } label: {
                Label(String(localized: "ai.mcp.add_server"), systemImage: "plus.circle")
                    .foregroundStyle(Morandi.accent)
            }
        }
    }

    private func toggleServer(id: String, enabled: Bool) {
        if let idx = configs.firstIndex(where: { $0.id == id }) {
            configs[idx].isEnabled = enabled
            if !enabled {
                statuses[id] = .disconnected
            }
            save()
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            statuses.removeValue(forKey: configs[index].id)
        }
        configs.remove(atOffsets: offsets)
        save()
    }

    private func testConnection(config: MCPServerConfig) {
        statuses[config.id] = .connecting
        Task {
            do {
                guard let url = URL(string: config.url) else {
                    await MainActor.run { statuses[config.id] = .error("Invalid URL") }
                    return
                }
                let transport = MCPHTTPSSETransport(serverURL: url, apiKey: config.apiKey)
                let client = MCPClient(transport: transport)
                let capabilities = try await client.initialize()
                let tools = try await client.listTools()

                // Update config with discovered tools
                if let idx = configs.firstIndex(where: { $0.id == config.id }) {
                    configs[idx].discoveredTools = tools
                    save()
                }

                await MainActor.run {
                    statuses[config.id] = .connected(toolCount: tools.count)
                }

                try await client.shutdown()
            } catch {
                await MainActor.run {
                    statuses[config.id] = .error(error.localizedDescription)
                }
            }
        }
    }

    private func save() {
        store.saveConfigs(configs)
    }
}

// MARK: - Server Row

struct MCPServerRow: View {
    let config: MCPServerConfig
    let status: MCPConnectionStatus
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(config.name)
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(Morandi.primaryText)
                    Text(config.url)
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { config.isEnabled },
                    set: { onToggle($0) }
                ))
                .labelsHidden()
                .tint(Morandi.accent)
            }

            HStack(spacing: AppSpacing.sm) {
                statusIndicator
                Text(status.displayText)
                    .font(AppTypography.caption2)
                    .foregroundStyle(statusColor)

                Spacer()

                Button(String(localized: "common.test")) { onTest() }
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
                    .buttonStyle(.plain)

                Button(String(localized: "common.edit")) { onEdit() }
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
                    .buttonStyle(.plain)
            }

            if !config.discoveredTools.isEmpty {
                DisclosureGroup {
                    ForEach(config.discoveredTools) { tool in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.name)
                                .font(AppTypography.caption.weight(.medium))
                                .foregroundStyle(Morandi.primaryText)
                            Text(tool.description)
                                .font(AppTypography.caption2)
                                .foregroundStyle(Morandi.secondaryText)
                        }
                        .padding(.vertical, 2)
                    }
                } label: {
                    Text("\(config.discoveredTools.count) tools")
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch status {
        case .disconnected: return Morandi.tertiaryText
        case .connecting: return Morandi.accent
        case .connected: return Morandi.sage
        case .error: return Morandi.destructive
        }
    }
}

// MARK: - Edit Sheet

struct MCPServerEditSheet: View {
    let config: MCPServerConfig?
    let onSave: (MCPServerConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var url: String
    @State private var apiKey: String

    init(config: MCPServerConfig?, onSave: @escaping (MCPServerConfig) -> Void) {
        self.config = config
        self.onSave = onSave
        _name = State(initialValue: config?.name ?? "")
        _url = State(initialValue: config?.url ?? "")
        _apiKey = State(initialValue: config?.apiKey ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "ai.mcp.server_details")) {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                }

                Section(String(localized: "common.authentication")) {
                    SecureField("API Key (optional)", text: $apiKey)
                }
            }
            .navigationTitle(config == nil ? "Add Server" : "Edit Server")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.save")) {
                        let updated = MCPServerConfig(
                            id: config?.id ?? UUID().uuidString,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                            apiKey: apiKey.isEmpty ? nil : apiKey,
                            isEnabled: config?.isEnabled ?? true,
                            transportType: config?.transportType ?? .httpSSE,
                            discoveredTools: config?.discoveredTools ?? []
                        )
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
