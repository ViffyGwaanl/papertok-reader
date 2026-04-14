import SwiftUI
import PTFeatures

/// Shows migration progress when user upgrades from the Flutter version of PaperTok Reader.
/// Presented as a sheet on first launch when a Flutter database is detected.
struct MigrationProgressView: View {
    @State private var migrationService = FlutterMigrationService()
    let database: AppDatabase
    @Environment(\.dismiss) private var dismiss

    private var statusText: String {
        migrationService.statusMessage.isEmpty
            ? String(localized: "migration.status.preparing")
            : migrationService.statusMessage
    }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Morandi.accent)

            Text("migration.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Morandi.primaryText)

            Text("migration.description")
                .font(.subheadline)
                .foregroundStyle(Morandi.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            ProgressView(value: migrationService.progress)
                .padding(.horizontal, 32)
                .tint(Morandi.accent)
                .animation(.easeInOut, value: migrationService.progress)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(Morandi.secondaryText)

            Text("migration.warning.api_keys_not_migrated")
                .font(.caption2)
                .foregroundStyle(Morandi.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let error = migrationService.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Morandi.destructive)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            HStack(spacing: 16) {
                if migrationService.isComplete {
                    Button("common.done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Morandi.accent)
                } else if migrationService.errorMessage != nil {
                    Button("common.skip") {
                        migrationService.skipMigration()
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("common.retry") {
                        migrationService.errorMessage = nil
                        Task {
                            await migrationService.migrate(into: database)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Morandi.accent)
                } else {
                    Button("migration.button.skip_migration") {
                        migrationService.skipMigration()
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .padding(32)
        .interactiveDismissDisabled(!migrationService.isComplete)
        .task {
            if await migrationService.isMigrationAvailable() {
                await migrationService.migrate(into: database)
            } else {
                dismiss()
            }
        }
    }
}
