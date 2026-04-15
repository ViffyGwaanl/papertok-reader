import Foundation
import PTCore

public enum MemoryDocumentLocalization {
    public static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date) + ".md"
    }

    public static func date(fromFileName name: String) -> Date? {
        guard (name as NSString).pathExtension.lowercased() == "md" else {
            return nil
        }

        let stem = (name as NSString).deletingPathExtension
        guard stem.count == 10 else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: stem)
    }

    public static func displayTitle(
        forDocumentName name: String,
        kind: MemoryDocumentSummary.Kind? = nil,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        if kind == .longTerm || name == "MEMORY.md" {
            return longTermTitle(locale: locale)
        }

        if let date = date(fromFileName: name) {
            return dailyTitle(for: date, locale: locale)
        }

        return name
    }

    public static func dailyHeader(for date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        "# \(dailyTitle(for: date, locale: locale))\n\n"
    }

    public static func longTermHeader(locale: Locale = .autoupdatingCurrent) -> String {
        "# \(longTermTitle(locale: locale))\n\n"
    }

    public static func sessionDigestHeader(at date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        "\n\n## \(sessionDigestTitle(at: date, locale: locale))\n\n"
    }

    public static func contextHeader(locale: Locale = .autoupdatingCurrent) -> String {
        let title = AppLocalization.string(
            "memory.context.header_title",
            locale: locale,
            value: fallback(
                locale: locale,
                english: "Persistent memory context",
                simplifiedChinese: "记忆上下文",
                traditionalChinese: "記憶上下文"
            )
        )
        let body = AppLocalization.string(
            "memory.context.header_body",
            locale: locale,
            value: fallback(
                locale: locale,
                english: "The following notes were recorded in previous sessions. Use them to maintain continuity, but do not mention them unless relevant to the user's request.",
                simplifiedChinese: "以下内容记录于之前的会话中，可用于保持连续上下文；只有在与用户当前请求相关时才提及。",
                traditionalChinese: "以下內容記錄於之前的會話中，可用於保持連續上下文；只有在與使用者目前請求相關時才提及。"
            )
        )
        return "## \(title)\n\n\(body)\n\n"
    }

    public static func truncatedSuffix(locale: Locale = .autoupdatingCurrent) -> String {
        AppLocalization.string(
            "memory.context.truncated_suffix",
            locale: locale,
            value: fallback(
                locale: locale,
                english: "…(truncated)",
                simplifiedChinese: "…（已截断）",
                traditionalChinese: "…（已截斷）"
            )
        )
    }

    public static func digestLanguageInstruction(locale: Locale = .autoupdatingCurrent) -> String {
        fallback(
            locale: locale,
            english: "Write in English.",
            simplifiedChinese: "请使用简体中文。",
            traditionalChinese: "請使用繁體中文。"
        )
    }

    public static func transcriptRoleTitle(_ role: ChatRole, locale: Locale = .autoupdatingCurrent) -> String {
        switch role {
        case .system:
            return fallback(
                locale: locale,
                english: "System",
                simplifiedChinese: "系统",
                traditionalChinese: "系統"
            )
        case .user:
            return fallback(
                locale: locale,
                english: "User",
                simplifiedChinese: "用户",
                traditionalChinese: "使用者"
            )
        case .assistant:
            return fallback(
                locale: locale,
                english: "Assistant",
                simplifiedChinese: "助手",
                traditionalChinese: "助理"
            )
        case .tool:
            return fallback(
                locale: locale,
                english: "Tool",
                simplifiedChinese: "工具",
                traditionalChinese: "工具"
            )
        }
    }

    private static func dailyTitle(for date: Date, locale: Locale) -> String {
        let dateText = date.formatted(
            Date.FormatStyle()
                .year()
                .month()
                .day()
                .locale(locale)
        )
        return AppLocalization.format(
            "memory.document.daily_title_format",
            fallback: fallback(
                locale: locale,
                english: "Daily memory · %@",
                simplifiedChinese: "每日记忆 · %@",
                traditionalChinese: "每日記憶 · %@"
            ),
            locale: locale,
            dateText
        )
    }

    private static func longTermTitle(locale: Locale) -> String {
        AppLocalization.string(
            "memory.document.long_term_title",
            locale: locale,
            value: fallback(
                locale: locale,
                english: "Long-term memory",
                simplifiedChinese: "长期记忆",
                traditionalChinese: "長期記憶"
            )
        )
    }

    private static func sessionDigestTitle(at date: Date, locale: Locale) -> String {
        let timeText = date.formatted(
            Date.FormatStyle()
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(locale)
        )
        return AppLocalization.format(
            "memory.document.session_digest_title_format",
            fallback: fallback(
                locale: locale,
                english: "Session digest · %@",
                simplifiedChinese: "会话摘要 · %@",
                traditionalChinese: "會話摘要 · %@"
            ),
            locale: locale,
            timeText
        )
    }

    private static func fallback(
        locale: Locale,
        english: String,
        simplifiedChinese: String,
        traditionalChinese: String
    ) -> String {
        if isTraditionalChinese(locale) {
            return traditionalChinese
        }
        if isChinese(locale) {
            return simplifiedChinese
        }
        return english
    }

    private static func isChinese(_ locale: Locale) -> Bool {
        locale.identifier.lowercased().hasPrefix("zh")
    }

    private static func isTraditionalChinese(_ locale: Locale) -> Bool {
        let identifier = locale.identifier.lowercased()
        return identifier.hasPrefix("zh")
            && (
                identifier.contains("hant")
                    || identifier.contains("tw")
                    || identifier.contains("hk")
                    || identifier.contains("mo")
            )
    }
}

public extension MemoryDocumentSummary {
    func displayTitle(locale: Locale = .autoupdatingCurrent) -> String {
        MemoryDocumentLocalization.displayTitle(
            forDocumentName: name,
            kind: kind,
            locale: locale
        )
    }
}

public extension MemorySearchResult {
    func displayTitle(locale: Locale = .autoupdatingCurrent) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return MemoryDocumentLocalization.displayTitle(
            forDocumentName: name,
            locale: locale
        )
    }
}
