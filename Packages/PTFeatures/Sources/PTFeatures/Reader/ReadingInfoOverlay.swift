import Foundation
import SwiftUI
import PTCore
import PTUI

/// W6.3b — Reader header/footer display overlay.
///
/// Renders the user-configured `ReadingInfoLayout` on top of the EPUB
/// navigator so the reader can surface chapter title, page number, reading
/// progress, battery level, session time, and the wall clock without
/// fragile CSS injection into Readium's webviews.
@MainActor
public struct ReadingInfoOverlay: View {
    public let layout: ReadingInfoLayout
    public let context: ReadingInfoContext
    public let isVisible: Bool

    public init(
        layout: ReadingInfoLayout,
        context: ReadingInfoContext,
        isVisible: Bool = true
    ) {
        self.layout = layout
        self.context = context
        self.isVisible = isVisible
    }

    public var body: some View {
        VStack {
            HStack {
                field(layout.topLeft, alignment: .leading)
                Spacer(minLength: 0)
                field(layout.topCenter, alignment: .center)
                Spacer(minLength: 0)
                field(layout.topRight, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer()

            HStack {
                field(layout.bottomLeft, alignment: .leading)
                Spacer(minLength: 0)
                field(layout.bottomCenter, alignment: .center)
                Spacer(minLength: 0)
                field(layout.bottomRight, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .allowsHitTesting(false)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isVisible)
    }

    @ViewBuilder
    private func field(_ field: ReadingInfoField, alignment: HorizontalAlignment) -> some View {
        if field == .nothing {
            // Occupy zero size so Spacer distribution matches the Flutter
            // layout: empty slots should not push neighbouring text around.
            Color.clear.frame(width: 0, height: 0)
        } else {
            Text(ReadingInfoOverlay.render(field: field, context: context))
                .font(ReadingInfoOverlay.font(for: field))
                .foregroundStyle(Morandi.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .multilineTextAlignment(multilineAlignment(for: alignment))
                .accessibilityLabel(ReadingInfoOverlay.accessibilityLabel(for: field, context: context))
        }
    }

    private func multilineAlignment(for horizontal: HorizontalAlignment) -> SwiftUI.TextAlignment {
        switch horizontal {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    // MARK: - Rendering helpers (exposed for testing)

    /// Renders a field as the user-visible string. Returns an empty string
    /// for `nothing` or when the backing context is missing.
    public static func render(field: ReadingInfoField, context: ReadingInfoContext) -> String {
        switch field {
        case .nothing:
            return ""
        case .chapterTitle:
            return context.chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        case .pageNumber:
            guard let page = context.pageNumber else { return "" }
            if let total = context.totalPages, total > 0 {
                return "\(page) / \(total)"
            }
            return "\(page)"
        case .progressPercentage:
            guard let progress = context.progressPercentage else { return "" }
            let clamped = max(0, min(1, progress))
            return "\(Int((clamped * 100).rounded()))%"
        case .readingTime:
            return formatReadingTime(context.readingTime)
        case .batteryLevel:
            guard let level = context.batteryLevel, level >= 0 else { return "" }
            let clamped = max(0, min(1, level))
            return "\(Int((clamped * 100).rounded()))%"
        case .clock:
            return clockFormatter.string(from: context.currentTime)
        }
    }

    public static func accessibilityLabel(for field: ReadingInfoField, context: ReadingInfoContext) -> String {
        let value = render(field: field, context: context)
        let key: String
        switch field {
        case .nothing: return ""
        case .chapterTitle: key = "reader.settings.reading_info.field.chapter"
        case .pageNumber: key = "reader.settings.reading_info.field.page_number"
        case .progressPercentage: key = "reader.settings.reading_info.field.progress"
        case .readingTime: key = "reader.settings.reading_info.field.reading_time"
        case .batteryLevel: key = "reader.settings.reading_info.field.battery"
        case .clock: key = "reader.settings.reading_info.field.clock"
        }
        let label = AppLocalization.string(key)
        return value.isEmpty ? label : "\(label): \(value)"
    }

    static func font(for field: ReadingInfoField) -> Font {
        switch field {
        case .pageNumber, .clock, .batteryLevel, .readingTime, .progressPercentage:
            return Font.caption.monospacedDigit()
        case .chapterTitle, .nothing:
            return Font.caption
        }
    }

    private static func formatReadingTime(_ interval: TimeInterval?) -> String {
        guard let interval, interval.isFinite, interval >= 0 else { return "" }
        let totalSeconds = Int(interval.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "<1m"
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// Immutable snapshot of the reader state used to populate the overlay.
public struct ReadingInfoContext: Sendable, Equatable {
    public let chapterTitle: String?
    public let pageNumber: Int?
    public let totalPages: Int?
    public let progressPercentage: Double?
    public let readingTime: TimeInterval?
    public let batteryLevel: Double?
    public let currentTime: Date

    public init(
        chapterTitle: String? = nil,
        pageNumber: Int? = nil,
        totalPages: Int? = nil,
        progressPercentage: Double? = nil,
        readingTime: TimeInterval? = nil,
        batteryLevel: Double? = nil,
        currentTime: Date = Date()
    ) {
        self.chapterTitle = chapterTitle
        self.pageNumber = pageNumber
        self.totalPages = totalPages
        self.progressPercentage = progressPercentage
        self.readingTime = readingTime
        self.batteryLevel = batteryLevel
        self.currentTime = currentTime
    }
}
