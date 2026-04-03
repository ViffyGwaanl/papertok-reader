import Testing
import Foundation
@testable import PTNetworking

@Suite("SSEParser")
struct SSEParserTests {
    @Test("Parses single data-only event")
    func singleDataEvent() async throws {
        let raw = "data: {\"text\":\"hello\"}\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "{\"text\":\"hello\"}")
        #expect(events[0].event == nil)
        #expect(events[0].id == nil)
    }

    @Test("Parses event with type and id")
    func eventWithTypeAndId() async throws {
        let raw = "event: message\nid: 42\ndata: payload\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].event == "message")
        #expect(events[0].id == "42")
        #expect(events[0].data == "payload")
    }

    @Test("Parses multi-line data (joined with newlines)")
    func multiLineData() async throws {
        let raw = "data: line1\ndata: line2\ndata: line3\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "line1\nline2\nline3")
    }

    @Test("Parses multiple events in stream")
    func multipleEvents() async throws {
        let raw = "data: first\n\ndata: second\n\ndata: third\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 3)
        #expect(events[0].data == "first")
        #expect(events[1].data == "second")
        #expect(events[2].data == "third")
    }

    @Test("Skips comment lines (colon prefix)")
    func skipsComments() async throws {
        let raw = ": this is a comment\ndata: actual\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "actual")
    }

    @Test("Handles [DONE] sentinel")
    func doneSignal() async throws {
        let raw = "data: {\"text\":\"hi\"}\n\ndata: [DONE]\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 2)
        #expect(events[1].data == "[DONE]")
    }

    @Test("Handles retry field")
    func retryField() async throws {
        let raw = "retry: 5000\ndata: hello\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].retry == 5000)
        #expect(events[0].data == "hello")
    }

    @Test("Ignores lines without colon")
    func ignoresInvalidLines() async throws {
        let raw = "invalid line\ndata: valid\n\n"
        let events = try await collectEvents(from: raw)
        #expect(events.count == 1)
        #expect(events[0].data == "valid")
    }

    // MARK: - Helper

    private func collectEvents(from text: String) async throws -> [SSEEvent] {
        let lines = text.components(separatedBy: "\n")
        let stream = SSEParser.events(from: makeAsyncLines(lines))
        var events: [SSEEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func makeAsyncLines(_ lines: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}
