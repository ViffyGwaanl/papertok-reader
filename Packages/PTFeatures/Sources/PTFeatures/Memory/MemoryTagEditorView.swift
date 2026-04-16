import SwiftUI
import PTUI

struct MemoryTagEditorView: View {
    @Binding var tags: [String]
    let allKnownTags: [String]
    let onSave: ([String]) -> Void

    @State private var newTagText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Current tags
                Text("memory.tags.current")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(Morandi.secondaryText)

                FlowLayout(spacing: AppSpacing.xs) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                                .font(AppTypography.caption2)
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Morandi.sage.opacity(0.18)))
                        .foregroundStyle(Morandi.sage)
                    }
                }

                // Add new tag
                HStack(spacing: AppSpacing.sm) {
                    TextField(String(localized: "memory.tags.add_placeholder"), text: $newTagText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCurrentTag() }

                    Button("memory.tags.add") {
                        addCurrentTag()
                    }
                    .buttonStyle(.bordered)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Suggestions from existing tags
                let suggestions = suggestedTags
                if suggestions.isEmpty == false {
                    Text("memory.tags.suggestions")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(Morandi.secondaryText)

                    FlowLayout(spacing: AppSpacing.xs) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button {
                                if !tags.contains(tag) {
                                    tags.append(tag)
                                }
                            } label: {
                                Text(tag)
                                    .font(AppTypography.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Capsule().fill(Morandi.accent.opacity(0.12)))
                                    .foregroundStyle(Morandi.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
            .padding(AppSpacing.md)
            .navigationTitle(String(localized: "memory.tags.editor_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") {
                        onSave(tags)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var suggestedTags: [String] {
        let query = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unused = allKnownTags.filter { !tags.contains($0) }
        if query.isEmpty {
            return unused
        }
        return unused.filter { $0.lowercased().contains(query) }
    }

    private func addCurrentTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.isEmpty == false, !tags.contains(tag) else { return }
        tags.append(tag)
        newTagText = ""
    }
}

/// Simple flow layout for tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            totalWidth = max(totalWidth, x - spacing)
            totalHeight = max(totalHeight, y + rowHeight)
        }

        return ArrangeResult(positions: positions, size: CGSize(width: totalWidth, height: totalHeight))
    }
}
