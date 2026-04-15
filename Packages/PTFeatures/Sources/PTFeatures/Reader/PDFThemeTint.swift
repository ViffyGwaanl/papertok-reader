import Foundation
import PTCore

/// The kind of tint to apply to PDF page rasters, derived from the active
/// reader theme. The PDF coordinator selects a corresponding Core Image
/// filter chain for this kind. `.none` means the raw page raster is shown
/// without any filtering.
public enum PDFThemeTintKind: String, Sendable, Equatable, CaseIterable {
    case none
    case dark
    case sepia
}

/// A logic-only description of a Core Image filter, used for test-driven
/// filter-chain selection. The PDF coordinator is responsible for
/// translating this descriptor into an actual `CIFilter` instance at
/// render time.
public struct PDFThemeTintFilter: Sendable, Equatable {
    public let name: String
    public let parameters: [String: Double]

    public init(name: String, parameters: [String: Double] = [:]) {
        self.name = name
        self.parameters = parameters
    }
}

public enum PDFThemeTint {
    /// Resolve the tint kind for a given `ReadTheme`. Built-in themes are
    /// matched by equality against the documented presets; any other theme
    /// (including user-customised variants) falls back to `.none` so we
    /// never apply unintended color transforms.
    public static func resolveTintKind(from theme: ReadTheme) -> PDFThemeTintKind {
        if theme == .defaultLight {
            return .none
        }
        if theme == .defaultDark {
            return .dark
        }
        if theme == .defaultSepia {
            return .sepia
        }
        return .none
    }

    /// Returns the ordered Core Image filter chain for the given tint kind.
    /// The order matters: the PDF coordinator applies each filter in turn.
    ///
    /// Chosen strategy:
    /// - `.dark` inverts colors (`CIColorInvert`) and then softens the
    ///   inversion via a `CIColorMatrix` with per-channel coefficients so
    ///   pure-white pages become a muted dark grey rather than solid black,
    ///   keeping syntax colours readable.
    /// - `.sepia` uses `CISepiaTone` at intensity 0.7.
    /// - `.none` is an empty chain.
    public static func filterChain(for kind: PDFThemeTintKind) -> [PDFThemeTintFilter] {
        switch kind {
        case .none:
            return []
        case .dark:
            return [
                PDFThemeTintFilter(name: "CIColorInvert"),
                PDFThemeTintFilter(
                    name: "CIColorMatrix",
                    parameters: [
                        "rVector.x": 0.85,
                        "gVector.y": 0.85,
                        "bVector.z": 0.85,
                        "aVector.w": 1.0,
                    ]
                ),
            ]
        case .sepia:
            return [
                PDFThemeTintFilter(
                    name: "CISepiaTone",
                    parameters: ["inputIntensity": 0.7]
                )
            ]
        }
    }
}
