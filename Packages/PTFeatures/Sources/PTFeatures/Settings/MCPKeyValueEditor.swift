import SwiftUI
import PTUI

struct KeyValueRow: Identifiable, Hashable {
    let id: UUID
    var key: String
    var value: String

    init(id: UUID = UUID(), key: String = "", value: String = "") {
        self.id = id
        self.key = key
        self.value = value
    }

    static func rows(from dict: [String: String]) -> [KeyValueRow] {
        dict.sorted { $0.key < $1.key }.map { KeyValueRow(key: $0.key, value: $0.value) }
    }

    static func dictionary(from rows: [KeyValueRow]) -> [String: String] {
        var result: [String: String] = [:]
        for row in rows where !row.key.isEmpty {
            result[row.key] = row.value
        }
        return result
    }
}

struct KeyValueEditor: View {
    let title: String
    let addLabel: String
    let keyPlaceholder: String
    let valuePlaceholder: String
    @Binding var rows: [KeyValueRow]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(title)
                .font(AppTypography.caption)
                .foregroundStyle(Morandi.secondaryText)
            ForEach($rows) { $row in
                HStack {
                    TextField(keyPlaceholder, text: $row.key)
                        .autocorrectionDisabled()
                    TextField(valuePlaceholder, text: $row.value)
                        .autocorrectionDisabled()
                    Button {
                        rows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(Morandi.destructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                rows.append(KeyValueRow())
            } label: {
                Label(addLabel, systemImage: "plus.circle")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.accent)
            }
            .buttonStyle(.plain)
        }
    }
}
