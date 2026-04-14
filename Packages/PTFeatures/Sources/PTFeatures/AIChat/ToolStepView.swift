import SwiftUI
import PTAIServices
import PTUI

/// Displays a single tool call + its result in the chat message list.
///
/// States: pending -> running (spinner) -> completed / error.
/// Completed results render rich markdown content including code blocks and tables.
public struct ToolStepView: View {
    public enum ToolStepState: Sendable {
        case pending
        case running
        case completed(output: String)
        case failed(error: String)
    }

    let toolName: String
    let arguments: String
    let state: ToolStepState
    var duration: TimeInterval? = nil
    @State private var showDetails = false

    public init(toolName: String, arguments: String, state: ToolStepState, duration: TimeInterval? = nil) {
        self.toolName = toolName
        self.arguments = arguments
        self.state = state
        self.duration = duration
    }

    /// Maps tool names to semantic SF Symbols.
    private var semanticIcon: String {
        let n = toolName.lowercased()
        if n.contains("web_search") || n.contains("fetch_url") || n.contains("url") || n.contains("browser") { return "globe" }
        if n.contains("search") { return "magnifyingglass" }
        if n.contains("calendar") { return "calendar" }
        if n.contains("reminder") { return "checklist" }
        if n.contains("calculator") || n.contains("calc") || n.contains("math") { return "plus.slash.minus" }
        if n.contains("highlight") { return "highlighter" }
        if n.contains("note") { return "note.text" }
        if n.contains("memory") || n.contains("memor") { return "brain" }
        if n.contains("file") { return "doc.text" }
        if n.contains("write") || n.contains("create") { return "square.and.pencil" }
        if n.contains("time") || n.contains("date") { return "clock" }
        if n.contains("weather") { return "cloud.sun" }
        if n.contains("image") || n.contains("photo") { return "photo" }
        if n.contains("code") || n.contains("exec") { return "chevron.left.forwardslash.chevron.right" }
        if n.contains("translate") { return "character.bubble" }
        return "checkmark.circle.fill"
    }

    private var humanReadableName: String {
        AIToolPresentation.displayName(for: toolName)
    }

