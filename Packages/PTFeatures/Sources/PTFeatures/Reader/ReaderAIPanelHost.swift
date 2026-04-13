import Foundation
import SwiftUI
import PTCore
import PTUI

public enum ReaderAIPanelSide: String, Sendable, Codable {
    case leading
    case trailing
}

public struct ReaderAIPanelPreferences: Equatable, Sendable {
    public var side: ReaderAIPanelSide
    public var width: Double

    public init(side: ReaderAIPanelSide, width: Double) {
        self.side = side
        self.width = width
    }
}

public enum ReaderAIPanelMetrics {
    public static let defaultWidth: Double = 360

    public static func minWidth(for availableWidth: Double) -> Double {
        min(320, max(260, availableWidth * 0.30))
    }

    public static func maxWidth(for availableWidth: Double) -> Double {
        min(540, max(minWidth(for: availableWidth), availableWidth * 0.55))
    }

    public static func clampedWidth(_ proposed: Double, availableWidth: Double) -> Double {
        guard proposed.isFinite, availableWidth.isFinite, availableWidth > 0 else {
            return defaultWidth
        }
        let lowerBound = minWidth(for: availableWidth)
        let upperBound = maxWidth(for: availableWidth)
        return min(max(proposed, lowerBound), upperBound)
    }
}

public final class ReaderAIPanelPreferencesStore: @unchecked Sendable {
    public static let shared = ReaderAIPanelPreferencesStore()

    private let defaults: UserDefaults
    private let keyPrefix: String

    public init(defaults: UserDefaults = .standard, keyPrefix: String = "reader.ai_panel") {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
    }

    public func load(for bookID: Int64?) -> ReaderAIPanelPreferences {
        let side = ReaderAIPanelSide(
            rawValue: defaults.string(forKey: key(for: "side", bookID: bookID)) ?? ""
        ) ?? .trailing
        let storedWidth = defaults.object(forKey: key(for: "width", bookID: bookID)) as? Double
        let width = storedWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? ReaderAIPanelMetrics.defaultWidth
        return ReaderAIPanelPreferences(side: side, width: width)
    }

    public func save(_ preferences: ReaderAIPanelPreferences, for bookID: Int64?) {
        defaults.set(preferences.side.rawValue, forKey: key(for: "side", bookID: bookID))
        defaults.set(preferences.width, forKey: key(for: "width", bookID: bookID))
    }

    private func key(for field: String, bookID: Int64?) -> String {
        let scope = bookID.map { "book.\($0)" } ?? "global"
        return "\(keyPrefix).\(scope).\(field)"
    }
}

public struct ReaderAIPanelHost<Content: View>: View {
    public let book: Book
    @Bindable public var aiChatViewModel: AIChatViewModel

    @Binding private var isPresented: Bool

    private let preferenceStore: ReaderAIPanelPreferencesStore
    private let content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var panelSide: ReaderAIPanelSide
    @State private var panelWidth: Double
    @State private var dragBaseWidth: Double?

    public init(
        book: Book,
        aiChatViewModel: AIChatViewModel,
        isPresented: Binding<Bool>,
        preferenceStore: ReaderAIPanelPreferencesStore = .shared,
        @ViewBuilder content: () -> Content
    ) {
        self.book = book
        self.aiChatViewModel = aiChatViewModel
        self._isPresented = isPresented
        self.preferenceStore = preferenceStore
        self.content = content()

        let preferences = preferenceStore.load(for: book.id)
        _panelSide = State(initialValue: preferences.side)
        _panelWidth = State(initialValue: preferences.width)
    }

    public var body: some View {
        GeometryReader { geometry in
            let availableWidth = max(Double(geometry.size.width), ReaderAIPanelMetrics.defaultWidth)
            let resolvedWidth = ReaderAIPanelMetrics.clampedWidth(panelWidth, availableWidth: availableWidth)

            Group {
                if usesDockedPanel {
                    HStack(spacing: 0) {
                        if isPresented && panelSide == .leading {
                            dockedPanel(width: resolvedWidth, availableWidth: availableWidth)
                            Divider()
                                .background(Morandi.divider)
                        }

                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if isPresented && panelSide == .trailing {
                            Divider()
                                .background(Morandi.divider)
                            dockedPanel(width: resolvedWidth, availableWidth: availableWidth)
                        }
                    }
                } else {
                    content
                }
            }
            .sheet(isPresented: compactPresentationBinding) {
                compactPanel
            }
            .onChange(of: geometry.size.width) { _, newWidth in
                let clamped = ReaderAIPanelMetrics.clampedWidth(panelWidth, availableWidth: Double(newWidth))
                guard clamped != panelWidth else { return }
                panelWidth = clamped
                persistPreferences()
            }
        }
    }

