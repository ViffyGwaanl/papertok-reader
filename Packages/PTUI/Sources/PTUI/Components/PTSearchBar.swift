import SwiftUI

public struct PTSearchBar: View {
    @Binding var text: String
    let placeholder: String

    public init(text: Binding<String>, placeholder: String = "Search") {
        self._text = text; self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Morandi.secondaryText)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Morandi.tertiaryText)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.sm)
        .background(Morandi.divider.opacity(0.3), in: RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
    }
}
