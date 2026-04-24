import SwiftUI
import PTCore
import PTReader
import PTUI

/// Floating context menu that appears near selected text in the reader.
///
/// Layout:
/// - Annotation style segment + color row (tap a swatch to highlight).
/// - A primary action row (note / copy / translate / define) plus a "More…"
///   entry that reveals the long-tail actions (explain / summarize / search /
///   share) in a bottom sheet.
///
/// Positioning:
/// - When `coordinator.selectionFrame` is non-nil, the menu picks the best
///   placement (`above` / `below` / `center`) relative to the selection and
///   renders a callout arrow pointing at it.
/// - When `selectionFrame` is nil, the view renders as a plain card and
///   relies on its host overlay's alignment (center) for placement.
public struct ReaderContextMenuView: View {
    @Bindable var coordinator: ContextMenuCoordinator
    let onDismiss: () -> Void
    @State private var pickerState: AnnotationStylePickerState
    @State private var showMoreSheet: Bool = false

    /// Approximate card height used for space calculations. The real card
    /// measures itself via `GeometryReader`, but we need an estimate before
    /// first layout to pick the placement.
    private static let estimatedMenuHeight: CGFloat = 220

    public init(coordinator: ContextMenuCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
        _pickerState = State(initialValue: AnnotationStylePickerState(
            kind: coordinator.annotationKind,
            color: coordinator.highlightColor
        ))
    }

    public var body: some View {
        Group {
            if let frame = coordinator.selectionFrame {
                positionedMenu(for: frame)
            } else {
                card
            }
        }
        .sheet(isPresented: $showMoreSheet) {
            MoreActionsSheet(
                actions: ContextMenuActionGrouping.moreActions,
                iconColor: iconColor,
                onSelect: { action in
                    showMoreSheet = false
                    coordinator.handleAction(action)
                    if dismissesImmediately(action) {
                        onDismiss()
                    }
                }
            )
            .presentationDetentsIfAvailable()
        }
    }

    // MARK: - Positioned layout

    @ViewBuilder
    private func positionedMenu(for selectionFrame: CGRect) -> some View {
        GeometryReader { proxy in
            let placement = ContextMenuPlacement.optimal(
                for: selectionFrame,
                in: proxy.size,
                menuHeight: Self.estimatedMenuHeight
            )
            CalloutCard(placement: placement, calloutX: arrowX(for: selectionFrame, in: proxy.size)) {
                card
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 320)
            .alignmentGuide(.leading) { _ in 0 }
            .overlay(
                GeometryReader { cardProxy in
                    Color.clear.preference(
                        key: MenuSizePreferenceKey.self,
                        value: cardProxy.size
                    )
                }
            )
            .offset(
                offset(
                    for: placement,
                    selectionFrame: selectionFrame,
                    in: proxy.size
                )
            )
        }
    }

    private func arrowX(for selection: CGRect, in viewBounds: CGSize) -> CGFloat {
        // Arrow points at selection midpoint, clamped into the card bounds.
        let cardWidth: CGFloat = 320
        let cardOriginX = min(
            max(8, selection.midX - cardWidth / 2),
            max(8, viewBounds.width - cardWidth - 8)
        )
        let rawArrowX = selection.midX - cardOriginX
        return min(max(16, rawArrowX), cardWidth - 16)
    }

    private func offset(
        for placement: ContextMenuPlacement,
        selectionFrame: CGRect,
        in viewBounds: CGSize
    ) -> CGSize {
        let origin = placement.menuOrigin(
            for: selectionFrame,
            in: viewBounds,
            menuSize: CGSize(width: 320, height: Self.estimatedMenuHeight)
        )
        return CGSize(width: origin.x, height: origin.y)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: AppSpacing.sm) {
            // Style segment + color row
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("reader.highlight")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                AnnotationStylePicker(state: pickerState) { kind, color in
                    coordinator.annotationKind = kind
                    coordinator.highlightColor = color
                    coordinator.handleAction(.highlight)
                    onDismiss()
                }
                .padding(.vertical, AppSpacing.xs)
            }

            Divider()
                .frame(height: 1)
                .overlay(Morandi.divider)

