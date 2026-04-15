import SwiftUI
import PTAIServices
import PTCore
import PTUI

public struct MCPServerListView: View {
    @State private var servers: [MCPServerConfig] = []
    @State private var didLoad: Bool = false
    @State private var pendingDeletion: MCPServerConfig?
    @State private var showNewSheet: Bool = false

    private let store: MCPServerStore

    public init(store: MCPServerStore = MCPServerStore()) {
        self.store = store
    }

    public var body: some View {
        Group {
            if servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .navigationTitle(String(localized: "settings.mcp.section_title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    MCPServerDetailView(serverId: nil, store: store, onDismiss: { Task { await refresh() } })
                } label: {
                    Label(String(localized: "settings.mcp.add_button"), systemImage: "plus")
                }
            }
        }
        .task {
            if !didLoad {
                await refresh()
                didLoad = true
            }
        }
        .refreshable {
            await refresh()
        }
        .confirmationDialog(
            String(localized: "settings.mcp.delete.confirm.title"),
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { server in
            Button(String(localized: "common.delete"), role: .destructive) {
                Task { await delete(server) }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { _ in
            Text("settings.mcp.delete.confirm.message")
        }
    }

    private var serverList: some View {
        List {
            ForEach(servers) { server in
                NavigationLink {
                    MCPServerDetailView(serverId: server.id, store: store, onDismiss: { Task { await refresh() } })
                } label: {
                    MCPServerListRow(server: server)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDeletion = server
                    } label: {
                        Label(String(localized: "common.delete"), systemImage: "trash")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 42))
                .foregroundStyle(Morandi.tertiaryText)
            Text("settings.mcp.empty.title")
                .font(AppTypography.body.weight(.medium))
                .foregroundStyle(Morandi.primaryText)
            Text("settings.mcp.empty.body")
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
            NavigationLink {
                MCPServerDetailView(serverId: nil, store: store, onDismiss: { Task { await refresh() } })
            } label: {
                Label(String(localized: "settings.mcp.add_button"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Morandi.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func refresh() async {
        servers = await store.load()
    }

    private func delete(_ server: MCPServerConfig) async {
        try? await store.remove(id: server.id)
        await refresh()
    }
}

private struct MCPServerListRow: View {
    let server: MCPServerConfig

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: server.transportType == .stdio ? "terminal" : "globe")
                .foregroundStyle(Morandi.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.isEmpty ? String(localized: "common.untitled") : server.name)
                    .font(AppTypography.body.weight(.medium))
                    .foregroundStyle(Morandi.primaryText)
                Text(subtitle)
                    .font(AppTypography.caption2)
                    .foregroundStyle(Morandi.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Image(systemName: server.isEnabled ? "circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundStyle(server.isEnabled ? Morandi.sage : Morandi.tertiaryText)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        switch server.transportType {
        case .stdio:
            return server.command ?? ""
        case .httpSSE:
            return server.url
        }
    }
}
