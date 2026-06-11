# P1 Brief — AI Chat 原生研讨会

> 状态见 `../STATUS_zh.md`。DoD:`P1_ACCEPTANCE_zh.md` 十步在真机全部通过,由用户标 done。
> 最后更新:2026-06-11

## 目标形态(一段话,v2)

研讨会像普通工具一样被对话调用:用户在 AI Chat 里用自然语言提出"就 X 开个研讨",LLM 自主调用研讨工具,同一条聊天流里出现原生研讨卡并按默认配置自动开始;划线"研讨"和 `+ → AI 研讨会` 是辅助入口。运行中依次看到证据工具调用、角色 streaming 发言、分歧、总结,可卡内追问;**全程界面稳定不闪动**;证据可跳回书内原文。它给用户的感觉必须是"对话的一部分",不是"嵌在对话里的另一个小应用"。

## 边界与不做事项(v2,2026-06-11 用户决策)

- Seminar 不是 `Choose style` 的 prompt 风格。
- 角色只用只读工具;用户回复不自动当书内证据;无 SourceRef 的结论不得存为正式知识资产。
- **取消即终止,不做"继续研讨"/resume**(成本过高,用户拍板砍掉);取消后重新发起即可。
- 保存知识卡/异常送审等沉淀动作、杀进程历史恢复:**不作为 P1 gate**,坏了不修,留给 R2 后再评估。
- 自由多轮工具 loop、统一 streaming tool-call 组件、研讨结果回流主对话上下文 → R3。

## 当前切片队列(按序执行,一片一停)

### F1 运行期闪动+卡顿(最高优先级)
现象:运行中整个对话界面持续上下跳动、明显卡顿。
排查方向:partial/snapshot 每次更新是否触发整个 `AiChatStream` setState 重建;是否每次重建都强制 scroll-to-bottom(跳动直接原因);message part 列表是否每帧换 identity 导致 ListView 项重建;运行卡是否被 AnimatedSize/AnimatedSlide 包裹放大布局抖动。
修复要求:partial 文本更新节流(≤10次/秒);自动滚动只在"用户本就在底部且追加了新消息"时发生,in-place 更新不滚动;part/消息项用稳定 key;运行卡加 RepaintBoundary;局部重建(只重建运行中的卡)。
验收:验收脚本第 4 步。深层治本在 R1,本片只须把体验修到"不闪、可滚、不明显卡"。

### F2 打开来源不跳转
现象:点证据"打开来源",对话框滑动闪一下,不跳转书内原文。
排查方向:`ai_chat_stream.dart` 中 `readerSourceRef.canJumpBack || hasBookAnchor` 分支(约 5003 行)向下追:跳转请求是否真的传到阅读页/`epub_player`;AI 面板是 AnimatedSlide overlay,跳转时是否只收起了面板或只滚动了聊天列表;SourceRef 的 cfi/anchor 是否为空导致静默失败。
验收:验收脚本第 9 步;不可用证据必须显示原因。

### F3 `start_seminar` 工具(对话内发起,MVP)
仿照既有 `spawn_sub_agent` 工具的注册方式,新增只读工具 `start_seminar(question, 可选 scope 覆盖)`:LLM 在普通对话中可调用;行为 = 走 `openNativeSeminarCard(...)` 同一路径,用 Settings 默认角色配置写卡并自动开始,工具立即返回"研讨已发起"。
边界:权限矩阵禁止 Seminar 角色/子 agent 调用它(防递归);文案进 ARB;测试 = 工具 service 级测试 + 一个 widget smoke。结果回流主对话上下文是 R3 的事,本片不做。
验收:验收脚本第 1 步。

## 工作方式

- 一个切片 = 上面一个 F 项或一个新失败项。流程:复现 → grep 定位 → 最小修改 → `flutter analyze` + 最小测试子集 → `bash tool/check_repo_budgets.sh` → 更新 STATUS 行 → 停下等真机复测。
- F1 若发现治本必须大拆 widget,则停下来汇报,由用户决定是否提前启动 R1,不要在本片内顺手重构。

## 文件地图(改动入口,用 grep 定位细节)

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| `lib/widgets/ai/ai_chat_stream.dart` | ~17000 | 全部研讨卡 UI(R1 拆分对象;新代码禁止进入) |
| `lib/providers/ai_seminar_runtime.dart` | ~2700 | scoped runtime provider、snapshot 合并、历史加载 |
| `lib/service/ai/ai_seminar_runtime_service.dart` | ~2900 | 编排器:evidence broker、角色顺序、Director、checkpoint |
| `lib/models/ai_seminar.dart` / `ai_conversation_tree.dart` | ~1700/— | 模型与 message part(`AiSeminarRunCardMessagePart`) |
| `lib/service/ai/agent_run_graph_store.dart` | ~1200 | run graph 持久化(`.workflow/agent_runs_v1.json`) |
| `lib/service/ai/agent_run_event_message_part_adapter.dart` | ~1100 | event → message part replay |
| `test/ai_chat_stream_seminar_entry_test.dart` | ~19800 | widget 测试(R1 同步拆分对象) |

入口锚点:`reading_page.dart` `aiChat?.openSeminar(...)` → `ai_multi_tab_chat.dart` `openSeminar` → `openNativeSeminarCard`。

## 工作方式

- 唯一剩余工作:修真机验收失败项。一个失败项 = 一个切片。
- 修复切片流程:复现描述 → grep 定位 → 最小修改 → `flutter analyze` + 最小测试子集 → 更新 STATUS 行。
- 验收全过后,P1 冻结,转入 R1。
