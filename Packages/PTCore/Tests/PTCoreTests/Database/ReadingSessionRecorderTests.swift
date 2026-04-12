import Foundation
import Testing
@testable import PTCore

@Suite("ReadingSessionRecorder")
struct ReadingSessionRecorderTests {
    @Test("flush persists accumulated reading time after pause and resume")
    func flushPersistsAccumulatedReadingTimeAfterPauseAndResume() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        var book = Book.placeholder(title: "Recorder", filePath: "/recorder.pdf")
        book.id = 10
        _ = try await bookDAO.save(book)

        let nowBox = MutableNow(makeDate("2026-04-08T10:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let recorder = ReadingSessionRecorder(
            bookId: 10,
            database: database,
            minimumRecordedSeconds: 5,
            calendar: calendar,
            nowProvider: { nowBox.value }
        )

        await recorder.resume()
        nowBox.value = makeDate("2026-04-08T10:00:03Z")
        await recorder.pause()

        nowBox.value = makeDate("2026-04-08T10:00:30Z")
        await recorder.resume()
        nowBox.value = makeDate("2026-04-08T10:00:37Z")

        let persistedSeconds = try await recorder.flush()

        #expect(persistedSeconds == 10)
        let rows = try await ReadingTimeDAO(database: database).fetchByDate("2026-04-08")
        #expect(rows.count == 1)
        #expect(rows[0].readingTime == 10)
    }

    @Test("flush drops sessions at or below the minimum threshold")
    func flushDropsSessionsAtOrBelowTheMinimumThreshold() async throws {
        let database = try AppDatabase.makeInMemory()
        let bookDAO = BookDAO(database: database)
        var book = Book.placeholder(title: "Short Session", filePath: "/short.pdf")
        book.id = 20
        _ = try await bookDAO.save(book)

        let nowBox = MutableNow(makeDate("2026-04-08T11:00:00Z"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let recorder = ReadingSessionRecorder(
            bookId: 20,
            database: database,
            minimumRecordedSeconds: 5,
            calendar: calendar,
            nowProvider: { nowBox.value }
        )

        await recorder.resume()
        nowBox.value = makeDate("2026-04-08T11:00:05Z")

        let persistedSeconds = try await recorder.flush()

        #expect(persistedSeconds == 0)
        let rows = try await ReadingTimeDAO(database: database).fetchByDate("2026-04-08")
        #expect(rows.isEmpty)
    }

    private func makeDate(_ raw: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)!
    }
}

private final class MutableNow: @unchecked Sendable {
    var value: Date

    init(_ value: Date) {
        self.value = value
    }
}
