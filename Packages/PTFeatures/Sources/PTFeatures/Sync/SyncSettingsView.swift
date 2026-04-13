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
    @State private var didLastConnectionSucceed: Bool?
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
            HStack(spacing: AppSpacing.sm) {
                Circle()
                    .fill(connectionStatusColor)
                    .frame(width: 10, height: 10)
                TextField(String(localized: "common.server_url"), text: $webdavURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
            }

            TextField(String(localized: "common.username"), text: $webdavUsername)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            SecureField(String(localized: "common.password"), text: $webdavPassword)

            HStack {
                Button(String(localized: "sync.test_connection")) {
                    Task { await testConnection() }
                }
                .disabled(webdavURL.isEmpty || isTesting)
                .foregroundStyle(Morandi.accent)

                Spacer()

                Button(String(localized: "common.save")) {
                    saveCredentials()
                }
                .disabled(webdavURL.isEmpty)
                .foregroundStyle(Morandi.accent)
            }

            Toggle(String(localized: "sync.auto_sync"), isOn: $syncService.autoSyncEnabled)
                .tint(Morandi.accent)
                .foregroundStyle(Morandi.primaryText)

            if let testResult {
                HStack {
                    Image(systemName: (didLastConnectionSucceed == true) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle((didLastConnectionSucceed == true) ? Morandi.sage : Morandi.destructive)
                    Text(testResult)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        } header: {
            Text("sync.webdav")
        } footer: {
            Text("sync.keychain_hint")
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)
        }
    }

    private var connectionStatusColor: Color {
        guard !webdavURL.isEmpty else { return Morandi.tertiaryText }
        if let didLastConnectionSucceed {
            return didLastConnectionSucceed ? Morandi.sage : Morandi.destructive
        }
        return Morandi.tertiaryText
    }

    // MARK: - Sync Options

    private var syncOptionsSection: some View {
        Section {
            Picker(String(localized: "sync.conflict_strategy"), selection: $syncService.conflictStrategy) {
                Text("sync.last_modified_wins").tag(ConflictStrategy.lastModifiedWins)
                Text("sync.local_wins").tag(ConflictStrategy.localWins)
                Text("sync.remote_wins").tag(ConflictStrategy.remoteWins)
                Text("ai.ask_me").tag(ConflictStrategy.manual)
            }
            .foregroundStyle(Morandi.primaryText)

            Text(conflictStrategyDescription)
                .font(AppTypography.caption2)
                .foregroundStyle(Morandi.tertiaryText)

            Toggle(String(localized: "sync.sync_ai_settings"), isOn: $syncService.aiSettingsSyncEnabled)
                .tint(Morandi.accent)
                .foregroundStyle(Morandi.primaryText)

            NavigationLink(String(localized: "sync.connection_tester")) {
                ConnectionTesterView(syncService: syncService)
            }
            .foregroundStyle(Morandi.primaryText)
        } header: {
            Text("sync.sync_options")
        }
    }

    // MARK: - Sync Actions

    private var syncActionsSection: some View {
        Section {
            Button {
                Task { await syncService.incrementalSync() }
            } label: {
                HStack {
                    Label(String(localized: "sync.sync_now"), systemImage: "arrow.triangle.2.circlepath")
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
                Label(String(localized: "sync.full_sync_legacy"), systemImage: "arrow.up.arrow.down.circle")
                    .foregroundStyle(Morandi.secondaryText)
            }
            .disabled(syncService.status == .syncing || webdavURL.isEmpty)

            Button {
                Task { await syncService.restore() }
            } label: {
                Label(String(localized: "sync.restore_from_server"), systemImage: "arrow.down.circle")
                    .foregroundStyle(Morandi.primaryText)
            }
            .disabled(syncService.status == .syncing || webdavURL.isEmpty)

            if syncService.status == .syncing {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Morandi.accent)
            }

            if let lastSync = syncService.lastSyncDate {
                HStack {
                    Text("sync.last_sync")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.secondaryText)
                    Spacer()
                    Text(lastSync, format: .relative(presentation: .named))
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }

            if let error = syncService.errorMessage {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack(alignment: .top, spacing: AppSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Morandi.destructive)
                        Text(error)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.destructive)
                    }
                    Button("common.retry") {
                        Task { await syncService.incrementalSync() }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
                }
            }
        } header: {
            Text("settings.sync")
        }
    }

    private var conflictStrategyDescription: String {
        switch syncService.conflictStrategy {
        case .lastModifiedWins:
            return String(localized: "sync.conflict_description.last_modified_wins")
        case .localWins:
            return String(localized: "sync.conflict_description.local_wins")
        case .remoteWins:
            return String(localized: "sync.conflict_description.remote_wins")
        case .manual:
            return String(localized: "sync.conflict_description.manual")
        }
    }

    // MARK: - Local Backup

    private var backupSection: some View {
        Section {
            Button {
                Task { await exportBackup() }
            } label: {
                Label(String(localized: "settings.export_backup"), systemImage: "square.and.arrow.up")
                    .foregroundStyle(Morandi.primaryText)
            }

            Button {
                // Import handled via document picker
            } label: {
                Label(String(localized: "settings.import_backup"), systemImage: "square.and.arrow.down")
                    .foregroundStyle(Morandi.primaryText)
            }
        } header: {
            Text("sync.local_backup")
        } footer: {
            Text("settings.storage.export_bundle_hint")
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
        didLastConnectionSucceed = nil
    }

    private func testConnection() async {
        isTesting = true
        testResult = nil
        let ok = await syncService.testConnection()
        didLastConnectionSucceed = ok
        testResult = ok
            ? String(localized: "sync.connection_status.success")
            : String(localized: "sync.connection_status.failure")
        isTesting = false
    }

    private func exportBackup() async {
        // BackupService.exportZip() integration point
    }
}
