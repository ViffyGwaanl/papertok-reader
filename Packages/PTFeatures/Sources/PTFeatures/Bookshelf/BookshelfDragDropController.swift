#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import PTUI

/// SwiftUI `DropDelegate` used by the bookshelf to move books between groups.
///
/// Usage:
/// ```swift
/// .onDrop(
///     of: [.plainText],
///     delegate: BookshelfDragDropController(
///         targetGroupId: group.id,
///         draggedBookId: $draggedBookId,
///         isTargeted: $isTargeted,
///         onMove: { bookId, groupId in
///             try await bookDAO.move(id: bookId, toGroupId: groupId)
///         }
///     )
/// )
/// ```
public struct BookshelfDragDropController: DropDelegate {
    /// Destination group for the drop, or `nil` for "no group".
    public let targetGroupId: Int64?

    /// The currently dragged book id.
    @Binding public var draggedBookId: Int64?

    /// Whether the destination is currently being hovered.
    @Binding public var isTargeted: Bool

    /// Callback invoked when a book is dropped onto the destination.
    public let onMove: @Sendable (_ bookId: Int64, _ targetGroupId: Int64?) async -> Void

    public init(
        targetGroupId: Int64?,
        draggedBookId: Binding<Int64?>,
        isTargeted: Binding<Bool>,
        onMove: @escaping @Sendable (_ bookId: Int64, _ targetGroupId: Int64?) async -> Void
    ) {
        self.targetGroupId = targetGroupId
        self._draggedBookId = draggedBookId
        self._isTargeted = isTargeted
        self.onMove = onMove
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    public func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    public func dropExited(info: DropInfo) {
        isTargeted = false
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false

        guard let provider = info.itemProviders(for: [UTType.plainText]).first else {
            // Fallback to the tracked draggedBookId if no provider is attached.
            if let id = draggedBookId {
                draggedBookId = nil
                let target = targetGroupId
                let callback = onMove
                Task { await callback(id, target) }
                return true
            }
            return false
        }

        let target = targetGroupId
        let callback = onMove

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let string = item as? String,
                  let bookId = Int64(string) else { return }
            Task {
                await callback(bookId, target)
            }
        }
        draggedBookId = nil
        return true
    }
}

/// Visual modifier that highlights a drop target when hovered.
public struct BookshelfDropHighlight: ViewModifier {
    public let isTargeted: Bool

    public init(isTargeted: Bool) {
        self.isTargeted = isTargeted
    }

    public func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargeted ? Morandi.sage : .clear,
                        lineWidth: 2
                    )
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)
            )
            .scaleEffect(isTargeted ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

extension View {
    /// Convenience modifier that applies `BookshelfDropHighlight`.
    public func bookshelfDropHighlight(isTargeted: Bool) -> some View {
        modifier(BookshelfDropHighlight(isTargeted: isTargeted))
    }
}
#endif
