import Testing
import Foundation
@testable import PTFeatures

/// W6.2 — Lightweight in-chat model picker sheet. Verifies the sheet's
/// public API shape (no SwiftUI view-graph introspection) exposes the
/// pieces hosts need to wire behaviour: the list it presents, the callbacks
/// it invokes when the user selects a preset or submits a custom model id,
/// and the empty-field guard that disables the "Apply" button.
@Suite("InChatModelPickerSheet (W6.2)")
struct InChatModelPickerSheetTests {
    final class SelectionSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [String] = []

        func record(_ value: String) {
            lock.lock(); defer { lock.unlock() }
            _values.append(value)
        }

        var values: [String] {
            lock.lock(); defer { lock.unlock() }
            return _values
        }
    }

    @MainActor
    @Test("presentsCurrentProviderName exposes the configured provider label")
    func presentsCurrentProviderName() {
        let sheet = InChatModelPickerSheet(
            currentProviderId: "alpha",
            currentProviderName: "Alpha",
            currentModelId: "alpha-1",
            availableModels: ["alpha-1", "alpha-2"],
            onSelect: { _ in },
            onCustomSubmit: { _ in }
        )

        #expect(sheet.currentProviderName == "Alpha")
        #expect(sheet.availableModels == ["alpha-1", "alpha-2"])
        #expect(sheet.currentModelId == "alpha-1")
    }

    @MainActor
    @Test("selectingModelFiresOnSelectClosure forwards the chosen id")
    func selectingModelFiresOnSelectClosure() {
        let spy = SelectionSpy()
        let sheet = InChatModelPickerSheet(
            currentProviderId: "alpha",
            currentProviderName: "Alpha",
            currentModelId: "alpha-1",
            availableModels: ["alpha-1", "alpha-2", "alpha-3"],
            onSelect: { spy.record($0) },
            onCustomSubmit: { _ in }
        )

        sheet.selectModel("alpha-2")
        sheet.selectModel("alpha-3")

        #expect(spy.values == ["alpha-2", "alpha-3"])
    }

    @MainActor
    @Test("customModelSubmitFiresOnCustomSubmit forwards trimmed text")
    func customModelSubmitFiresOnCustomSubmit() {
        let spy = SelectionSpy()
        let sheet = InChatModelPickerSheet(
            currentProviderId: "alpha",
            currentProviderName: "Alpha",
            currentModelId: "alpha-1",
            availableModels: ["alpha-1"],
            onSelect: { _ in },
            onCustomSubmit: { spy.record($0) }
        )

        sheet.submitCustom("  my-custom-model  ")

        #expect(spy.values == ["my-custom-model"])
    }

    @MainActor
    @Test("emptyCustomFieldDisablesApplyButton reports canApply false on empty/whitespace")
    func emptyCustomFieldDisablesApplyButton() {
        let sheet = InChatModelPickerSheet(
            currentProviderId: "alpha",
            currentProviderName: "Alpha",
            currentModelId: "alpha-1",
            availableModels: ["alpha-1"],
            onSelect: { _ in },
            onCustomSubmit: { _ in }
        )

        #expect(InChatModelPickerSheet.canApply(customText: "") == false)
        #expect(InChatModelPickerSheet.canApply(customText: "   ") == false)
        #expect(InChatModelPickerSheet.canApply(customText: "\n\t") == false)
        #expect(InChatModelPickerSheet.canApply(customText: "custom-id") == true)
        #expect(InChatModelPickerSheet.canApply(customText: "  custom-id  ") == true)
    }

    @MainActor
    @Test("emptyCustomSubmitDoesNothing when the text is whitespace only")
    func emptyCustomSubmitDoesNothing() {
        let spy = SelectionSpy()
        let sheet = InChatModelPickerSheet(
            currentProviderId: "alpha",
            currentProviderName: "Alpha",
            currentModelId: "alpha-1",
            availableModels: ["alpha-1"],
            onSelect: { _ in },
            onCustomSubmit: { spy.record($0) }
        )

        sheet.submitCustom("   ")
        sheet.submitCustom("")

        #expect(spy.values.isEmpty)
    }

    @Test("localizationKeysResolveToNonEmptyStrings so the sheet renders in every locale")
    func localizationKeysResolveToNonEmptyStrings() {
        let keys: [String] = [
            "chat.input.model_picker.title",
            "chat.input.model_picker.current_provider",
            "chat.input.model_picker.available_models",
            "chat.input.model_picker.custom_model",
            "chat.input.model_picker.custom_model.placeholder",
            "chat.input.model_picker.apply",
        ]
        for key in keys {
            let value = String(localized: String.LocalizationValue(key), bundle: .main)
            #expect(value.isEmpty == false, "\(key) resolved empty")
        }
    }
}
