#if canImport(UIKit)
import Foundation
import PDFKit
import Testing
import UIKit
@testable import PTFeatures

@MainActor
@Suite("PDFThemedPageOverlayProvider")
struct PDFThemedPageOverlayProviderTests {
    private func makePage() -> PDFPage {
        PDFPage()
    }

    @Test("tint kind .none returns nil overlay")
    func tintKindNoneReturnsNilOverlay() throws {
        guard #available(iOS 16.0, *) else { return }
        let provider = PDFThemedPageOverlayProvider()
        provider.tintKind = .none
        let pdfView = PDFView()
        let page = makePage()
        #expect(provider.pdfView(pdfView, overlayViewFor: page) == nil)
    }

    @Test("tint kind .dark returns non-nil overlay")
    func tintKindInvertReturnsOverlay() throws {
        guard #available(iOS 16.0, *) else { return }
        let provider = PDFThemedPageOverlayProvider()
        provider.tintKind = .dark
        let pdfView = PDFView()
        let page = makePage()
        let overlay = provider.pdfView(pdfView, overlayViewFor: page)
        #expect(overlay != nil)
        #expect(overlay is PDFThemedPageOverlayView)
    }

    @Test("updating tint kind refreshes active overlays")
    func updatingTintKindRefreshesActiveOverlays() throws {
        guard #available(iOS 16.0, *) else { return }
        let provider = PDFThemedPageOverlayProvider()
        provider.tintKind = .dark
        let pdfView = PDFView()
        let page = makePage()
        let overlay = provider.pdfView(pdfView, overlayViewFor: page) as? PDFThemedPageOverlayView
        #expect(overlay?.tintKind == .dark)
        provider.tintKind = .sepia
        #expect(overlay?.tintKind == .sepia)
    }

    @Test("ending display removes overlay from tracking")
    func endingDisplayRemovesOverlayFromTracking() throws {
        guard #available(iOS 16.0, *) else { return }
        let provider = PDFThemedPageOverlayProvider()
        provider.tintKind = .dark
        let pdfView = PDFView()
        let page = makePage()
        let overlay = provider.pdfView(pdfView, overlayViewFor: page)
        #expect(provider.activeOverlayCount == 1)
        if let overlay {
            provider.pdfView(pdfView, willEndDisplayingOverlayView: overlay, for: page)
        }
        #expect(provider.activeOverlayCount == 0)
    }
}
#endif
