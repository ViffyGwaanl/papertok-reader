import SwiftUI
import PTAIServices
import PTUI

/// Displays a single tool call + its result in the chat message list.
///
/// States: pending -> running (spinner) -> completed / error.
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
    @State private var showDetails = false

    public init(toolName: String, arguments: String, state: ToolStepState) {
        self.toolName = toolName
        self.arguments = arguments
        self.state = state
    }

    public var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            stateIcon
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(toolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Morandi.primaryText)

                if showDetails {
                    Text(arguments)
                        .font(AppTypography.caption2)
                        .foregroundStyle(Morandi.secondaryText)
                        .padding(.top, AppSpacing.xxs)

                    if case .completed(let output) = state {
                        Divider()
                            .background(Morandi.divider)
                            .padding(.vertical, AppSpacing.xxs)
                        Text(output)
                            .font(AppTypography.caption2)
                            .foregroundStyle(Morandi.secondaryText)
                            .lineLimit(5)
                    } else if case .failed(let error) = state {
                        Text(error)
                            .font(AppTypography.caption2)
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

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(Morandi.tertiaryText)
        case .running:
            ProgressView()
                .scaleEffect(0.7)
                .tint(Morandi.accent)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Morandi.sage)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Morandi.destructive)
        }
    }
}
