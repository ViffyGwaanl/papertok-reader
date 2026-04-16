import os

/// Zero-cost performance markers visible in Instruments but compiled away
/// in optimized builds. Wrap key user-facing flows with begin/end pairs
/// so that Instruments' os_signpost timeline shows wall-clock durations.
public enum PerformanceSignposts {
    private static let log = OSLog(subsystem: "ai.papertok.reader", category: "Performance")

    // MARK: - Book Open

    public static func beginBookOpen() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "BookOpen", signpostID: id)
        return id
    }

    public static func endBookOpen(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "BookOpen", signpostID: id)
    }

    // MARK: - Chat Send

    public static func beginChatSend() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ChatSend", signpostID: id)
        return id
    }

    public static func endChatSend(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "ChatSend", signpostID: id)
    }

    // MARK: - Chapter Enumeration

    public static func beginChapterEnum() -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "ChapterEnum", signpostID: id)
        return id
    }

    public static func endChapterEnum(_ id: OSSignpostID) {
        os_signpost(.end, log: log, name: "ChapterEnum", signpostID: id)
    }
}