            // Primary action row + More…
            primaryActionRow
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .frame(maxWidth: 320)
    }

    private var primaryActionRow: some View {
        let primary = ContextMenuActionGrouping.primaryActions

        return HStack(spacing: AppSpacing.xs) {
            ForEach(primary) { action in
                actionTile(for: action) {
                    coordinator.handleAction(action)
                    if dismissesImmediately(action) {
                        onDismiss()
                    }
                }
            }
            moreTile
        }
    }

    private func actionTile(for action: ContextMenuAction, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: action.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(iconColor(for: action))
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                            .fill(iconColor(for: action).opacity(0.12))
                    )

                Text(action.title)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ContextMenuButtonStyle())
        .accessibilityLabel(Text(action.title))
    }

    private var moreTile: some View {
        Button {
            showMoreSheet = true
        } label: {
            VStack(spacing: AppSpacing.xs) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18))
                    .foregroundStyle(Morandi.secondaryText)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                            .fill(Morandi.divider.opacity(0.35))
                    )

                Text("reader.more_options")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ContextMenuButtonStyle())
        .accessibilityLabel(Text("reader.more_options"))
    }

    private func dismissesImmediately(_ action: ContextMenuAction) -> Bool {
        switch action {
        case .copy, .highlight, .search:
            return true
        default:
            return false
        }
    }

    private func iconColor(for action: ContextMenuAction) -> Color {
        switch action.category {
        case .annotate: return Morandi.dustyRose
        case .ai:       return Morandi.sage
        case .utility:  return Morandi.powder
        }
    }
}

// MARK: - Subviews

/// A bottom-sheet list of the overflow actions (explain / summarize / search
/// / share) presented when the user taps the "More…" tile.
private struct MoreActionsSheet: View {
    let actions: [ContextMenuAction]
    let iconColor: (ContextMenuAction) -> Color
    let onSelect: (ContextMenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("reader.context_menu.more_actions.title")
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.primaryText)
                .padding(.top, AppSpacing.md)

            Divider().overlay(Morandi.divider)

            VStack(spacing: AppSpacing.xs) {
                ForEach(actions) { action in
                    Button {
                        onSelect(action)
                    } label: {
                        HStack(spacing: AppSpacing.md) {
                            Image(systemName: action.icon)
                                .font(.system(size: 18))
                                .foregroundStyle(iconColor(action))
                                .frame(width: 32, height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                                        .fill(iconColor(action).opacity(0.12))
                                )

                            Text(action.title)
                                .font(AppTypography.body)
                                .foregroundStyle(Morandi.primaryText)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Morandi.tertiaryText)
                        }
                        .padding(.vertical, AppSpacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(ContextMenuButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md)
        .background(Morandi.background.ignoresSafeArea())
    }
}

/// Wraps the menu card and draws a small callout triangle that points at
/// the selection. Hidden for `.center` placement.
private struct CalloutCard<Content: View>: View {
    let placement: ContextMenuPlacement
    let calloutX: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            if placement == .below {
                arrow(pointingDown: false)
                    .padding(.leading, calloutX - 6)
            }

            content()

            if placement == .above {
                arrow(pointingDown: true)
                    .padding(.leading, calloutX - 6)
            }
        }
    }

    private func arrow(pointingDown: Bool) -> some View {
        CalloutTriangle(pointingDown: pointingDown)
            .fill(Morandi.cardBackground)
            .frame(width: 12, height: 6)
            .shadow(color: .black.opacity(0.08), radius: 2, y: pointingDown ? 1 : -1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A tiny triangle that forms the callout arrow. Always drawn with the
/// triangle base flush with the menu card.
struct CalloutTriangle: Shape {
    let pointingDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if pointingDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// Shared button style for context-menu tiles: subtle scale-down on press.
struct ContextMenuButtonStyle: SwiftUI.ButtonStyle {
    func makeBody(configuration: SwiftUI.ButtonStyleConfiguration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Preference keys

private struct MenuSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

// MARK: - Back-deploy helpers

private extension View {
    /// Apply `presentationDetents` on iOS 16+ / macOS 13+, no-op otherwise.
    @ViewBuilder
    func presentationDetentsIfAvailable() -> some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            self.presentationDetents([.medium, .large])
        } else {
            self
        }
    }
}
