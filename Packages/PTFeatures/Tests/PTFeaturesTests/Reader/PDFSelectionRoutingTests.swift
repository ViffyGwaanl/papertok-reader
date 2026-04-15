import Testing
@testable import PTFeatures
import PTReader

@Suite("PDFSelectionRouting")
struct PDFSelectionRoutingTests {
    @Test("raw PDF text selection keeps AI/context-menu state but does not auto-create an annotation draft")
    func rawSelectionDoesNotCreateAnnotationDraft() {
        let selection = PDFSelectionSnapshot(
            selectedText: "Diffusion models improve progressively.",
            anchorString: #"{"kind":"selection"}"#,
            pageLabel: "Page 12"
        )

        let routing = PDFSelectionRouting.from(selection: selection)

        #expect(routing.aiQuickActionText == "Diffusion models improve progressively.")
        #expect(routing.aiQuickActionChapter == "Page 12")
        #expect(routing.contextMenuText == "Diffusion models improve progressively.")
        #expect(routing.contextMenuLocator == #"{"kind":"selection"}"#)
        #expect(routing.contextMenuChapter == "Page 12")
        #expect(routing.shouldCreateAnnotationDraft == false)
    }
}
