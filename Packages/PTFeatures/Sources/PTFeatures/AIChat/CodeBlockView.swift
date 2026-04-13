import SwiftUI
import PTUI

/// Rich code block with language label, copy button, horizontal scroll,
/// monospaced font, and lightweight syntax highlighting for common languages.
struct CodeBlockView: View {
    let language: String
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                Text(highlighted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Morandi.primaryText)
                    .padding(AppSpacing.md)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .fill(Morandi.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall)
                .strokeBorder(Morandi.divider, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            Text(language.isEmpty ? "code" : language.lowercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Morandi.tertiaryText)
            Spacer()
            Button {
                copy()
            } label: {
                HStack(spacing: AppSpacing.xxs) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    Text(copied ? "Copied" : "Copy")
                }
                .font(AppTypography.caption2)
                .foregroundStyle(copied ? Morandi.sage : Morandi.secondaryText)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Morandi.divider.opacity(0.35))
    }

    private func copy() {
        #if os(iOS)
        UIPasteboard.general.string = code
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
        withAnimation(.easeInOut(duration: 0.2)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation { copied = false }
        }
    }

    // MARK: - Syntax Highlighting

    private var highlighted: AttributedString {
        var attr = AttributedString(code)
        attr.foregroundColor = Morandi.primaryText

        let lang = language.lowercased()
        let keywords: [String]
        switch lang {
        case "swift":
            keywords = ["func","let","var","if","else","guard","return","import","struct","class","enum","protocol","extension","public","private","internal","async","await","throws","try","self","init","nil","true","false","for","in","while","switch","case","default","break","continue","where","do","catch","throw"]
        case "python", "py":
            keywords = ["def","class","if","elif","else","return","import","from","as","for","while","in","not","and","or","is","None","True","False","pass","break","continue","try","except","raise","with","yield","lambda","async","await","global","nonlocal"]
        case "js","javascript","ts","typescript":
            keywords = ["function","const","let","var","if","else","return","import","from","export","class","extends","new","this","async","await","for","while","switch","case","default","break","continue","try","catch","throw","finally","null","undefined","true","false","typeof","instanceof"]
        case "json":
            keywords = ["true","false","null"]
        default:
            return applyStrings(to: attr)
        }

        // Keywords
        for kw in keywords {
            let regex = try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: kw))\\b")
            apply(regex: regex, to: &attr, color: Morandi.dustyRose, bold: true)
        }
        // Strings
        let stringRegex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"")
        apply(regex: stringRegex, to: &attr, color: Morandi.moss, bold: false)
        // Line comments
        let commentRegex = try? NSRegularExpression(pattern: "//[^\n]*")
        apply(regex: commentRegex, to: &attr, color: Morandi.tertiaryText, bold: false)
        let hashComment = try? NSRegularExpression(pattern: "#[^\n]*")
        if lang == "python" || lang == "py" {
            apply(regex: hashComment, to: &attr, color: Morandi.tertiaryText, bold: false)
        }
        // Numbers
        let numberRegex = try? NSRegularExpression(pattern: "\\b\\d+(?:\\.\\d+)?\\b")
        apply(regex: numberRegex, to: &attr, color: Morandi.powder, bold: false)
        return attr
    }

    private func applyStrings(to attr: AttributedString) -> AttributedString {
        var result = attr
        let stringRegex = try? NSRegularExpression(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"")
        apply(regex: stringRegex, to: &result, color: Morandi.moss, bold: false)
        return result
    }

    private func apply(regex: NSRegularExpression?, to attr: inout AttributedString, color: Color, bold: Bool) {
        guard let regex else { return }
        let nsString = code as NSString
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsString.length))
        for match in matches {
            guard let range = Range(match.range, in: code),
                  let attrRange = attr.range(of: String(code[range])) else { continue }
            attr[attrRange].foregroundColor = color
            if bold {
                attr[attrRange].font = .system(.caption, design: .monospaced).weight(.semibold)
            }
        }
    }
}