    private func formatDuration(_ d: TimeInterval) -> String {
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        return String(format: "%.1fs", d)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            stateIconWithBackground
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                HStack(spacing: AppSpacing.xs) {
                    Text(humanReadableName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Morandi.primaryText)

                    if case .running = state {
                        Text("common.running")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.accent)
                    } else if case .completed = state {
                        Text("common.done")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.sage)
                    } else if case .failed = state {
                        Text("intent.result.failed")
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.destructive)
                    }

                    if let duration {
                        Text(formatDuration(duration))
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Morandi.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Morandi.divider.opacity(0.4)))
                    }
                }

                if showDetails {
                    // Arguments (formatted JSON if possible)
                    Text(formattedArguments)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Morandi.secondaryText)
                        .padding(AppSpacing.xs)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Morandi.background)
                        )
                        .padding(.top, AppSpacing.xxs)

                    if case .completed(let output) = state, !output.isEmpty {
                        Divider()
                            .background(Morandi.divider)
                            .padding(.vertical, AppSpacing.xxs)

                        richResultView(output: output)
                    } else if case .failed(let error) = state {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(AppTypography.caption2)
                            Text(error)
                                .font(AppTypography.caption2)
                        }
                        .foregroundStyle(Morandi.destructive)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
            } label: {
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.cardBackground)
                .strokeBorder(Morandi.divider, lineWidth: 0.5)
        )
    }

    // MARK: - Rich Result Rendering

    @ViewBuilder
    private func richResultView(output: String) -> some View {
        let blocks = parseOutputBlocks(output)

        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(blocks.indices, id: \.self) { index in
                switch blocks[index] {
                case .text(let text):
                    Text(markdownAttributedString(text))
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                        .textSelection(.enabled)

                case .codeBlock(let language, let code):
                    VStack(alignment: .leading, spacing: 0) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Morandi.tertiaryText)
                                .padding(.horizontal, AppSpacing.xs)
                                .padding(.vertical, 2)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(code)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Morandi.primaryText)
                                .padding(AppSpacing.xs)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Morandi.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Morandi.divider, lineWidth: 0.5)
                    )

                case .table(let rows):
                    tableView(rows: rows)
                }
            }
        }
        .lineLimit(showDetails ? nil : 8)
    }

    @ViewBuilder
    private func tableView(rows: [[String]]) -> some View {
        if rows.isEmpty { EmptyView() } else {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows.indices, id: \.self) { rowIdx in
                        HStack(spacing: 0) {
                            ForEach(rows[rowIdx].indices, id: \.self) { colIdx in
                                Text(rows[rowIdx][colIdx])
                                    .font(rowIdx == 0 ? AppTypography.caption2.weight(.semibold) : AppTypography.caption2)
                                    .foregroundStyle(Morandi.primaryText)
                                    .padding(.horizontal, AppSpacing.xs)
                                    .padding(.vertical, 3)
                                    .frame(minWidth: 60, alignment: .leading)
                            }
                        }
                        if rowIdx == 0 {
                            Divider().background(Morandi.divider)
                        }
                    }
                }
                .padding(AppSpacing.xs)
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Morandi.background)
            )
        }
    }

    // MARK: - State Icon

    private var iconTint: Color {
        switch state {
        case .pending: return Morandi.tertiaryText
        case .running: return Morandi.accent
        case .completed: return Morandi.sage
        case .failed: return Morandi.destructive
        }
    }

    private var stateKey: String {
        switch state {
        case .pending: return "pending"
        case .running: return "running"
        case .completed: return "completed"
        case .failed: return "failed"
        }
    }

    private var stateIconWithBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(iconTint.opacity(0.15))
            Group {
                switch state {
                case .pending:
                    Image(systemName: "clock")
                case .running:
                    ProgressView().scaleEffect(0.7).tint(iconTint)
                case .completed:
                    Image(systemName: semanticIcon)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .foregroundStyle(iconTint)
            .font(.system(size: 14, weight: .semibold))
            .transition(.scale.combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: stateKey)
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        stateIconWithBackground
    }

    // MARK: - Formatting Helpers

    private var formattedArguments: String {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
              let result = String(data: pretty, encoding: .utf8) else {
            return arguments
        }
        return result
    }

    private func markdownAttributedString(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    // MARK: - Output Block Parsing

    private enum OutputBlock {
        case text(String)
        case codeBlock(language: String, code: String)
        case table(rows: [[String]])
    }

    private func parseOutputBlocks(_ output: String) -> [OutputBlock] {
        var blocks: [OutputBlock] = []
        var currentText = ""
        let lines = output.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Code block detection
            if line.hasPrefix("```") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Table detection (pipe-delimited)
            if line.contains("|") && line.trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                if !currentText.isEmpty {
                    blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
                    currentText = ""
                }
                var tableRows: [[String]] = []
                while i < lines.count {
                    let tableLine = lines[i].trimmingCharacters(in: .whitespaces)
                    guard tableLine.contains("|") else { break }
                    // Skip separator lines (|---|---|)
                    if tableLine.replacingOccurrences(of: "|", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ":", with: "")
                        .replacingOccurrences(of: " ", with: "")
                        .isEmpty {
                        i += 1
                        continue
                    }
                    let cells = tableLine
                        .split(separator: "|", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    if !cells.isEmpty {
                        tableRows.append(cells)
                    }
                    i += 1
                }
                if !tableRows.isEmpty {
                    blocks.append(.table(rows: tableRows))
                }
                continue
            }

            currentText += line + "\n"
            i += 1
        }

        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            blocks.append(.text(currentText.trimmingCharacters(in: .whitespacesAndNewlines)))
        }

        return blocks
    }
}
