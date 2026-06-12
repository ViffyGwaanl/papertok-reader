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

## 切片队列·第三轮(2026-06-12 三轮真机后;按 F9 → F10 → F11 → F12 → F13 执行,一片一停)

三轮结果:F4 开始瞬间抖动已修;F5/F6 部分生效但有漏改和行为错误;新增文本整洁与运行信息问题。

### F9 生成过程列表上下跳(F1/F4 残余,第三次迭代,最高优先级)
现象:开始瞬间已稳定,但 streaming 生成全程列表仍上下跳;对话式发起和手动开始两种入口都复现。
排查与方案(按序尝试):
1. 集中滚动控制:全文件只允许一个 autoscroll 入口;条件 = 用户视口距底部 <80px 且无进行中拖拽;streaming 期间用 `jumpTo` 不用 `animateTo`(动画叠加互相打架是跳动常见根因);不满足条件绝不滚动。
2. 仍跳则评估列表 `reverse: true` 重构(聊天标准做法,追加内容不位移已视内容);若涉及面过大,停下汇报——这是提前启动 R1 的信号。
3. 稳定 key;移除 streaming 卡上的 AnimatedSize 等隐式动画。
验收:两种入口发起,生成全程视口稳定;上滑浏览历史不被拉回。

### F10 读者动作行为修复 + 轮次上限放宽
现象:整理总结按下无反应;重新找证据触发整场重跑。
预期行为(写死):整理总结 = 立即触发 Director 总结生成/更新总结块;重新找证据 = 仅重新运行 evidence broker、更新证据块后继续当前研讨,不重启、不清空已有发言。
顺手:`maxRounds.clamp(1, 5)`(ai_seminar.dart:568、ai_seminar_config.dart:138)上限放宽到 10,默认仍 2。

### F11 展开一致性(F5 漏改)
仍点不开:分歧 tab 的"分歧扫描"、白板的"分歧继续讨论"、角色 tab 的各角色观点。
要求:所有 tab(全部/分歧/白板/角色)的长文本块统一可展开收起;建议抽一个共用的可展开文本组件放 `lib/widgets/ai/seminar/`,各处复用,消灭多套渲染路径漏改。

### F12 文本与引用整洁
- 裸 `(current-N)` 证据 id(来源:evidence broker `id: 'current-${n}'`)在角色发言/知识卡中:UI 渲染为可点证据角标(点击展开对应证据);保存知识卡时转为可读引用或附录,不得出现内部 id。
- 字面 `\n` 显示:定位未反转义的解析路径并修复。

### F13 运行追踪信息人话化
现象:"运行追踪/父运行"(ai_chat_stream.dart:11746/11766)直接显示 `seminar-tool-call-<uuid>` 等原始 run id。
要求:默认显示人类可读标签(如"本场研讨 · 批判者");原始 id 折叠进"调试详情"或仅 debug 模式显示。

---

## 切片队列·第二轮(已执行,留档;2026-06-11)

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
