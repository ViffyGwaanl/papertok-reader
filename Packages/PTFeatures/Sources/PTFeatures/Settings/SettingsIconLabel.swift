import SwiftUI
import PTUI

/// Apple Settings-app style row label: a tinted rounded-square glyph followed by
/// a title (and optional subtitle). Designed to be used inside a `Form` or
/// `NavigationLink` label so the built-in chevron is rendered automatically.
public struct SettingsIconLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let subtitle: String?

    public init(
        _ title: String,
        systemImage: String,
        tint: Color,
        subtitle: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.subtitle = subtitle
    }

    public var body: some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint)
                    .frame(width: 29, height: 29)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
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
