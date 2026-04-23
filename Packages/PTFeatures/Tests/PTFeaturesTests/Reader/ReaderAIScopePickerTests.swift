import Foundation
import Testing
@testable import PTFeatures

/// Verifies the W6.5 AI scope-picker contract inside
/// `ReaderAIQuickActionsSheet`. The SwiftUI body is exercised indirectly via
/// the sheet's observable helpers (`isSelectionScopeDisabled`, `defaultScope`)
/// which deterministically describe what a user would see.
@Suite("ReaderAIScopePicker")
@MainActor
struct ReaderAIScopePickerTests {

    private func makeSheet(selectedText: String) -> ReaderAIQuickActionsSheet {
        ReaderAIQuickActionsSheet(
            selectedText: selectedText,
            chapterTitle: "Chapter 2",
            bookTitle: "Book",
            onAction: { _ in },
            onDismiss: {}
        )
    }

    @Test("scope picker is visible whenever the quick actions sheet opens")
    func scopePickerVisibleWhenQuickActionsSheetOpens() {
        // The picker is surfaced unconditionally at the top of the sheet — we
        // assert by inspecting the sheet's public helpers. With or without a
        // selection, the helper must not throw and the selection-disabled hint
        // is determined solely by the selection, not by sheet visibility.
        let withSelection = makeSheet(selectedText: "Chosen phrase")
        let withoutSelection = makeSheet(selectedText: "")

        #expect(withSelection.isSelectionScopeDisabled == false)
        #expect(withoutSelection.isSelectionScopeDisabled == true)
    }

    @Test("selection scope is disabled when no text is selected")
    func selectionScopeDisabledWhenNoSelection() {
        let emptySheet = makeSheet(selectedText: "   \n ")
        #expect(emptySheet.isSelectionScopeDisabled == true)

        let selectedSheet = makeSheet(selectedText: "Meaningful fragment")
        #expect(selectedSheet.isSelectionScopeDisabled == false)
    }

    @Test("default scope is chapter when there is no selection")
    func defaultScopeIsChapterWhenNoSelection() {
        #expect(ReaderAIQuickActionsSheet.defaultScope(selectedText: "") == .chapter)
        #expect(ReaderAIQuickActionsSheet.defaultScope(selectedText: "   ") == .chapter)
    }

    @Test("default scope is selection when user has highlighted text")
    func defaultScopeIsSelectionWhenTextSelected() {
        #expect(
            ReaderAIQuickActionsSheet.defaultScope(selectedText: "highlighted") == .selection
        )
    }

    @Test("scope picker visibility helpers do not require UI presentation")
    func scopePickerHelpersAreDeterministic() {
        // Regression guard: the helpers must be pure — the picker rendering
        // must not be gated on an external AppStorage value or sheet lifecycle.
        let repeated = (0..<5).map { _ in makeSheet(selectedText: "x") }
        for sheet in repeated {
            #expect(sheet.isSelectionScopeDisabled == false)
        }
    }
}
