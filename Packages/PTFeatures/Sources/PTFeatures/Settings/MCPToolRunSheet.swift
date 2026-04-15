import SwiftUI
import PTCore
import PTUI

struct MCPToolRunSheet: View {
    let toolName: String
    let onRun: (String) async -> Void
    let result: String?
    let errorMessage: String?

    @State private var argumentsJSON: String
    @State private var isRunning: Bool = false
    @Environment(\.dismiss) private var dismiss

    init(
        toolName: String,
        initialArgs: String = "{}",
        result: String?,
        errorMessage: String?,
        onRun: @escaping (String) async -> Void
    ) {
        self.toolName = toolName
        self._argumentsJSON = State(initialValue: initialArgs)
        self.result = result
        self.errorMessage = errorMessage
        self.onRun = onRun
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "settings.mcp.tools.run_sheet.arguments")) {
                    TextEditor(text: $argumentsJSON)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                }

                Section {
                    Button {
                        Task {
                            isRunning = true
                            await onRun(argumentsJSON)
                            isRunning = false
                        }
                    } label: {
                        if isRunning {
                            ProgressView()
                        } else {
                            Text("settings.mcp.tools.run_sheet.run_button")
                        }
                    }
                    .disabled(isRunning)
                }

                if let result {
                    Section(String(localized: "settings.mcp.tools.run_sheet.result")) {
                        ScrollView {
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 80, maxHeight: 240)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.destructive)
                    }
                }
            }
            .navigationTitle(
                AppLocalization.format(
                    "settings.mcp.tools.run_sheet.title_format",
                    locale: .autoupdatingCurrent,
                    toolName
                )
            )
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close")) { dismiss() }
                }
            }
        }
    }
}
