import SwiftUI
import PTUI

/// Lightweight value carrier for the footnote popover. The EPUB host
/// view resolves the footnote text (typically via Readium's
/// `publication.get(link:)` plus an HTML→plain-text extraction) and
/// hands the resulting content to this view.
public struct FootnotePopoverContent: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let body: String
    public let sourceHref: String

    public init(title: String, body: String, sourceHref: String) {
        self.title = title
        self.body = body
        self.sourceHref = sourceHref
    }
}

/// Bottom-sheet style popover that shows footnote content without
/// navigating the main reader away from the current page.
///
/// Designed to be presented from `.sheet(item:)` so the caller keeps
/// control over dismissal and can intercept Readium's link-tap delegate
/// at the top level.
public struct FootnotePopoverView: View {
    let content: FootnotePopoverContent
    let onClose: () -> Void

    public init(content: FootnotePopoverContent, onClose: @escaping () -> Void) {
        self.content = content
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(content.body)
                        .font(AppTypography.body)
                        .foregroundStyle(Morandi.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(AppSpacing.lg)
            }
            .background(Morandi.background)
            .navigationTitle(String(localized: "reader.footnote.title"))
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onClose()
                    } label: {
                        Text("common.close")
                    }
                    .foregroundStyle(Morandi.accent)
                    .accessibilityLabel(String(localized: "reader.footnote.close"))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
