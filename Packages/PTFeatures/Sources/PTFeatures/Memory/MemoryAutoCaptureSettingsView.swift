import SwiftUI
import PTUI

public struct MemoryAutoCaptureSettingsView: View {
    @AppStorage("memory.auto_capture.ai_chat") private var aiChatEnabled: Bool = true
    @AppStorage("memory.auto_capture.reader_highlights") private var readerHighlightsEnabled: Bool = true
    @AppStorage("memory.auto_capture.reader_notes") private var readerNotesEnabled: Bool = true
    @AppStorage("memory.auto_capture.confidence_threshold") private var confidenceThreshold: Double = 0.5

    public init() {}

    public var body: some View {
        Form {
            Section {
                Toggle("memory.auto_capture.ai_chat", isOn: $aiChatEnabled)
                Toggle("memory.auto_capture.reader_highlights", isOn: $readerHighlightsEnabled)
                Toggle("memory.auto_capture.reader_notes", isOn: $readerNotesEnabled)
            } header: {
                Text("memory.auto_capture.sources")
            }

            Section {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Text("memory.auto_capture.confidence_threshold")
                        Spacer()
                        Text(String(format: "%.0f%%", confidenceThreshold * 100))
                            .font(AppTypography.caption)
                            .foregroundStyle(Morandi.secondaryText)
                    }
                    Slider(value: $confidenceThreshold, in: 0...1, step: 0.05)
                        .tint(Morandi.accent)
                }
            } header: {
                Text("memory.auto_capture.threshold_section")
            } footer: {
                Text("memory.auto_capture.threshold_description")
            }
        }
        .navigationTitle(String(localized: "memory.auto_capture.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
