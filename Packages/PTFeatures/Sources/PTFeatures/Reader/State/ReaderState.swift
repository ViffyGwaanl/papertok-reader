import Foundation

/// High-level state of a reader host (EPUB or PDF). Consumed by
/// `ReaderStateScreen` to render loading, empty, permission, error,
/// and recovery UI without a blank canvas.
public enum ReaderState: Sendable, Equatable {
    case idle
    case loading(progress: Double?)
    case empty(reason: ReaderEmptyReason)
    case permissionDenied(detail: String?)
    case failed(error: ReaderRenderError)
    case ready
}

public enum ReaderEmptyReason: Sendable, Equatable {
    case noPages
    case unsupportedFormat(String)
    case zeroLengthDocument
}

public struct ReaderRenderError: Error, Sendable, Equatable {
    public let kind: Kind
    public let underlyingMessage: String?
    public let isRecoverable: Bool

    public enum Kind: Sendable, Equatable {
        case openFailed
        case parsingFailed
        case missingResource
        case fileSystemError
        case unknown
    }

    public init(kind: Kind, underlyingMessage: String? = nil, isRecoverable: Bool = true) {
        self.kind = kind
        self.underlyingMessage = underlyingMessage
        self.isRecoverable = isRecoverable
    }
}

extension ReaderRenderError.Kind {
    /// Localization key for the user-facing description of this error kind.
    public var localizationKey: String {
        switch self {
        case .openFailed: return "reader.state.error.kind.open_failed"
        case .parsingFailed: return "reader.state.error.kind.parsing_failed"
        case .missingResource: return "reader.state.error.kind.missing_resource"
        case .fileSystemError: return "reader.state.error.kind.file_system_error"
        case .unknown: return "reader.state.error.kind.unknown"
        }
    }
}

extension ReaderState {
    /// Convenience: caller should not present a screen at all when ready.
    public var shouldPresentStateScreen: Bool {
        if case .ready = self { return false }
        return true
    }
}
