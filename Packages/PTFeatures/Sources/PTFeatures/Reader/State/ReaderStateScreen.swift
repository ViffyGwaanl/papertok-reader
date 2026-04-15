import SwiftUI
import PTCore
import PTUI

/// Unified loading / empty / permission / error / recovery surface for the
/// EPUB and PDF reader hosts. Pure presentation: all business logic lives in
/// the owning view model or host.
public struct ReaderStateScreen: View {
    public let state: ReaderState
    public let onRetry: (() -> Void)?
    public let onDismiss: (() -> Void)?

    public init(
        state: ReaderState,
        onRetry: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.state = state
        self.onRetry = onRetry
        self.onDismiss = onDismiss
    }

    public var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .idle:
            loadingContent(progress: nil)
        case .loading(let progress):
            loadingContent(progress: progress)
        default:
            cardContent
        }
    }

    @ViewBuilder
    private func loadingContent(progress: Double?) -> some View {
        ZStack {
            Morandi.background.ignoresSafeArea()
            VStack(spacing: AppSpacing.md) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Morandi.accent)
                        .frame(maxWidth: 240)
                } else {
                    ProgressView()
                        .tint(Morandi.accent)
                }
                Text(AppLocalization.string("reader.state.loading_title"))
                    .font(.body)
                    .foregroundStyle(Morandi.secondaryText)
            }
            .padding(AppSpacing.xl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(AppLocalization.string("reader.state.loading_title")))
    }

    @ViewBuilder
    private var cardContent: some View {
        ZStack {
            Morandi.background.ignoresSafeArea()
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: Self.iconName(for: state))
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Self.iconTint(for: state))
                    .accessibilityHidden(true)

                Text(Self.titleText(for: state))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)
                    .multilineTextAlignment(.center)

                Text(Self.bodyText(for: state))
                    .font(.body)
                    .foregroundStyle(Morandi.secondaryText)
                    .multilineTextAlignment(.center)

                HStack(spacing: AppSpacing.md) {
                    if Self.showsRetryButton(for: state), let onRetry {
                        Button {
                            onRetry()
                        } label: {
                            Text(AppLocalization.string("reader.state.retry"))
                                .font(.body.weight(.semibold))
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.sm)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Morandi.accent)
                        .accessibilityLabel(Text(AppLocalization.string("reader.state.retry")))
                    }
                    if let onDismiss {
                        Button {
                            onDismiss()
                        } label: {
                            Text(AppLocalization.string("common.close"))
                                .font(.body)
                                .padding(.horizontal, AppSpacing.lg)
                                .padding(.vertical, AppSpacing.sm)
                        }
                        .buttonStyle(.bordered)
                        .tint(Morandi.secondaryText)
                        .accessibilityLabel(Text(AppLocalization.string("common.close")))
                    }
                }
            }
            .padding(AppSpacing.xl)
            .frame(maxWidth: 480)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))
            .ptShadow(level: 2)
            .padding(AppSpacing.lg)
        }
    }

    // MARK: - Logic-only helpers (tested directly)

    public static func iconName(for state: ReaderState) -> String {
        switch state {
        case .idle, .loading:
            return "hourglass"
        case .empty(let reason):
            switch reason {
            case .noPages: return "book.closed"
            case .unsupportedFormat: return "doc.questionmark"
            case .zeroLengthDocument: return "doc"
            }
        case .permissionDenied:
            return "lock.shield"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .ready:
            return ""
        }
    }

    static func iconTint(for state: ReaderState) -> Color {
        switch state {
        case .failed:
            return Morandi.warning
        case .permissionDenied:
            return Morandi.warning
        default:
            return Morandi.accent
        }
    }

    public static func titleText(for state: ReaderState) -> String {
        switch state {
        case .idle, .loading:
            return AppLocalization.string("reader.state.loading_title")
        case .empty(let reason):
            switch reason {
            case .noPages:
                return AppLocalization.string("reader.state.empty.no_pages.title")
            case .unsupportedFormat:
                return AppLocalization.string("reader.state.empty.unsupported_format.title")
            case .zeroLengthDocument:
                return AppLocalization.string("reader.state.empty.zero_length.title")
            }
        case .permissionDenied:
            return AppLocalization.string("reader.state.permission_denied.title")
        case .failed:
            return AppLocalization.string("reader.state.failed.title")
        case .ready:
            return ""
        }
    }

    public static func bodyText(for state: ReaderState) -> String {
        switch state {
        case .idle, .loading:
            return AppLocalization.string("reader.state.loading_title")
        case .empty(let reason):
            switch reason {
            case .noPages:
                return AppLocalization.string("reader.state.empty.no_pages.body")
            case .unsupportedFormat(let ext):
                return AppLocalization.format("reader.state.empty.unsupported_format.body_format", ext as CVarArg)
            case .zeroLengthDocument:
                return AppLocalization.string("reader.state.empty.zero_length.body")
            }
        case .permissionDenied(let detail):
            let base = AppLocalization.string("reader.state.permission_denied.body")
            if let detail, detail.isEmpty == false {
                return base + "\n" + detail
            }
            return base
        case .failed(let error):
            let kindMessage = AppLocalization.string(error.kind.localizationKey)
            if let raw = error.underlyingMessage, raw.isEmpty == false {
                let truncated = raw.count > 200 ? String(raw.prefix(200)) + "…" : raw
                return kindMessage + "\n" + truncated
            }
            return kindMessage
        case .ready:
            return ""
        }
    }

    public static func showsRetryButton(for state: ReaderState) -> Bool {
        if case .failed(let error) = state {
            return error.isRecoverable
        }
        return false
    }
}
