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

## 切片队列·第二轮(2026-06-11 二轮真机后;按 F5 → F6 → F4 → F7 → F8 执行,一片一停)

第一轮结果:F2 来源跳转、F3 start_seminar 已通过;F1 大幅改善,残余开始瞬间抖动(转 F4)。

### F5 白板/分歧/角色观点内容截断且不可展开
现象:三类块能显示但内容不全,点击无反应(当前实现就是只读截断摘要,没挂展开手势,不是用户操作问题)。
锚点:whiteboard entries 渲染 ~3824/4404;`disagreement`/`role_turn` tiles。
要求:默认摘要,点击内联展开全文(不开新页),可收起;长文本可滚动、可选择复制。

### F6 读者参与动作解耦(composer 交互重做)
锚点:action ids `ask-role`/`refresh-evidence`/`synthesize` @3257–3262,执行按钮文案 @8206,handlers @13971/14153 起。
现状问题:三个动作都强制填"我的研讨回复"才能执行。
新交互:四个动作——让角色回应(给角色的话**可选填**)、重新找证据(**一键**,无需文本)、整理总结(**一键**,无需文本)、**发送我的回复**(新增,必须填文本,作为读者观点进入研讨记录)。执行按钮文案随所选动作变化;移除全局强制文本校验;文案进 ARB。

### F4 开始研讨瞬间整屏左右抖动(F1 残余)
现象:点"开始研讨"瞬间整界面左右抖一下,之后稳定。
排查:setup 态卡 → running 态卡切换是否同帧发生宽度/约束突变(按钮行、padding 变化);是否插入新 part 触发整列表重布局。
要求:状态切换无可感知水平位移(固定宽度约束或淡入过渡)。

### F7 全局默认轮次设置缺失
锚点:`lib/page/settings_page/ai_seminar_config.dart`(grep maxRounds 无结果,确实没暴露)。
要求:Settings → Seminar settings 增加全局默认最大轮次(及其它合理默认);与每场"调整设置"是默认值/单次覆盖关系,文案说清。

### F8 保存知识卡后给"查看"入口
锚点:保存提示 `knowledgeCardSavedInline` @app_zh.arb:110;`artifact_actions` part ~3924。
要求:保存知识卡/编辑后保存成功后,提示或块内出现"查看知识卡"动作,点击跳到该知识卡详情;加入复习/加入图谱可同样处理(低优先,知识卡必做)。

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
