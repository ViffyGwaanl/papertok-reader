import Foundation

public actor ReadingSessionRecorder {
    private let bookId: Int64?
    private let readingTimeDAO: ReadingTimeDAO
    private let minimumRecordedSeconds: Int
    private let calendar: Calendar
    private let nowProvider: @Sendable () -> Date

    private var sessionStart: Date?
    private var activeStart: Date?
    private var accumulatedSeconds: Int = 0

    public init(
        bookId: Int64?,
        database: AppDatabase,
        minimumRecordedSeconds: Int = 5,
        calendar: Calendar = .current,
        nowProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.bookId = bookId
        self.readingTimeDAO = ReadingTimeDAO(database: database)
        self.minimumRecordedSeconds = minimumRecordedSeconds
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    public func resume() {
        let now = nowProvider()
        if sessionStart == nil {
            sessionStart = now
        }
        if activeStart == nil {
            activeStart = now
        }
    }

    public func pause() {
        guard let activeStart else { return }
        accumulatedSeconds += max(Int(nowProvider().timeIntervalSince(activeStart)), 0)
        self.activeStart = nil
    }

    @discardableResult
    public func flush(resetSession: Bool = true) async throws -> Int {
        pause()

        guard let bookId, accumulatedSeconds > minimumRecordedSeconds else {
            if resetSession {
                reset()
            }
            return 0
        }

        let dayKey = dayKey(for: sessionStart ?? nowProvider())
        try await readingTimeDAO.addReadingTime(
            bookId: bookId,
            dayKey: dayKey,
            readingTime: accumulatedSeconds
        )

        let persistedSeconds = accumulatedSeconds
        accumulatedSeconds = 0
        if resetSession {
            sessionStart = nil
        }
        return persistedSeconds
    }

    private func reset() {
        sessionStart = nil
        activeStart = nil
        accumulatedSeconds = 0
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
