import Foundation

public enum SSEParser {
    /// Parse an `AsyncStream<String>` of lines into SSE events.
    public static func events(from lines: AsyncStream<String>) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var eventType: String?
                var dataLines: [String] = []
                var eventId: String?
                var retry: Int?

                for await line in lines {
                    if line.isEmpty {
                        if !dataLines.isEmpty {
                            let event = SSEEvent(
                                event: eventType,
                                data: dataLines.joined(separator: "\n"),
                                id: eventId,
                                retry: retry
                            )
                            continuation.yield(event)
                        }
                        eventType = nil
                        dataLines = []
                        eventId = nil
                        retry = nil
                        continue
                    }

                    if line.hasPrefix(":") { continue }

                    let field: String
                    let value: String
                    if let colonIndex = line.firstIndex(of: ":") {
                        field = String(line[line.startIndex..<colonIndex])
                        let afterColon = line.index(after: colonIndex)
                        if afterColon < line.endIndex && line[afterColon] == " " {
                            value = String(line[line.index(after: afterColon)...])
                        } else {
                            value = String(line[afterColon...])
                        }
                    } else {
                        continue
                    }

                    switch field {
                    case "event": eventType = value
                    case "data": dataLines.append(value)
                    case "id": eventId = value
                    case "retry": retry = Int(value)
                    default: break
                    }
                }

                if !dataLines.isEmpty {
                    let event = SSEEvent(
                        event: eventType,
                        data: dataLines.joined(separator: "\n"),
                        id: eventId,
                        retry: retry
                    )
                    continuation.yield(event)
                }

                continuation.finish()
            }
        }
    }

    /// Convenience: parse `URLSession.AsyncBytes` into SSE events.
    public static func events(from bytes: URLSession.AsyncBytes, heartbeatTimeout: TimeInterval = 15) -> AsyncThrowingStream<SSEEvent, Error> {
        let lines = AsyncStream<String> { continuation in
            Task {
                var buffer = ""
                for try await byte in bytes {
                    let char = Character(UnicodeScalar(byte))
                    if char == "\n" {
                        continuation.yield(buffer)
                        buffer = ""
                    } else if char != "\r" {
                        buffer.append(char)
                    }
                }
                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
        }
        return events(from: lines)
    }
}
