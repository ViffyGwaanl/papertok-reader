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

## 切片队列·第四轮(2026-06-12 四轮真机后;按 F14 → F15 → F16 → F17 执行,一片一停)

历史轮次结果:一轮修入口/跳转/工具发起;二轮修展开/动作/轮次/查看入口(部分);三轮治好滚动跳动(F9 ✓)、文本整洁部分生效。当前痛点:读者参与模块整体混乱(用户拍板重构)、展开覆盖两轮漏改、证据编号对不上、滚动疲劳。

### F14 读者参与重构:"聊天即参与"(核心,允许拆 2 个 commit:UI / 行为接线)

产品决策(用户 2026-06-12 拍板):现有"动作单选 + 文本框 + 执行选中动作"表单和"回应角色"弹窗整体废弃;机制黑话按钮(让角色反驳/已有证据分歧/优先处理反驳等)全部删除。读者参与 = 插话、要求继续、要总结三件事。

新交互 spec:
1. 研讨卡底部常驻**参与区**(运行中与完成态都显示):
   - 一行快捷 chips:「继续讨论」「换个角度看」「补充证据」「出总结」——全部一键执行,无需文本;点击后 chip 变执行中态,产出块出现后自动滚到该块。
   - 一个单行输入框,placeholder"说点什么,引导这场研讨…",右侧发送键;发送后默认由主持人(Director)分配角色回应;输入框左侧可选目标角色下拉,默认"主持人分配"。
2. 分歧块动作收敛为两个 chips:「就这点继续讨论」(预填输入框"围绕这条分歧继续:…",用户可改后发送)、「找证据验证」(一键,带分歧上下文补充证据)。
3. 行为语义(写死):「出总结」= 立即触发 synthesis,研讨流出现"正在整理总结…"状态块,完成后更新总结块并滚到该处(按下必须有即时可见反馈);「补充证据」= 只重跑 evidence broker,状态文案"正在补充证据,已有发言保留",证据块更新后继续讨论,**禁止**复用"开始研讨"进度文案,禁止视口闪跳。
4. 运行控制(暂停/取消/角色控制)固定在研讨卡 header(sticky),不得随内容流动(当前漂在流中间,完全不可用)。
5. 首次使用 hint(可关闭,记偏好):"你可以随时插话、补充证据或要求总结"。
6. 文案表:重新找证据→补充证据;整理总结→出总结;发送我的回复→发送;等待工具调用→证据检索中…;其余机制词不再出现。
7. 实现约束:新组件全部进 `lib/widgets/ai/seminar/composer/`;删除 ai_chat_stream.dart 内旧 composer/弹窗渲染分支(本片应让 god file 净缩);复用既有 runUserDirectedRole / evidence broker 续跑 / synthesis 触发 API。

### F15 证据编号对账
证据快照每条显示编号(证据1、证据2…,与 broker `current-N` 一一对应);角色发言中的"证据N"角标可点击,点击展开/跳到对应证据条目。知识卡保存时引用仍转可读文本。

### F16 展开覆盖穷举(两轮漏改,最后一次)
仍不可展开:研讨总结、异常 tab 综合总结、知识卡候选明细、候选证据。
要求:不再逐点打补丁——grep 穷举所有渲染长文本的 tile,列清单逐一接入共用可展开组件,commit 正文附穷举清单和已接入清单。

### F17 快速滚动
聊天列表加"回到底部"悬浮按钮(用户向上滑时出现;有新内容时带提示点),长按或附加"回到顶部"。

---

## 历史队列(一至三轮,已执行,详情见 git log 与验收失败表)

F1–F13 详情不再在本文件保留;每片对应一个 commit(git log 可查),失败现象见 `P1_ACCEPTANCE_zh.md` 失败记录表。F6 的"四动作"交互已被第四轮 F14"聊天即参与"设计取代。

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
