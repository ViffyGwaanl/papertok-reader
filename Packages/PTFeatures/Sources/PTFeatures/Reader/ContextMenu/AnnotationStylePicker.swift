import SwiftUI
import Observation
import PTCore
import PTReader
import PTUI

/// Observable state backing the annotation style picker. The picker tracks the
/// currently-selected style (highlight / underline / strikethrough) and the
/// currently-selected color independently; committing a color fires a callback
/// with the (kind, color) tuple so the caller can create the annotation.
@Observable
@MainActor
public final class AnnotationStylePickerState {
    public var kind: BookNoteAnnotationKind
    public var color: HighlightColor

    public init(kind: BookNoteAnnotationKind = .highlight, color: HighlightColor = .yellow) {
        self.kind = kind
        self.color = color
    }

    public func selectKind(_ newKind: BookNoteAnnotationKind) {
        kind = newKind
    }

    public func selectColor(_ newColor: HighlightColor) {
        color = newColor
    }
}

/// Segmented annotation-style picker: three SF-Symbol segments for style on
/// top, a Morandi-tinted color row underneath. Tapping a style segment only
/// changes the current kind; tapping a color commits the (kind, color) pair
/// to the `onCommit` callback.
struct AnnotationStylePicker: View {
    @Bindable var state: AnnotationStylePickerState
    let onCommit: (BookNoteAnnotationKind, HighlightColor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            styleSegments
            HighlightColorPicker(
                selected: state.color,
                onSelect: { color in
                    state.selectColor(color)
                    onCommit(state.kind, color)
                }
            )
        }
    }

    private var styleSegments: some View {
        HStack(spacing: AppSpacing.xs) {
            segment(for: .highlight, label: Text("reader.annotation.style.highlight"))
            segment(for: .underline, label: Text("reader.annotation.style.underline"))
            segment(for: .strikethrough, label: Text("reader.annotation.style.strikethrough"))
        }
    }

    private func segment(for kind: BookNoteAnnotationKind, label: Text) -> some View {
        Button {
            state.selectKind(kind)
        } label: {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: Self.systemImage(for: kind))
                    .font(.system(size: 14, weight: .semibold))
                label
                    .font(AppTypography.caption)
                    .lineLimit(1)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, AppSpacing.xs)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                    .fill(state.kind == kind
                          ? Morandi.dustyRose.opacity(0.2)
                          : Morandi.cardBackground)
            )
            .foregroundStyle(state.kind == kind ? Morandi.accent : Morandi.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(state.kind == kind ? [.isSelected] : [])
    }

    static func systemImage(for kind: BookNoteAnnotationKind) -> String {
        switch kind {
        case .highlight: return "highlighter"
        case .underline: return "underline"
        case .strikethrough: return "strikethrough"
        }
    }

    static func titleKey(for kind: BookNoteAnnotationKind) -> String {
        switch kind {
        case .highlight: return "reader.annotation.style.highlight"
        case .underline: return "reader.annotation.style.underline"
        case .strikethrough: return "reader.annotation.style.strikethrough"
        }
    }
}
