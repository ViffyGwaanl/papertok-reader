import Foundation
import Testing
@testable import PTFeatures
import PTCore
import PTReader

@Suite("PDFThemeTint")
struct PDFThemeTintTests {
    @Test("Light theme resolves to no tint")
    func lightResolvesToNone() {
        #expect(PDFThemeTint.resolveTintKind(from: .defaultLight) == .none)
        #expect(PDFThemeTint.filterChain(for: .none).isEmpty)
    }

    @Test("Dark theme resolves to invert + softening matrix")
    func darkResolvesToInvertChain() {
        #expect(PDFThemeTint.resolveTintKind(from: .defaultDark) == .dark)
        let chain = PDFThemeTint.filterChain(for: .dark)
        #expect(chain.map(\.name) == ["CIColorInvert", "CIColorMatrix"])
        let matrix = chain[1].parameters
        #expect(matrix["rVector.x"] == 0.85)
        #expect(matrix["gVector.y"] == 0.85)
        #expect(matrix["bVector.z"] == 0.85)
    }

    @Test("Sepia theme resolves to CISepiaTone at 0.7 intensity")
    func sepiaResolvesToSepiaTone() {
        #expect(PDFThemeTint.resolveTintKind(from: .defaultSepia) == .sepia)
        let chain = PDFThemeTint.filterChain(for: .sepia)
        #expect(chain.count == 1)
        #expect(chain[0].name == "CISepiaTone")
        #expect(chain[0].parameters["inputIntensity"] == 0.7)
    }

    @Test("Custom (unknown) theme falls back to no tint so we never misapply filters")
    func customThemeFallsBackToNone() {
        var custom = ReadTheme.defaultLight
        custom.backgroundColor = "FF112233"
        custom.textColor = "FFFFFFFF"
        #expect(PDFThemeTint.resolveTintKind(from: custom) == .none)
    }

    @Test("Switching theme produces a different filter chain")
    func switchingThemeProducesDifferentChain() {
        let lightChain = PDFThemeTint.filterChain(
            for: PDFThemeTint.resolveTintKind(from: .defaultLight)
        )
        let darkChain = PDFThemeTint.filterChain(
            for: PDFThemeTint.resolveTintKind(from: .defaultDark)
        )
        let sepiaChain = PDFThemeTint.filterChain(
            for: PDFThemeTint.resolveTintKind(from: .defaultSepia)
        )
        #expect(lightChain != darkChain)
        #expect(darkChain != sepiaChain)
        #expect(lightChain != sepiaChain)
    }
}
