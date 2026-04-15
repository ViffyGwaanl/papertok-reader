import CoreImage
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
        #expect(matrix["inputRVector"] == .vector(x: 0.85, y: 0, z: 0, w: 0))
        #expect(matrix["inputGVector"] == .vector(x: 0, y: 0.85, z: 0, w: 0))
        #expect(matrix["inputBVector"] == .vector(x: 0, y: 0, z: 0.85, w: 0))
        #expect(matrix["inputAVector"] == .vector(x: 0, y: 0, z: 0, w: 1.0))
    }

    @Test("Sepia theme resolves to CISepiaTone at 0.7 intensity")
    func sepiaResolvesToSepiaTone() {
        #expect(PDFThemeTint.resolveTintKind(from: .defaultSepia) == .sepia)
        let chain = PDFThemeTint.filterChain(for: .sepia)
        #expect(chain.count == 1)
        #expect(chain[0].name == "CISepiaTone")
        #expect(chain[0].parameters["inputIntensity"] == .scalar(0.7))
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

    @Test("Light chain has no parameters or dotted keys")
    func lightChainHasNoParameters() {
        let chain = PDFThemeTint.filterChain(for: .none)
        #expect(chain.isEmpty)
        for descriptor in chain {
            for key in descriptor.parameters.keys {
                #expect(!key.contains("."))
            }
        }
    }

    @Test("Dark chain parameters are CIVector-ready, not scalar dotted keys")
    func darkChainParametersAreCIVectorReady() {
        let chain = PDFThemeTint.filterChain(for: .dark)
        for descriptor in chain {
            for (key, parameter) in descriptor.parameters {
                #expect(!key.contains("."))
                if key.lowercased().contains("vector") {
                    if case .vector = parameter {
                        // ok
                    } else {
                        Issue.record("Vector-shaped key \(key) must be a .vector parameter")
                    }
                    #expect(parameter.ciFilterValue is CIVector)
                }
            }
        }
    }

    @Test("Every chain parameter applies to its CIFilter without crashing and produces output")
    func parametersApplyToCIFilterWithoutCrash() {
        let sampleImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        for kind in PDFThemeTintKind.allCases {
            let chain = PDFThemeTint.filterChain(for: kind)
            for descriptor in chain {
                guard let filter = CIFilter(name: descriptor.name) else {
                    Issue.record("Unknown CIFilter name: \(descriptor.name)")
                    continue
                }
                filter.setValue(sampleImage, forKey: kCIInputImageKey)
                for (key, parameter) in descriptor.parameters {
                    filter.setValue(parameter.ciFilterValue, forKey: key)
                }
                #expect(filter.outputImage != nil, "\(descriptor.name) produced no output image")
            }
        }
    }
}
