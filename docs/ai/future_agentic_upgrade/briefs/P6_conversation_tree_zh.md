# P6 Brief — AI Chat 多分支对话树状可视化

> 前置:R1 已收口(Seminar 渲染视图已独立)。状态见 `../STATUS_zh.md`。
> DoD:聊天界面有入口按钮打开对话树浮层;树按真实分支结构渲染,每条消息一个节点(发言方+首句摘要),当前活跃路径整条高亮;点任一节点即切换到该分支并关闭浮层;真机验收(本文件 §验收)通过。
> 用户拍板形态(2026-06-17,一比一实现不留发挥):①入口 = 顶部按钮弹出浮层;②节点 = 每条消息一节点 + 首句摘要 + 当前分支高亮。

## 目标形态(一段话)

普通 AI Chat 顶部加一个小按钮(分支树图标);点击弹出一张浮层,把当前对话的完整分支结构画成自上而下的树:每个节点是一条消息,显示发言方(你 / AI)+ 开头一句摘要;当前所走的活跃路径整条高亮。点击任一节点,对话即切换到经过该节点的分支(把该节点设为其各级祖先的活跃子节点),浮层关闭、聊天回到该分支最新一条;点空白处或关闭按钮收起。**只读 + 切换,不在树上编辑/删除消息**。

## 数据与锚点

- 数据源:`lib/providers/ai_chat.dart` 私有 `_tree`(`AiConversationTree`)。**需新增只读 getter 暴露树**给 UI。
- 模型:`lib/models/ai_conversation_tree.dart` —— `AiConversationTree{rootId, nodes}`;`AiConversationNode{id, parentId, children, activeChildId, message, ...}`;活跃路径 = 从 root 顺 `activeChildId`;切分支 = `setActiveChild(parentId, childId)`。
- 切换落地:provider 需新增"激活到某节点路径"方法(沿该节点到 root 逐级 `setActiveChild`)+ 持久化,复用既有 `switchVariantAtMessageIndexAndPersist` 的持久化模式(`conversationV2: _tree.toJson()`)。
- 节点摘要:取 `node.message` 文本首句/首行(截断);发言方由 message 类型(human/ai)判定;沿用 P1 文本清洗(无裸 id、无字面 \n)。

## 边界与不做

- 只读 + 切分支;不在树上编辑、重生成、删除节点(那些走现有聊天交互)。
- 仅当前会话的树,不跨会话。
- 新 UI 代码进 `lib/widgets/ai/conversation_tree/`;god file 只加最小入口钩子(按钮 + 打开浮层),保持在 baseline 16620 以下,能不涨尽量不涨。
- 浮层用 `pointer_interceptor`(在 WebView 之上);配色走 Claude palette;所有文案进 ARB(en/zh)。

## 批次(每批一切片一 commit)

1. **树数据适配**:纯函数把 `AiConversationTree` 转成可渲染结构(节点列表 + 父子关系、发言方、首句摘要、isOnActivePath);单测覆盖空树/单节点/多分支/深路径。新文件 `conversation_tree/conversation_tree_model.dart`。
2. **provider 暴露**:加只读 `conversationTree` getter + `activatePathToNode(nodeId)`(逐级 `setActiveChild`)+ 持久化;provider 测试覆盖切换后活跃路径正确、持久化生效。
3. **浮层渲染(只读)**:`ConversationTreeOverlay`(自上而下树状布局、活跃路径高亮、长会话可滚动),先不接交互;widget 测试 pump 各形态。新文件 `conversation_tree/conversation_tree_overlay.dart`。
4. **入口 + 切换**:god file 顶部加按钮打开浮层;节点点击 → `activatePathToNode` → 关闭浮层 → 聊天跳该分支最新;widget/集成测试。

> 批次 1–4 跑完停下报告(逐批 commit、god file 行数、测试结果),等规划者审 + 用户真机看一眼;之后再发批次 5 收尾(空/单节点态、手机尺寸、ARB、配色微调)。

## 验收(真机,用户执行)

1. 多分支对话(对某条消息重新生成或编辑,分叉出多个版本)后点顶部按钮,浮层弹出,树结构与实际分支一致。
2. 每个节点显示发言方 + 首句摘要;当前所在分支整条高亮。
3. 点一个非当前分支的节点:浮层关闭,聊天切到该分支,内容正确。
4. 长对话树可上下滚动;点空白/关闭按钮收起;手机上不挤、可用。
5. 普通单线对话(无分支)打开树也正常(一条线),无报错。

## 工作方式

- 一批一切片一 commit:`feat(chat-tree): <批次> (P6 batch N)`;每批 `flutter analyze` 无新增 + `flutter test` + `bash tool/check_repo_budgets.sh` 全过再停。
- 批次 1–2(数据 + provider)无 UI 风险可连做;批次 3–4 出 UI;做完 4 停,等审 + 真机。
