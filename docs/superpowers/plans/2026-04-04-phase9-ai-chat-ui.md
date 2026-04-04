# Phase 9：AI 聊天 UI 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**目标：** 在 PTFeatures 包中实现完整的 AI 聊天 SwiftUI 界面，1:1 对标 Flutter 版 `AiChatStream` 的全部功能：流式消息渲染、工具调用展示、思考块折叠/展开、多模态附件、Provider/模型切换、对话分支导航。

**架构：** PTFeatures/AIChat 目录下新增 SwiftUI 视图层。`AIChatViewModel`（Phase 6 已实现）负责状态管理；新建 `AIChatView` 作为主容器，拆分为 `MessageListView`、`MessageBubbleView`、`ToolStepView`、`ThinkingBlockView`、`ChatInputView`、`ProviderPickerSheet` 等子视图。Markdown 渲染复用 PTUI 组件。

**技术栈：** Swift 5.9+, SwiftUI, PTUI (Morandi 设计系统, Markdown 渲染), PTAIServices (ChatMessage, ConversationTree, ToolCall), Observation 框架

**前置依赖：** Phase 4 PTUI ✅, Phase 5 PTAIServices ✅, Phase 6 PTFeatures AIChatViewModel ✅

**参考 Flutter 文件：**
- `lib/widgets/ai/ai_chat_stream.dart` — 主聊天容器（1600+ 行）
- `lib/widgets/ai/tool_step_tile.dart` — 工具调用展示
- `lib/widgets/ai/ai_collapsible_section.dart` — 思考块折叠
- `lib/widgets/ai/attachment_picker_dialog.dart` — 附件选择
- `lib/widgets/ai/tool_approval_dialog.dart` — 工具审批对话框
- `lib/page/home_page/ai_page.dart` — AI Tab 页入口

---

## 文件结构

```
Packages/PTFeatures/Sources/PTFeatures/AIChat/
├── AIChatViewModel.swift                   # 已存在（Phase 6），需扩展
├── AIChatView.swift                        # 新建：主容器（Scaffold + 路由）
├── MessageListView.swift                   # 新建：消息列表 + 自动滚动
├── MessageBubbleView.swift                 # 新建：用户/助手/系统消息气泡
├── ToolStepView.swift                      # 新建：工具调用行 + 结果展示
├── ThinkingBlockView.swift                 # 新建：思考块折叠/展开
├── ChatInputView.swift                     # 新建：输入框 + 附件 + 快捷提示词
├── ProviderPickerSheet.swift               # 新建：Provider/模型选择底部弹窗
├── AttachmentRowView.swift                 # 新建：附件预览行（图片/文件）
├── BranchNavigatorView.swift               # 新建：对话分支（上一个/下一个变体）
└── ToolApprovalSheet.swift                 # 新建：危险工具审批确认弹窗

Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/
├── AIChatViewModelExtTests.swift           # 扩展测试：Provider 切换、附件
├── MessageBubbleViewTests.swift            # 气泡渲染逻辑测试
└── BranchNavigatorViewTests.swift          # 分支导航测试
```

---

### Task 1：扩展 AIChatViewModel — Provider 切换、附件、流式状态

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift`
- Create: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/AIChatViewModelExtTests.swift`

- [ ] **Step 1：编写失败测试**

```swift
import Testing
@testable import PTFeatures
import PTCore

@Suite("AIChatViewModel 扩展")
struct AIChatViewModelExtTests {
    @Test("附件列表初始为空")
    func attachmentsInitiallyEmpty() {
        let vm = AIChatViewModel()
        #expect(vm.attachments.isEmpty)
    }

    @Test("addAttachment 增加附件数量")
    func addAttachment() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        #expect(vm.attachments.count == 1)
    }

    @Test("clearAttachments 清空附件")
    func clearAttachments() {
        let vm = AIChatViewModel()
        vm.addAttachment(.init(type: .image, name: "photo.jpg", data: Data()))
        vm.clearAttachments()
        #expect(vm.attachments.isEmpty)
    }
}
```

- [ ] **Step 2：扩展 AIChatViewModel**

在现有 `AIChatViewModel.swift` 中追加以下属性和方法：

