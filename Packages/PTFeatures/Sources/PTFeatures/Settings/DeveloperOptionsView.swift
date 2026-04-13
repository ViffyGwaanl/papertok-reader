import SwiftUI
import PTCore
import PTUI
#if canImport(UIKit)
import UIKit
#endif

/// Developer-facing debug toggles, diagnostic export, and build info.
/// Hidden by default; revealed via a 5-tap gesture on the About → Version row.
public struct DeveloperOptionsView: View {
    @State private var viewModel: SettingsViewModel
    @State private var showRecentErrors = false
    @State private var exportMessage: String?

    @MainActor
    public init(viewModel: SettingsViewModel? = nil) {
        _viewModel = State(initialValue: viewModel ?? SettingsViewModel())
    }

    public var body: some View {
        Form {
            togglesSection
            diagnosticsSection
            buildInfoSection
        }
        .scrollContentBackground(.hidden)
        .background(Morandi.background)
        .navigationTitle(String(localized: "settings.developer"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showRecentErrors) {
            recentErrorsSheet
        }
        .onChange(of: viewModel.verboseLogging) { _, _ in viewModel.save() }
        .onChange(of: viewModel.networkRequestLogging) { _, _ in viewModel.save() }
        .onChange(of: viewModel.slowAnimations) { _, _ in viewModel.save() }
        .onChange(of: viewModel.showDebugOverlay) { _, _ in viewModel.save() }
    }

    // MARK: - Toggles

    private var togglesSection: some View {
        Section(String(localized: "common.diagnostics")) {
            Toggle("settings.developer.verbose_logging", isOn: $viewModel.verboseLogging)
                .tint(Morandi.accent)
            Toggle("settings.developer.network_logging", isOn: $viewModel.networkRequestLogging)
                .tint(Morandi.accent)
            Toggle("settings.developer.slow_animations", isOn: $viewModel.slowAnimations)
                .tint(Morandi.accent)
            Toggle("settings.developer.debug_overlay", isOn: $viewModel.showDebugOverlay)
                .tint(Morandi.accent)
        }
    }

    // MARK: - Diagnostic actions

    private var diagnosticsSection: some View {
        Section(String(localized: "ai.tools")) {
            Button {
                exportDiagnosticReport()
            } label: {
                Label(String(localized: "settings.export_diagnostics"), systemImage: "square.and.arrow.up.on.square")
                    .foregroundStyle(Morandi.accent)
            }

            Button {
                showRecentErrors = true
            } label: {
                Label(String(localized: "settings.view_recent_errors"), systemImage: "exclamationmark.bubble")
                    .foregroundStyle(Morandi.accent)
            }

            if let message = exportMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Morandi.sage)
                    Text(message)
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.sage)
                }
            }
        }
    }

    // MARK: - Build info

    private var buildInfoSection: some View {
        Section(String(localized: "common.build_info")) {
            infoRow(String(localized: "common.version"), Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
            infoRow(String(localized: "common.build"), Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
            infoRow(String(localized: "common.commit"), commitHash)
            infoRow(String(localized: "common.device"), deviceDescription)
            infoRow(String(localized: "common.operating_system"), osDescription)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Morandi.primaryText)
            Spacer()
            Text(value)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Recent errors sheet

    private var recentErrorsSheet: some View {
        NavigationStack {
            List {
                Section(String(localized: "settings.errors")) {
                    if DeveloperLogBuffer.shared.recent.isEmpty {
                        Text("notes.no_recent_errors")
                            .foregroundStyle(Morandi.secondaryText)
                    } else {
                        ForEach(DeveloperLogBuffer.shared.recent, id: \.self) { entry in
                            Text(entry)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(Morandi.primaryText)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "settings.recent_errors"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) { showRecentErrors = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func exportDiagnosticReport() {
        let report: [String: Any] = [
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "device": deviceDescription,
            "os": osDescription,
            "verboseLogging": viewModel.verboseLogging,
            "networkRequestLogging": viewModel.networkRequestLogging,
            "slowAnimations": viewModel.slowAnimations,
            "showDebugOverlay": viewModel.showDebugOverlay,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted) {
            let url = AppConfig.appGroupContainerURL()
                .appendingPathComponent("diagnostic_report.json")
            try? data.write(to: url)
            exportMessage = String(localized: "settings.developer.export_report_success")
        } else {
            exportMessage = String(localized: "settings.developer.export_report_failed")
        }
    }

    // MARK: - Device info

    private var commitHash: String {
        Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? String(localized: "common.unknown")
    }

    private var deviceDescription: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.model) (\(UIDevice.current.name))"
        #else
        return "macOS"
        #endif
    }

    private var osDescription: String {
        #if canImport(UIKit)
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }
}

/// In-memory ring buffer of recent errors/logs, surfaced by DeveloperOptionsView.
public final class DeveloperLogBuffer: @unchecked Sendable {
    public static let shared = DeveloperLogBuffer()
    private let lock = NSLock()
    private var buffer: [String] = []
    private let capacity = 100

    public func append(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(message)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
    }

    public var recent: [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}