    private var usesDockedPanel: Bool {
        horizontalSizeClass != .compact
    }

    private var compactPresentationBinding: Binding<Bool> {
        Binding(
            get: { usesDockedPanel == false && isPresented },
            set: { newValue in
                guard usesDockedPanel == false else { return }
                isPresented = newValue
            }
        )
    }

    private var compactPanel: some View {
        panelContent(isCompact: true)
#if os(iOS)
            .presentationDetents([.fraction(0.35), .medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(.regularMaterial)
#endif
            .interactiveDismissDisabled(aiChatViewModel.isStreaming || hasPendingApprovals)
    }

    private func dockedPanel(width: Double, availableWidth: Double) -> some View {
        HStack(spacing: 0) {
            if panelSide == .trailing {
                resizeHandle(availableWidth: availableWidth)
            }

            panelContent(isCompact: false)
                .frame(width: width)
                .background(Morandi.background)

            if panelSide == .leading {
                resizeHandle(availableWidth: availableWidth)
            }
        }
    }

    private func panelContent(isCompact: Bool) -> some View {
        NavigationStack {
            AIChatView(viewModel: aiChatViewModel)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: isCompact ? "common.close" : "common.minimize")) {
                            isPresented = false
                        }
                    }

                    if isCompact == false {
                        ToolbarItem(placement: movePanelToolbarPlacement) {
                            Button {
                                panelSide = panelSide == .leading ? .trailing : .leading
                                persistPreferences()
                            } label: {
                                Image(systemName: panelSide == .leading ? "sidebar.trailing" : "sidebar.leading")
                            }
                            .accessibilityLabel(String(localized: "reader.ai_panel.move"))
                        }
                    }
                }
        }
    }

    private func resizeHandle(availableWidth: Double) -> some View {
        let direction = panelSide == .leading ? 1.0 : -1.0

        return Rectangle()
            .fill(.clear)
            .frame(width: 16)
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(Morandi.divider)
                    .frame(width: 4, height: 48)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragBaseWidth == nil {
                            dragBaseWidth = panelWidth
                        }
                        let baseWidth = dragBaseWidth ?? panelWidth
                        panelWidth = ReaderAIPanelMetrics.clampedWidth(
                            baseWidth + Double(value.translation.width) * direction,
                            availableWidth: availableWidth
                        )
                    }
                    .onEnded { _ in
                        dragBaseWidth = nil
                        persistPreferences()
                    }
            )
            .accessibilityLabel(String(localized: "reader.ai_panel.resize"))
    }

    private var hasPendingApprovals: Bool {
        aiChatViewModel.pendingApprovals.contains(where: { $0.isApproved == nil })
    }

    private var movePanelToolbarPlacement: ToolbarItemPlacement {
#if os(macOS)
        .navigation
#else
        .topBarLeading
#endif
    }

    private func persistPreferences() {
        preferenceStore.save(
            ReaderAIPanelPreferences(
                side: panelSide,
                width: panelWidth
            ),
            for: book.id
        )
    }
}

public struct ReaderAIMinimizedBar: View {
    @Bindable public var aiChatViewModel: AIChatViewModel
    private let reopen: () -> Void

    public init(
        aiChatViewModel: AIChatViewModel,
        reopen: @escaping () -> Void
    ) {
        self.aiChatViewModel = aiChatViewModel
        self.reopen = reopen
    }

    public var body: some View {
        if aiChatViewModel.isStreaming || hasPendingApprovals {
            Button(action: reopen) {
                HStack(spacing: AppSpacing.sm) {
                    if aiChatViewModel.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Text(statusText)
                        .font(AppTypography.footnote.weight(.medium))
                        .foregroundStyle(Morandi.primaryText)

                    Spacer(minLength: AppSpacing.md)

                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Morandi.accent)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(Morandi.cardBackground)
                .clipShape(Capsule())
                .shadow(color: Morandi.warmGray.opacity(0.18), radius: AppSpacing.shadowRadius)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(.clear)
        }
    }

    private var hasPendingApprovals: Bool {
        aiChatViewModel.pendingApprovals.contains(where: { $0.isApproved == nil })
    }

    private var statusText: String {
        if hasPendingApprovals {
            let count = aiChatViewModel.pendingApprovals.filter { $0.isApproved == nil }.count
            if count == 1 {
                return String(localized: "reader.ai_panel.pending_approval")
            }
            return AppLocalization.format(
                "reader.ai_panel.pending_approvals_format",
                "AI needs %d approvals",
                count
            )
        }
        return String(localized: "reader.ai_panel.responding")
    }
}
