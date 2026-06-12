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

## 收口队列·第五轮(2026-06-12;只剩 F19,完成后 P1 进入最终验收)

五轮判定(用户 + 规划者一致):读者参与层(F6→F10→F14)五次返工未稳,根因是结构性的——reader 输入要穿过 UI/scoped provider/runtime service 三层状态机和 snapshot+event 双数据路径,且其正确形态(主输入框参与、上下文统一)架构上属于 R3。**决策:参与层冻结,P1 以"观看+追问"形态收口;实时参与在 R3 以新架构重生。**

### F19 P1 收口片(允许拆 2 个 commit:a 回流 / b 冻结)

**F19a 研讨结论回流主对话上下文(最小版)**
锚点:`lib/providers/ai_chat.dart` `_buildPromptMessagesForAssistantParent`(~845 行);研讨数据在 segment meta 的 `seminarRunCard.snapshot`。
要求:completed 研讨卡在主对话 LLM 历史中注入一段结论文本:研讨问题、最终总结、主要分歧条目、关键证据编号与出处;总长封顶(约 1500 token,超出截断,总结优先);running/cancelled 卡注入一行状态说明即可。
验收:研讨完成后在主输入框追问研讨内容,AI 回答能引用总结与分歧;无研讨的对话行为不变。

**F19b 冻结参与层**
要求:移除研讨卡内参与输入框、角色下拉、发送按钮、快捷 chips 和分歧块动作 chips(渲染分支删除,不是 disable);参与区位置替换为一行静态引导文案(ARB):"研讨结束后,可直接在下方对话框继续追问";暂停/取消保留在卡 header;删除现已无入口的死代码路径(composer 相关 handler),god file 应净缩。
验收:卡内不存在任何可点但无反应的参与控件;引导文案出现;主输入框追问可用(走 F19a)。

### P1 最终验收
F19 合入后,用户跑 `P1_ACCEPTANCE_zh.md` v6 全量(预计 15 分钟),全过则 P1 标 done,立即启动 R1。

---

## 历史队列(一至四轮,已执行,详情见 git log 与验收失败表)

F1–F18 详情不再在本文件保留;每片对应一个 commit(git log 可查),失败现象见 `P1_ACCEPTANCE_zh.md` 失败记录表。参与层演化史:F6 四动作 → F14"聊天即参与"卡内参与区 → 五轮判定冻结(F19b),正确形态移交 R3。

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
