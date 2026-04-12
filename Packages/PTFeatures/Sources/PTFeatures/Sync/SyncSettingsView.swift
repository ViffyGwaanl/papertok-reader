import SwiftUI
import PTCore
import PTUI

/// Settings view for configuring WebDAV sync and local backup/restore.
public struct SyncSettingsView: View {
    @State private var syncService = WebDAVSyncService()
    @State private var webdavURL: String = ""
    @State private var webdavUsername: String = ""
    @State private var webdavPassword: String = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showCredentialEditor = false

    public init() {}

    public var body: some View {
        Form {
            webdavSection
            syncOptionsSection
            syncActionsSection
            backupSection
        }
        .navigationTitle(String(localized: "settings.sync_backup"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear(perform: loadCredentials)
    }

    // MARK: - WebDAV Configuration

    private var webdavSection: some View {
        Section {
            if showCredentialEditor {
                credentialFields
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WebDAV Server")
                            .font(AppTypography.body)
                            .foregroundStyle(Morandi.primaryText)
                        if webdavURL.isEmpty {
                            Text("Not configured")
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.tertiaryText)
                        } else {
                            Text(webdavURL)
                                .font(AppTypography.caption)
                                .foregroundStyle(Morandi.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button(webdavURL.isEmpty ? "Configure" : "Edit") {
                        showCredentialEditor = true
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
                }
            }

            Toggle("Auto-sync", isOn: $syncService.autoSyncEnabled)
                .tint(Morandi.accent)
                .foregroundStyle(Morandi.primaryText)

            if let testResult {
                HStack {
                    Image(systemName: testResult.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(testResult.contains("Success") ? Morandi.sage : Morandi.destructive)
                    Text(testResult)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        } header: {
            Text("WebDAV Sync")
        }
    }

    @ViewBuilder
    private var credentialFields: some View {
        TextField("Server URL", text: $webdavURL)
            #if os(iOS)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

        TextField("Username", text: $webdavUsername)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            #endif
            .autocorrectionDisabled()

        SecureField("Password", text: $webdavPassword)

        HStack {
            Button("Test Connection") {
                Task { await testConnection() }
            }
            .disabled(webdavURL.isEmpty || isTesting)
            .foregroundStyle(Morandi.accent)

            Spacer()

            Button("Save") {
                saveCredentials()
                showCredentialEditor = false
            }
            .disabled(webdavURL.isEmpty)
            .foregroundStyle(Morandi.accent)
        }
    }

    // MARK: - Sync Options

    private var syncOptionsSection: some View {
        Section {
            Picker("Conflict strategy", selection: Binding(
                get: { syncService.conflictStrategy },
                set: { syncService.conflictStrategy = $0 }
            )) {
                Text("Last modified wins").tag(ConflictStrategy.lastModifiedWins)
                Text("Local wins").tag(ConflictStrategy.localWins)
                Text("Remote wins").tag(ConflictStrategy.remoteWins)
                Text("Ask me").tag(ConflictStrategy.manual)
            }
            .foregroundStyle(Morandi.primaryText)

            Toggle("Sync AI settings", isOn: Binding(
                get: { syncService.aiSettingsSyncEnabled },
                set: { syncService.aiSettingsSyncEnabled = $0 }
            ))
            .tint(Morandi.accent)
            .foregroundStyle(Morandi.primaryText)

            NavigationLink("Connection tester") {
                ConnectionTesterView(syncService: syncService)
            }
            .foregroundStyle(Morandi.primaryText)
        } header: {
            Text("Sync Options")
        }
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        Section {
            Button {
                Task { await syncService.incrementalSync() }
            } label: {
                HStack {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Morandi.primaryText)
                    Spacer()
                    if syncService.status == .syncing {
                        ProgressView()
                    }
                }
            }
            .disabled(syncService.status == .syncing || webdavURL.isEmpty)

            Button {
                Task { await syncService.sync() }
            } label: {
                Label("Full Sync (Legacy)", systemImage: "arrow.up.arrow.down.circle")
                    .foregroundStyle(Morandi.secondaryText)
            }
            .disabled(syncService.status == .syncing || webdavURL.isEmpty)

            Button {
                Task { await syncService.restore() }
            } label: {
                Label("Restore from Server", systemImage: "arrow.down.circle")
                    .foregroundStyle(Morandi.primaryText)
            }
            .disabled(syncService.status == .syncing || webdavURL.isEmpty)

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Text("Last sync")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    Spacer()
                    Text(lastSync, style: .relative)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }

            if let error = syncService.errorMessage {
                Text(error)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.destructive)
            }
        } header: {
            Text("Sync")
        }
    }

    // MARK: - Local Backup

    private var backupSection: some View {
        Section {
            Button {
                Task { await exportBackup() }
            } label: {
                Label("Export Backup", systemImage: "square.and.arrow.up")
                    .foregroundStyle(Morandi.primaryText)
            }

            Button {
                // Import handled via document picker
            } label: {
                Label("Import Backup", systemImage: "square.and.arrow.down")
                    .foregroundStyle(Morandi.primaryText)
            }
        } header: {
            Text("Local Backup")
        } footer: {
            Text("Exports the database and all book files as a zip archive.")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    // MARK: - Actions

    private func loadCredentials() {
        webdavURL = (try? KeychainService.load(key: "webdav_url")) ?? ""
        webdavUsername = (try? KeychainService.load(key: "webdav_user")) ?? ""
        webdavPassword = ""
    }

    private func saveCredentials() {
        try? syncService.saveCredentials(
            url: webdavURL,
            username: webdavUsername,
            password: webdavPassword
        )
        testResult = nil
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let ok = await syncService.testConnection()
        testResult = ok ? "Success — connected" : "Failed — check credentials"
        isTesting = false
    }

    private func exportBackup() async {
        // BackupService.exportZip() integration point
    }
}
