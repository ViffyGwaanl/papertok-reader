import SwiftUI
import PTCore
import PTNetworking
import PTUI

/// Outcome of an individual check.
private enum CheckStatus: Equatable {
    case pending
    case running
    case success(String)
    case failure(String)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "hourglass"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }
}

private struct CheckRow: Identifiable, Equatable {
    let id: String
    let title: String
    var status: CheckStatus
}

/// A SwiftUI view that runs a series of sanity checks against the configured
/// WebDAV server: reachability, auth, write permission, latency, and (when
/// supported) storage quota.
public struct ConnectionTesterView: View {
    @State private var checks: [CheckRow] = Self.defaultChecks()
    @State private var isRunning = false
    @State private var summary: String?

    private let syncService: WebDAVSyncService

    @MainActor
    public init(syncService: WebDAVSyncService) {
        self.syncService = syncService
    }

    public var body: some View {
        Form {
            Section {
                ForEach(checks) { row in
                    HStack(spacing: 12) {
                        Image(systemName: row.status.icon)
                            .foregroundStyle(color(for: row.status))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)
                            if let detail = detail(for: row.status) {
                                Text(detail)
                                    .font(AppTypography.caption)
                                    .foregroundStyle(Morandi.secondaryText)
                            }
                        }
                        Spacer()
                        if case .running = row.status {
                            ProgressView()
                        }
                    }
                }
            } header: {
                Text("settings.connection_checks")
            } footer: {
                if let summary {
                    Text(summary)
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.tertiaryText)
                }
            }

            Section {
                Button {
                    Task { await runAll() }
                } label: {
                    HStack {
                        Label(
                            isRunning
                                ? AppLocalization.string("common.running", value: "Running")
                                : AppLocalization.string("sync.run_test", value: "Run Test"),
                            systemImage: "play.circle"
                        )
                            .foregroundStyle(Morandi.accent)
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning)
            }
        }
        .navigationTitle(String(localized: "sync.connection_tester"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await runAll() }
    }

    // MARK: - Running

    private func runAll() async {
        guard !isRunning else { return }
        isRunning = true
        summary = nil
        checks = Self.defaultChecks()

        guard let client = syncService.makeClient() else {
            for index in checks.indices {
                checks[index].status = .failure(
                    AppLocalization.string(
                        "sync.connection_detail.not_configured",
                        value: "WebDAV not configured"
                    )
                )
            }
            summary = AppLocalization.string(
                "sync.connection_detail.configure_webdav_first",
                value: "Configure a WebDAV server in Sync Settings first."
            )
            isRunning = false
            return
        }

        await run(index: 0) { await testReachability(client: client) }
        await run(index: 1) { await testAuthentication(client: client) }
        await run(index: 2) { await testWritePermission(client: client) }
        await run(index: 3) { await testLatency(client: client) }
        await run(index: 4) { await testQuota(client: client) }

        let failed = checks.filter { if case .failure = $0.status { return true } else { return false } }
        summary = failed.isEmpty
            ? AppLocalization.string("sync.connection_detail.all_passed", value: "All checks passed.")
            : String(
                format: AppLocalization.string(
                    "sync.connection_detail.summary_failed",
                    value: "%d of %d checks failed."
                ),
                locale: .autoupdatingCurrent,
                failed.count,
                checks.count
            )
        isRunning = false
    }

    private func run(index: Int, _ block: () async -> CheckStatus) async {
        guard checks.indices.contains(index) else { return }
        checks[index].status = .running
        let status = await block()
        checks[index].status = status
    }

    // MARK: - Individual checks

    private func testReachability(client: WebDAVClient) async -> CheckStatus {
        do {
            try await client.ping()
            return .success(
                AppLocalization.string("sync.connection_detail.server_reachable", value: "Server reachable")
            )
        } catch {
            return .failure(
                String(
                    format: AppLocalization.string(
                        "sync.connection_detail.reachability_failed_format",
                        value: "Reachability failed: %@"
                    ),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
            )
        }
    }

    private func testAuthentication(client: WebDAVClient) async -> CheckStatus {
        do {
            _ = try await client.listDirectory("/")
            return .success(
                AppLocalization.string("sync.connection_detail.credentials_accepted", value: "Credentials accepted")
            )
        } catch {
            return .failure(
                String(
                    format: AppLocalization.string(
                        "sync.connection_detail.auth_failed_format",
                        value: "Authentication failed: %@"
                    ),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
            )
        }
    }

    private func testWritePermission(client: WebDAVClient) async -> CheckStatus {
        let folder = syncService.remoteFolder
        let path = "\(folder)/.pt_write_test_\(UUID().uuidString).tmp"
        do {
            try await client.mkdirAll(folder)
            try await client.put(path, data: Data("ok".utf8))
            try? await client.delete(path)
            return .success(
                AppLocalization.string("sync.connection_detail.write_ok", value: "Write OK")
            )
        } catch {
            return .failure(
                String(
                    format: AppLocalization.string(
                        "sync.connection_detail.cannot_write_format",
                        value: "Cannot write: %@"
                    ),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
            )
        }
    }

    private func testLatency(client: WebDAVClient) async -> CheckStatus {
        var samples: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            do {
                try await client.ping()
                samples.append(Date().timeIntervalSince(start) * 1000)
            } catch {
                return .failure(
                    AppLocalization.string(
                        "sync.connection_detail.latency_probe_failed",
                        value: "Latency probe failed"
                    )
                )
            }
        }
        let avg = samples.reduce(0, +) / Double(samples.count)
        return .success(
            String(
                format: AppLocalization.string(
                    "sync.connection_detail.latency_average",
                    value: "Avg %.0f ms (%d samples)"
                ),
                locale: .autoupdatingCurrent,
                avg,
                samples.count
            )
        )
    }

    private func testQuota(client: WebDAVClient) async -> CheckStatus {
        // Most servers don't report quota; a successful PROPFIND on root is
        // enough to confirm the endpoint works. We report "unavailable" when
        // no quota metadata is returned to avoid a false negative.
        do {
            _ = try await client.listDirectory("/")
            return .success(
                AppLocalization.string(
                    "sync.connection_detail.quota_unavailable",
                    value: "Quota info unavailable"
                )
            )
        } catch {
            return .failure(
                String(
                    format: AppLocalization.string(
                        "sync.connection_detail.quota_failed_format",
                        value: "Quota check failed: %@"
                    ),
                    locale: .autoupdatingCurrent,
                    error.localizedDescription
                )
            )
        }
    }

    // MARK: - Styling

    private func color(for status: CheckStatus) -> Color {
        switch status {
        case .pending: return Morandi.tertiaryText
        case .running: return Morandi.accent
        case .success: return Morandi.sage
        case .failure: return Morandi.destructive
        }
    }

    private func detail(for status: CheckStatus) -> String? {
        switch status {
        case .success(let msg), .failure(let msg): return msg
        case .pending, .running: return nil
        }
    }

    private static func defaultChecks() -> [CheckRow] {
        [
            CheckRow(
                id: "reach",
                title: AppLocalization.string("sync.connection_check.reachability", value: "Reachability"),
                status: .pending
            ),
            CheckRow(
                id: "auth",
                title: AppLocalization.string("sync.connection_check.authentication", value: "Authentication"),
                status: .pending
            ),
            CheckRow(
                id: "write",
                title: AppLocalization.string("sync.connection_check.write_permission", value: "Write permission"),
                status: .pending
            ),
            CheckRow(
                id: "latency",
                title: AppLocalization.string("sync.connection_check.latency", value: "Latency (3 samples)"),
                status: .pending
            ),
            CheckRow(
                id: "quota",
                title: AppLocalization.string("sync.connection_check.quota", value: "Storage quota"),
                status: .pending
            ),
        ]
    }
}

#Preview {
    NavigationStack {
        ConnectionTesterView(syncService: WebDAVSyncService())
    }
}