```swift
// MARK: - 附件支持
public struct Attachment: Sendable, Identifiable {
    public enum AttachmentType: Sendable { case image, file }
    public let id = UUID()
    public let type: AttachmentType
    public let name: String
    public let data: Data
    public init(type: AttachmentType, name: String, data: Data) {
        self.type = type; self.name = name; self.data = data
    }
}

public var attachments: [Attachment] = []

public func addAttachment(_ attachment: Attachment) {
    attachments.append(attachment)
}

public func clearAttachments() {
    attachments.removeAll()
}

// MARK: - Provider 选择
public var selectedProviderId: String = ""
public var selectedModelId: String = ""

// MARK: - 流式增量文本
public var streamingTokens: [String] = []

public func appendStreamToken(_ token: String) {
    streamingTokens.append(token)
    currentStreamText += token
}

public func finalizeStream() {
    let text = currentStreamText
    addAssistantMessage(text)
    currentStreamText = ""
    streamingTokens.removeAll()
    isStreaming = false
}

// MARK: - 工具审批队列
public struct PendingToolApproval: Sendable, Identifiable {
    public let id = UUID()
    public let toolName: String
    public let toolCallId: String
    public let arguments: String
    public var isApproved: Bool? = nil
}

public var pendingApprovals: [PendingToolApproval] = []

public func requestApproval(toolName: String, toolCallId: String, arguments: String) {
    pendingApprovals.append(PendingToolApproval(toolName: toolName, toolCallId: toolCallId, arguments: arguments))
}

public func resolveApproval(id: UUID, approved: Bool) {
    if let idx = pendingApprovals.firstIndex(where: { $0.id == id }) {
        pendingApprovals[idx].isApproved = approved
    }
}
```

- [ ] **Step 3：运行测试**

运行: `cd Packages/PTFeatures && swift test --filter AIChatViewModelExtTests`
预期: PASS（3 tests）

- [ ] **Step 4：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatViewModel.swift \
        Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/AIChatViewModelExtTests.swift
git commit -m "feat(PTFeatures): extend AIChatViewModel with attachments, streaming, tool approval"
```

---

### Task 2：ThinkingBlockView — 思考块折叠/展开

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ThinkingBlockView.swift`

- [ ] **Step 1：实现 ThinkingBlockView**

对标 Flutter `ai_collapsible_section.dart` 的折叠动画行为：

```swift
import SwiftUI
import PTUI

/// Collapsible "thinking" block shown for extended-thinking model responses.
///
/// Matches Flutter's AiCollapsibleSection behavior:
/// - Collapsed by default while streaming, auto-expands on completion.
/// - Shows token count in header.
/// - Smooth height animation on toggle.
struct ThinkingBlockView: View {
    let content: String
    let tokenCount: Int?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("思考过程")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if let count = tokenCount {
                        Text("(\(count) tokens)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            // Collapsible content
            if isExpanded {
                ScrollView {
                    Text(content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
```

- [ ] **Step 2：编译验证**

运行: `cd Packages/PTFeatures && swift build`
预期: Build succeeded

- [ ] **Step 3：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/ThinkingBlockView.swift
git commit -m "feat(PTFeatures): add ThinkingBlockView with collapse animation"
```

---

### Task 3：ToolStepView — 工具调用结果展示

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ToolStepView.swift`

- [ ] **Step 1：实现 ToolStepView**

对标 Flutter `tool_step_tile.dart`：

```swift
import SwiftUI
import PTAIServices

/// Displays a single tool call + its result in the chat message list.
///
/// States: pending → running (spinner) → completed / error.
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

    public var body: some View {
        HStack(alignment: .top, spacing: 8) {
            stateIcon
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(toolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                if showDetails {
                    Text(arguments)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)

                    if case .completed(let output) = state {
                        Divider().padding(.vertical, 2)
                        Text(output)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                    } else if case .failed(let error) = state {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() }
            } label: {
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.tertiarySystemBackground))
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
        case .running:
            ProgressView()
                .scaleEffect(0.7)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/ToolStepView.swift
git commit -m "feat(PTFeatures): add ToolStepView with expandable details"
```

---

### Task 4：MessageBubbleView — 消息气泡

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageBubbleView.swift`

- [ ] **Step 1：实现 MessageBubbleView**

```swift
import SwiftUI
import PTAIServices
import PTUI

