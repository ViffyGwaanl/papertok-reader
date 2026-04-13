#if canImport(SwiftUI) && canImport(Charts)
import SwiftUI
import Charts
import PTCore
import PTUI

/// Displays daily reading time trends, weekday averages, and per-book breakdowns.
public struct ReadingTrendChartView: View {
    public enum ChartMode: String, CaseIterable, Identifiable, Sendable {
        case daily
        case weekday
        case perBook

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .daily: return AppLocalization.string("statistics.daily", value: "Daily")
            case .weekday: return AppLocalization.string("statistics.weekday", value: "Weekday")
            case .perBook: return AppLocalization.string("statistics.by_book", value: "By Book")
            }
        }
    }

    public struct DailyPoint: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let date: Date
        public let minutes: Double

        public init(id: UUID = UUID(), date: Date, minutes: Double) {
            self.id = id
            self.date = date
            self.minutes = minutes
        }
    }

    public struct WeekdayPoint: Identifiable, Sendable, Equatable {
        public let id: UUID
        /// 1 = Sunday ... 7 = Saturday (matches Calendar weekday)
        public let weekday: Int
        public let minutes: Double

        public init(id: UUID = UUID(), weekday: Int, minutes: Double) {
            self.id = id
            self.weekday = weekday
            self.minutes = minutes
        }

        public var label: String {
            let symbols = Calendar.current.shortWeekdaySymbols
            guard weekday >= 1, weekday <= symbols.count else { return "" }
            return symbols[weekday - 1]
        }
    }

    public struct BookPoint: Identifiable, Sendable, Equatable {
        public let id: UUID
        public let bookTitle: String
        public let minutes: Double

        public init(id: UUID = UUID(), bookTitle: String, minutes: Double) {
            self.id = id
            self.bookTitle = bookTitle
            self.minutes = minutes
        }
    }

    public enum RangeSelection: String, CaseIterable, Identifiable, Sendable {
        case thirtyDays
        case ninetyDays

        public var id: String { rawValue }

        public var days: Int {
            switch self {
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }

        public var displayName: String {
            switch self {
            case .thirtyDays: return AppLocalization.string("statistics.last_30_days", value: "Last 30 Days")
            case .ninetyDays: return AppLocalization.string("statistics.last_90_days", value: "Last 90 Days")
            }
        }
    }

    private let daily: [DailyPoint]
    private let weekday: [WeekdayPoint]
    private let perBook: [BookPoint]

    @State private var mode: ChartMode = .daily
    @State private var range: RangeSelection = .thirtyDays

    public init(
        daily: [DailyPoint],
        weekday: [WeekdayPoint],
        perBook: [BookPoint]
    ) {
        self.daily = daily
        self.weekday = weekday
        self.perBook = perBook
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(String(localized: "common.mode"), selection: $mode) {
                ForEach(ChartMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)

            if mode == .daily {
                Picker(String(localized: "common.range"), selection: $range) {
                    ForEach(RangeSelection.allCases) { r in
                        Text(r.displayName).tag(r)
                    }
                }
                .pickerStyle(.segmented)
            }

            chartContent
                .frame(height: 240)
                .padding(12)
                .background(Morandi.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Morandi.background.ignoresSafeArea())
    }

    @ViewBuilder
    private var chartContent: some View {
        switch mode {
        case .daily:
            dailyChart
        case .weekday:
            weekdayChart
        case .perBook:
            perBookChart
        }
    }

    private var dailyChart: some View {
        let points = filteredDaily
        return Chart(points) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Minutes", point.minutes)
            )
            .foregroundStyle(Morandi.sage)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Date", point.date),
                y: .value("Minutes", point.minutes)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Morandi.sage.opacity(0.35), Morandi.sage.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.catmullRom)
        }
        .chartYAxisLabel(String(localized: "common.minutes"))
    }

    private var weekdayChart: some View {
        Chart(weekday) { point in
            BarMark(
                x: .value("Day", point.label),
                y: .value("Minutes", point.minutes)
            )
            .foregroundStyle(Morandi.powder)
            .cornerRadius(4)
        }
        .chartYAxisLabel(String(localized: "statistics.avg_minutes"))
    }

    private var perBookChart: some View {
        Chart(perBook) { point in
            BarMark(
                x: .value("Minutes", point.minutes),
                y: .value("Book", point.bookTitle)
            )
            .foregroundStyle(by: .value("Book", point.bookTitle))
            .cornerRadius(4)
        }
        .chartForegroundStyleScale(range: morandiPalette)
        .chartXAxisLabel(String(localized: "common.minutes"))
    }

    private var filteredDaily: [DailyPoint] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.days, to: Date()) else {
            return daily
        }
        return daily.filter { $0.date >= cutoff }
    }

    private var morandiPalette: [Color] {
        [
            Morandi.sage,
            Morandi.dustyRose,
            Morandi.powder,
            Morandi.clay,
            Morandi.lavender,
            Morandi.moss,
            Morandi.mauve,
            Morandi.sand
        ]
    }
}
#endif
