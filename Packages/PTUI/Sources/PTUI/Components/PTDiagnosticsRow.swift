import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A key-value row for diagnostics sections. Label on left, value on right, optional copy button.
public struct PTDiagnosticsRow: View {
    let label: LocalizedStringKey
    let value: String
    let copyable: Bool

    public init(label: LocalizedStringKey, value: String, copyable: Bool = true) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(label)
                .font(AppTypography.subheadline)
                .foregroundStyle(Morandi.secondaryText)

            Spacer()

            Text(value)
                .font(AppTypography.mono)
                .foregroundStyle(Morandi.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            if copyable {
                Button {
                    copyToClipboard(value)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(AppTypography.caption)
                        .foregroundStyle(Morandi.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.copy"))
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, AppSpacing.lg)
    }

    private func copyToClipboard(_ string: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = string
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}

// MARK: - Test Hooks

extension PTDiagnosticsRow {
    struct TestHooks {
        let value: String
        let copyable: Bool
    }

    var testHooks: TestHooks {
        TestHooks(value: value, copyable: copyable)
    }
}
