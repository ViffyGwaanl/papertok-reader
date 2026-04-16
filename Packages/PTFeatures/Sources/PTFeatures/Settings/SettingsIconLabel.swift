import SwiftUI
import PTUI

/// Claude-app style row label: a monochrome SF Symbol glyph followed by a
/// title (and optional subtitle). The icon is rendered in neutral text color
/// — no tinted rounded-square background — so settings rows feel understated
/// and consistent, matching the Claude iOS design language.
///
/// The `tint` parameter is retained for API compatibility with earlier
/// call sites but is ignored by the monochrome rendering. State-carrying
/// indicators (toggles, status dots, badges) should be implemented by
/// callers elsewhere — this label is for decorative row icons only.
public struct SettingsIconLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let subtitle: String?

    public init(
        _ title: String,
        systemImage: String,
        tint: Color = Morandi.primaryText,
        subtitle: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Morandi.primaryText)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Morandi.primaryText)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Morandi.secondaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Test Hooks

extension SettingsIconLabel {
    /// Visual style identifier exposed for tests and telemetry, so we can
    /// assert that settings rows continue to render in monochrome.
    public enum IconStyle: String, Sendable {
        case monochrome
        case tintedSquare
    }

    public struct TestHooks {
        public let systemImage: String
        public let iconStyle: IconStyle
        public let hasSubtitle: Bool
    }

    public var testHooks: TestHooks {
        TestHooks(
            systemImage: systemImage,
            iconStyle: .monochrome,
            hasSubtitle: (subtitle?.isEmpty == false)
        )
    }
}
