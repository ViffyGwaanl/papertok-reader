import CoreImage
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

/// A parameter value for a `PDFThemeTintFilter`. The cases mirror the
/// concrete Core Image input shapes: a plain scalar gets wrapped in an
/// `NSNumber` at apply-time, while `.vector` carries a 4-component
/// `CIVector` already assembled so `CIFilter.setValue(_:forKey:)` can
/// accept the value directly. This representation exists so the descriptor
/// is self-contained: no dotted scalar keys leak out of `PDFThemeTint`.
public enum PDFThemeTintParameter: Sendable, Equatable {
    case scalar(Double)
    case vector(x: Double, y: Double, z: Double, w: Double)

    /// Returns a value suitable for `CIFilter.setValue(_:forKey:)`.
    public var ciFilterValue: Any {
        switch self {
        case .scalar(let value):
            return NSNumber(value: value)
        case .vector(let x, let y, let z, let w):
            return CIVector(x: CGFloat(x), y: CGFloat(y), z: CGFloat(z), w: CGFloat(w))
        }
    }
}

/// A logic-only description of a Core Image filter, used for test-driven
/// filter-chain selection. Every parameter key is the exact Core Image
/// input key (`inputIntensity`, `inputRVector`, ...); parameter values are
/// pre-bundled into scalars or `CIVector`s so consumers can pass them
/// straight to `CIFilter.setValue(_:forKey:)` with no translation.
public struct PDFThemeTintFilter: Sendable, Equatable {
    public let name: String
    public let parameters: [String: PDFThemeTintParameter]

    public init(name: String, parameters: [String: PDFThemeTintParameter] = [:]) {
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
                        "inputRVector": .vector(x: 0.85, y: 0, z: 0, w: 0),
                        "inputGVector": .vector(x: 0, y: 0.85, z: 0, w: 0),
                        "inputBVector": .vector(x: 0, y: 0, z: 0.85, w: 0),
                        "inputAVector": .vector(x: 0, y: 0, z: 0, w: 1.0),
                    ]
                ),
            ]
        case .sepia:
            return [
                PDFThemeTintFilter(
                    name: "CISepiaTone",
                    parameters: ["inputIntensity": .scalar(0.7)]
                )
            ]
        }
    }
}
