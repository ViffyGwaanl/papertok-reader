import SwiftUI
import PTUI

/// W6.2 — Lightweight in-chat model picker.
///
/// Wave 5.3 consolidated full provider configuration into Settings → AI
/// Provider Center and removed the legacy `ProviderPickerSheet`. Users still
/// need a fast way to flip models mid-conversation without leaving the chat.
/// Flutter main ships a medium-detent bottom sheet that lists the current
/// provider's cached model ids + a custom text field. This is the SwiftUI
/// equivalent.
///
/// The sheet is intentionally dumb — it owns only the custom text field
/// state. Hosts pass the selection callbacks; persistence lives on
/// `AIChatViewModel.setModelForCurrentProvider(_:)` which writes the
/// provider-scoped UserDefaults key and posts
/// `StoredAIProviderCatalog.configurationDidChangeNotification` so the
/// send-time resolver picks up the change on the very next message.
@MainActor
public struct InChatModelPickerSheet: View {
    public let currentProviderId: String
    public let currentProviderName: String
    public let currentModelId: String
    public let availableModels: [String]
    public let onSelect: (String) -> Void
    public let onCustomSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var customText: String = ""

    public init(
        currentProviderId: String,
        currentProviderName: String,
        currentModelId: String,
        availableModels: [String],
        onSelect: @escaping (String) -> Void,
        onCustomSubmit: @escaping (String) -> Void
    ) {
        self.currentProviderId = currentProviderId
        self.currentProviderName = currentProviderName
        self.currentModelId = currentModelId
        self.availableModels = availableModels
        self.onSelect = onSelect
        self.onCustomSubmit = onCustomSubmit
    }

    // MARK: - Pure helpers (easy to unit-test without exercising SwiftUI)

    /// Exposed for tests and direct in-process invocation — selecting a row
    /// forwards the id and dismisses the sheet.
    public func selectModel(_ modelId: String) {
        onSelect(modelId)
        dismiss()
    }

    /// Submit the custom text field. Trims whitespace/newlines; no-op when
    /// the resulting string is empty so we never persist a blank id.
    public func submitCustom(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        onCustomSubmit(trimmed)
        dismiss()
    }

    /// Static helper used by the "Apply" button to decide whether the
    /// current custom text is submittable.
    public static func canApply(customText: String) -> Bool {
        customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(currentProviderName)
                            .font(AppTypography.callout)
                            .foregroundStyle(Morandi.secondaryText)
                    } label: {
                        Text("chat.input.model_picker.current_provider")
                            .font(AppTypography.callout)
                            .foregroundStyle(Morandi.primaryText)
                    }
                }

                Section {
                    ForEach(availableModels, id: \.self) { modelId in
                        Button {
                            selectModel(modelId)
                        } label: {
                            HStack {
                                Text(modelId)
                                    .font(AppTypography.body)
                                    .foregroundStyle(Morandi.primaryText)
                                Spacer()
                                if modelId == currentModelId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Morandi.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("chat.input.model_picker.available_models")
                }

                Section {
                    customField

                    Button {
                        submitCustom(customText)
                    } label: {
                        Text("chat.input.model_picker.apply")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(Self.canApply(customText: customText) == false)
                } header: {
                    Text("chat.input.model_picker.custom_model")
                }
            }
            .navigationTitle(Text("chat.input.model_picker.title"))

            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("common.cancel")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// `.textInputAutocapitalization` is iOS-only; macOS plain TextFields have
    /// no capitalization modifier, so we gate the modifier with a platform
    /// check and keep the rest of the field configuration identical.
    @ViewBuilder
    private var customField: some View {
        #if os(iOS)
        TextField(
            "chat.input.model_picker.custom_model.placeholder",
            text: $customText
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled(true)
        .onSubmit {
            submitCustom(customText)
        }
        #else
        TextField(
            "chat.input.model_picker.custom_model.placeholder",
            text: $customText
        )
        .autocorrectionDisabled(true)
        .onSubmit {
            submitCustom(customText)
        }
        #endif
    }
}