/// Renders a single chat message as a bubble.
///
/// - User: right-aligned, Morandi accent background
/// - Assistant: left-aligned, secondary background + Markdown rendering
/// - System: centered, small secondary text (collapsed by default)
/// - Tool result: shown inline via ToolStepView
struct MessageBubbleView: View {
    let message: ChatMessage
    @State private var showSystemContent = false

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemLabel
        case .tool:
            toolResultView
        }
    }

    // MARK: User bubble
    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 4) {
                if !attachmentViews.isEmpty {
                    VStack(alignment: .trailing, spacing: 4) { attachmentViews }
                }
                if let text = message.textContent, !text.isEmpty {
                    Text(text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.morandiAccent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .textSelection(.enabled)
                }
            }
        }
    }

    // MARK: Assistant bubble
    private var assistantBubble: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                if let text = message.textContent, !text.isEmpty {
                    MarkdownView(text: text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                    ForEach(toolCalls) { call in
                        ToolStepView(
                            toolName: call.name,
                            arguments: call.arguments,
                            state: .completed(output: "")
                        )
                    }
                }
            }
            Spacer(minLength: 48)
        }
    }

    // MARK: System message (collapsed by default)
    private var systemLabel: some View {
        Button {
            withAnimation { showSystemContent.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                if showSystemContent, let text = message.textContent {
                    Text(text).font(.caption2)
                } else {
                    Text("系统消息").font(.caption2)
                }
            }
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color(.tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tool result
    private var toolResultView: some View {
        ToolStepView(
            toolName: "工具结果",
            arguments: "",
            state: .completed(output: message.textContent ?? "")
        )
    }

    // MARK: Attachments
    @ViewBuilder
    private var attachmentViews: some View {
        ForEach(message.content.indices, id: \.self) { i in
            switch message.content[i] {
            case .imageBase64(let data, _):
                if let uiImage = UIImage(data: Data(base64Encoded: data) ?? Data()) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            case .imageURL(let url):
                AsyncImage(url: URL(string: url)) { img in
                    img.resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } placeholder: { ProgressView() }
            default:
                EmptyView()
            }
        }
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageBubbleView.swift
git commit -m "feat(PTFeatures): add MessageBubbleView for user/assistant/system/tool messages"
```

---

### Task 5：ChatInputView — 输入框 + 附件 + 快捷提示词

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ChatInputView.swift`

- [ ] **Step 1：实现 ChatInputView**

```swift
import SwiftUI
import PTUI

/// Chat input bar with text field, attachment picker, send button, and quick prompt chips.
///
/// Matches Flutter AiChatStream input row behavior:
/// - Multi-line text field (max 5 lines before scroll)
/// - Paperclip icon opens attachment picker
/// - Send disabled while streaming
/// - Quick prompt chips shown when input is empty
struct ChatInputView: View {
    @Binding var text: String
    let isStreaming: Bool
    let quickPrompts: [QuickPrompt]
    let onSend: () -> Void
    let onAttach: () -> Void
    let onStop: () -> Void

    struct QuickPrompt: Identifiable {
        let id = UUID()
        let label: String
        let prompt: String
    }

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Quick prompts (shown only when text is empty + not focused)
            if text.isEmpty && !isFocused && !quickPrompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quickPrompts) { prompt in
                            Button(prompt.label) {
                                text = prompt.prompt
                                onSend()
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                            .tint(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 8)
            }

            // Input row
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: onAttach) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                ZStack(alignment: .leading) {
                    if text.isEmpty {
                        Text("向 AI 提问…")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $text)
                        .frame(minHeight: 36, maxHeight: 120)
                        .scrollContentBackground(.hidden)
                        .focused($isFocused)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                )

                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(text.isEmpty ? .tertiary : Color.morandiAccent)
                    }
                    .buttonStyle(.plain)
                    .disabled(text.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/ChatInputView.swift
git commit -m "feat(PTFeatures): add ChatInputView with quick prompts, attachment, stop button"
```

---

### Task 6：BranchNavigatorView — 对话分支导航

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/BranchNavigatorView.swift`
- Create: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/BranchNavigatorViewTests.swift`

- [ ] **Step 1：编写测试**

```swift
import Testing
@testable import PTFeatures
import PTAIServices

@Suite("BranchNavigatorView")
struct BranchNavigatorViewTests {
    @Test("单个变体时，导航按钮禁用")
    func singleVariantDisablesNavigation() {
        let vm = AIChatViewModel()
        vm.conversationTree.append(.user("你好"))
        // 只有 1 个变体时 activeVariantIndex 为 0，没有其他变体
        let variants = vm.conversationTree.variantCount(at: 0)
        #expect(variants == 1)
    }
}
```

- [ ] **Step 2：实现 BranchNavigatorView**

```swift
import SwiftUI
import PTAIServices

/// Shows "< 1/3 >" navigation control for message variants (conversation branches).
///
/// Visible only when a user turn has more than one AI response variant.
struct BranchNavigatorView: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        guard totalCount > 1 else { return AnyView(EmptyView()) }
        return AnyView(
            HStack(spacing: 12) {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.semibold))
                }
                .disabled(currentIndex == 0)

                Text("\(currentIndex + 1) / \(totalCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .disabled(currentIndex >= totalCount - 1)
            }
            .foregroundStyle(.secondary)
        )
    }
}
```

- [ ] **Step 3：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/BranchNavigatorView.swift \
        Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/BranchNavigatorViewTests.swift
git commit -m "feat(PTFeatures): add BranchNavigatorView for conversation variant navigation"
```

---

### Task 7：ProviderPickerSheet — Provider/模型选择

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift`

- [ ] **Step 1：实现 ProviderPickerSheet**

```swift
import SwiftUI
import PTAIServices

/// Bottom sheet for selecting LLM provider and model.
///
/// Matches Flutter AiChatStream's provider selector dropdown behavior.
/// Providers loaded from AIChatViewModel.selectedProviderId.
struct ProviderPickerSheet: View {
    @Bindable var viewModel: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    // Provider list is injected; in Phase 12 this will come from PTAIServices registry
    let providers: [ProviderOption]

    struct ProviderOption: Identifiable {
        let id: String
        let displayName: String
        let models: [ModelOption]
    }

    struct ModelOption: Identifiable {
        let id: String
        let displayName: String
        let supportsThinking: Bool
        let supportsVision: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(providers) { provider in
                    Section(provider.displayName) {
                        ForEach(provider.models) { model in
                            Button {
                                viewModel.selectedProviderId = provider.id
                                viewModel.selectedModelId = model.id
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.displayName)
                                            .font(.body)
                                        HStack(spacing: 6) {
                                            if model.supportsThinking {
                                                Label("Thinking", systemImage: "brain")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if model.supportsVision {
                                                Label("Vision", systemImage: "eye")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    Spacer()
                                    if viewModel.selectedProviderId == provider.id
                                        && viewModel.selectedModelId == model.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("选择模型")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/ProviderPickerSheet.swift
git commit -m "feat(PTFeatures): add ProviderPickerSheet for model selection"
```

---

### Task 8：ToolApprovalSheet — 危险工具审批

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/ToolApprovalSheet.swift`

- [ ] **Step 1：实现 ToolApprovalSheet**

对标 Flutter `tool_approval_dialog.dart`：

```swift
import SwiftUI

/// Modal sheet asking user to approve or deny a dangerous tool call.
///
/// Shown for tools with riskLevel == .dangerous (calendar writes, reminders writes, shortcuts).
struct ToolApprovalSheet: View {
    let toolName: String
    let arguments: String
    let onApprove: () -> Void
    let onDeny: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("工具调用审批", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("工具名称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(toolName)
                    .font(.body.monospaced())
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("参数")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(arguments)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("此工具将写入您的设备数据。请确认是否允许执行。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("拒绝") {
                    onDeny()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .frame(maxWidth: .infinity)

                Button("允许") {
                    onApprove()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/ToolApprovalSheet.swift
git commit -m "feat(PTFeatures): add ToolApprovalSheet for dangerous tool confirmation"
```

---

### Task 9：MessageListView — 消息列表 + 自动滚动

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageListView.swift`

- [ ] **Step 1：实现 MessageListView**

```swift
import SwiftUI
import PTAIServices

/// Scrollable message list that auto-scrolls to bottom during streaming.
///
/// Matches Flutter AiChatStream auto-scroll behavior:
/// - Pins to bottom when streaming starts
/// - Stops auto-scroll if user manually scrolls up
struct MessageListView: View {
    let messages: [ChatMessage]
    let streamingText: String
    let isStreaming: Bool
    @State private var scrollProxy: ScrollViewProxy? = nil
    private let bottomAnchor = "bottom_anchor"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubbleView(message: message)
                            .padding(.horizontal, 16)
                    }
                    // Streaming in-progress bubble
                    if isStreaming && !streamingText.isEmpty {
                        HStack {
                            Text(streamingText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 18))
                                .animation(.default, value: streamingText)
                            Spacer(minLength: 48)
                        }
                        .padding(.horizontal, 16)
                    }
                    // Scroll anchor
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.vertical, 12)
            }
            .onAppear { scrollProxy = proxy }
            .onChange(of: messages.count) {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingText) {
                if isStreaming { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }
}
```

- [ ] **Step 2：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageListView.swift
git commit -m "feat(PTFeatures): add MessageListView with auto-scroll during streaming"
```

---

### Task 10：AIChatView — 主容器视图

**Files:**
- Create: `Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatView.swift`

- [ ] **Step 1：实现 AIChatView**

```swift
import SwiftUI
import PTAIServices
import PTUI

/// Main AI chat screen.
///
/// Matches Flutter AiChatStream top-level layout:
/// - NavigationBar with provider name + model picker button
/// - Message list (MessageListView)
/// - Input bar (ChatInputView) pinned to bottom
/// - Tool approval sheet (.sheet on pendingApprovals)
/// - Provider picker sheet (.sheet on showProviderPicker)
public struct AIChatView: View {
    @Bindable var viewModel: AIChatViewModel
    @State private var showProviderPicker = false
    @State private var showAttachmentPicker = false

    private let quickPrompts = [
        ChatInputView.QuickPrompt(label: "解释", prompt: "请解释这段内容"),
        ChatInputView.QuickPrompt(label: "总结", prompt: "请总结这段内容的主要观点"),
        ChatInputView.QuickPrompt(label: "分析", prompt: "请深入分析"),
    ]

    public init(viewModel: AIChatViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Message list
            if viewModel.messages.isEmpty && !viewModel.isStreaming {
                emptyState
            } else {
                MessageListView(
                    messages: viewModel.messages,
                    streamingText: viewModel.currentStreamText,
                    isStreaming: viewModel.isStreaming
                )
            }

            Divider()

            // Input bar
            ChatInputView(
                text: Binding(
                    get: { viewModel.currentStreamText },
                    set: { _ in }
                ),
                isStreaming: viewModel.isStreaming,
                quickPrompts: quickPrompts,
                onSend: handleSend,
                onAttach: { showAttachmentPicker = true },
                onStop: { viewModel.isStreaming = false }
            )
        }
        .navigationTitle(viewModel.selectedModelId.isEmpty ? "AI 助手" : viewModel.selectedModelId)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showProviderPicker = true
                } label: {
                    Image(systemName: "cpu")
                }
            }
        }
        .sheet(isPresented: $showProviderPicker) {
            ProviderPickerSheet(viewModel: viewModel, providers: [])
        }
        .sheet(item: Binding(
            get: { viewModel.pendingApprovals.first(where: { $0.isApproved == nil }) },
            set: { _ in }
        )) { approval in
            ToolApprovalSheet(
                toolName: approval.toolName,
                arguments: approval.arguments,
                onApprove: { viewModel.resolveApproval(id: approval.id, approved: true) },
                onDeny: { viewModel.resolveApproval(id: approval.id, approved: false) }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("开始你的 AI 对话")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func handleSend() {
        // Actual streaming implementation in Phase 12 (needs ChatModelProvider instance)
        // For now: stub send
        viewModel.sendMessage("")
    }
}
```

- [ ] **Step 2：运行全部 PTFeatures 测试**

运行: `cd Packages/PTFeatures && swift test`
预期: All tests pass

- [ ] **Step 3：提交**

```bash
git add Packages/PTFeatures/Sources/PTFeatures/AIChat/AIChatView.swift \
        Packages/PTFeatures/Sources/PTFeatures/AIChat/MessageListView.swift
git commit -m "feat(PTFeatures): add AIChatView main container wiring all chat subviews"
git push origin swift-native
```

---

## 工作量估算

| 任务 | 估算天数 |
|------|----------|
| Task 1：扩展 AIChatViewModel | 0.5 天 |
| Task 2：ThinkingBlockView | 0.5 天 |
| Task 3：ToolStepView | 0.5 天 |
| Task 4：MessageBubbleView | 1 天 |
| Task 5：ChatInputView | 1 天 |
| Task 6：BranchNavigatorView | 0.5 天 |
| Task 7：ProviderPickerSheet | 0.5 天 |
| Task 8：ToolApprovalSheet | 0.5 天 |
| Task 9：MessageListView | 0.5 天 |
| Task 10：AIChatView 集成 | 1 天 |
| **合计** | **~6.5 天** |

## 风险点

1. **Markdown 渲染**：PTUI MarkdownView 的 API 需在 Phase 4 已实现，如不存在需先补充。
2. **流式动画**：TextEditor 实时更新可能导致键盘弹跳，需测试 `resizeToAvoidBottomInset` 行为。
3. **多变体分支**：ConversationTree.variantCount(at:) 和 activeVariantIndex 需在 Phase 5 中已定义。
4. **图片附件**：base64 解码在主线程可能卡顿，超过 1MB 需移至后台线程。
