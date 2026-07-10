# 状态表(唯一)

> 规则:每个切片只改本表对应行;状态只有 backlog / in progress / 待真机验收 / done;done 只能由用户标。
> 最后更新:2026-07-09(新增 S1 数据完整性线,冻结规则例外,见 `EXPERIENCE_REBUILD_PLAN_zh.md`)

| 任务 | 内容 | 状态 | 下一步 | 验收/Brief |
| --- | --- | --- | --- | --- |
| S1 | 数据完整性与崩溃修复(全新安装无法存高亮/笔记、WebDAV 同步丢数据、TTS/书架崩溃、AI历史损坏即删库) | 待真机验收(批次1/2/3/5) | 批次1/2/3/5 已实现+测试(分支 claude/s1-batches);仅剩批次4(WebDAV)——开工前需用户对合并策略拍板 | `briefs/S1_data_integrity_zh.md` |
| S2 | 核心能力缺口(PDF对全部AI取证工具静默空内容、KnowledgeCard本体无主页存卡即消失) | 待真机验收(批次2) | 批次2 已实现(列表页在"我的",详情页补跳转来源/提交审核/删除);批次1(PDF)待做 | `briefs/S2_core_capability_gaps_zh.md` |
| S3 | 信任快赢集(研讨成本显示、CBZ放行、隐私可见化、零配置查词) | backlog | 不单独出包,随 S1/S2/P6 验收 build 搭车;批次4入口位置服从 E4 决策清单 | `briefs/S3_trust_quick_wins_zh.md` |
| P7 | Android 平台启用(系统性回归+Google Play/APK 发布;用户拍板不上大陆商店) | backlog | S1 批次1 落地后开工;批次1 按 ANDROID_QA_CHECKLIST 全量回归 | `briefs/P7_android_enablement_zh.md` |
| E5 | 无障碍基线(Semantics 覆盖、VoiceOver 阅读面、图标 tooltip) | backlog | 重建期后;开工前写 brief(首片:选区菜单+图标按钮语义标签;阅读面 VoiceOver 模式单列) | 开工前写 brief |
| P1 | AI Chat 原生研讨会(收口为"观看+追问"形态) | done | 真机 v6 全量通过(2026-06-17,build 6533),用户确认收口;详见验收记录 | `briefs/P1_ACCEPTANCE_zh.md`(v6) |
| R1 | 拆分 ai_chat_stream.dart god file | done | Seminar 渲染视图全部抽至 seminar/(各≤787、83 测试、纯机械);god file 16618→11667。用户拍板收口(2026-06-17),原 ≤3000 目标作废、改为现实 DoD(见 brief);深拆 State 留作未来重构 | `briefs/R1_godfile_split_zh.md` |
| R2 | 事件流单一数据源,删 snapshot 双写与 fallback | backlog | A 线第一步;第一批产出删除清单 ADR;旧研讨历史方向=放弃不迁移(2026-07-03 用户授权,开工时确认) | `briefs/R2_event_ssot_zh.md` |
| R3 | Seminar 并入 sub-agent 平台(原 P1.5/S7) | backlog | R2 后;自由工具 loop、统一 streaming 组件、**读者参与重生(主输入框路由,P1 冻结移交)**在此实现 | `briefs/R3_agent_platform_merge_zh.md` |
| P2 | Understand-Anything 式全书 AI 理解地图 | backlog | R1–R3 完成后,开工前重写 brief;重写时差异化叙事改打"跳回原书锚点+对抗式多角色"(引用溯源已被 NotebookLM 变为免费标配);前置补 S2 批次1(PDF 取文原语) | 旧版 `priority_plans/P2_*.md` 仅作参考 |
| P3 | 智能索引/语义检索/ANN 底座 | backlog(暂停) | 生产级 ANN 打包、恢复式构建并入 R2 之后评估 | `priority_plans/P3_*.md` |
| P4 | AI 辅助产物保存与 Review 异常中心 | backlog(暂停) | 内联保存已可用;AI 预审并入 P2 之后评估 | `priority_plans/P4_*.md` |
| P5 | 同步/恢复/测试/发布 | in progress(按发布节奏) | 每次 release 跟随既有 SOP | `docs/SOP_RELEASE_AUTOMATION_zh.md` |
| P6 | AI Chat 多分支对话树状可视化(呈现多分支对话结构,可点击切分支) | 待真机验收 | 批次 1–4 规划者审过(纯净:新码在 conversation_tree/、provider+5/god file+33、5 测试);待含 P6+B1 的新 build 真机验收(brief §验收 5 项),过后做批次 5 收尾 | `briefs/P6_conversation_tree_zh.md` |
| B1 | 阅读器选区扩展后高亮/AI 研讨仍只用首次选区(iOS 触屏拖手柄扩展不重发选区) | 待真机验收 | 规划者审过(只动 book.js+测试,修法正确,index.html 确认走 src 无需重打包);待同一新 build 真机验收三项 | chat 指令 / `assets/foliate-js/src/book.js` |
| E1 | AI Chat 流式渲染局部化(消息级重建,根治生成期抖动) | backlog | R2 后、R3 前(A 线第二步);批次 1 先立 rebuild 探针靶子测试 | `briefs/E1_chat_render_locality_zh.md` |
| E2 | 阅读翻译体验简化(自动重试、人话提示、收纳工程仪表) | backlog | 可与 A 线并行(文件不相交);批次 1 自动重试 | `briefs/E2_translate_ux_simplify_zh.md` |
| E3 | 全局糙感清扫(zh 漏翻 372、裸错误文案 71 处、双击回顶、PaperTok 首屏) | 待真机验收 | 批次 1:zh 缺失已清零,待真机抽查;下一步批次 2 裸错误文案人话化;批次 5 等用户 E0 走查输入 | `briefs/E3_polish_sweep_zh.md` |
| E4 | 减法与聚焦(7 tab→4、设置树收纳、选区菜单 9→5) | in progress | 批次 2/3 已实现(4 tab+我的;极客入口收进开发者选项,图片分析降入 AI 设置);下一步批次 4 选区菜单 | `briefs/E4_subtraction_focus_zh.md` |
| G1a | 分享资产:书摘卡 2.0、读书报告(不含实录长图) | backlog | 不受冻结规则约束,可直接开工(2026-07-09 复核:不碰高风险文件、无R2/R3依赖);开工前用户拍板水印/二维码 | `briefs/G1_share_artifacts_zh.md` |
| G1b | 分享资产:研讨会实录长图 | backlog | 依赖 R2 后干净事件流,维持原排期 | `briefs/G1_share_artifacts_zh.md` |
| G2 | 每日回顾循环(本地通知 + 记忆间隔重复回顾) | backlog | 重建期收口后,可与 G1 并行;通知权限时机开工前拍板 | `briefs/G2_daily_review_loop_zh.md` |
| G0/G3/G5 | 零配置首航 / 研讨播客 / PaperTok 日报 | backlog | 见 `GROWTH_PLAN_zh.md`;G0 商业形状已拍板(免费额度代理,不做订阅);各自开工前重写为 brief | `GROWTH_PLAN_zh.md` |
| G4a | 跨书馆长轻量 MVP(记忆正文戳书名 + prompt 引导 + 跨书引用角标) | backlog | 与 R3 正交,重建期后可与 G1b/G2 并行;开工前写 brief | `GROWTH_PLAN_zh.md` §排期修正 |
| G4b | 跨书馆长完整形态 | backlog | R3 后 | `GROWTH_PLAN_zh.md` |

## P1 已知缺口与砍掉项(2026-06-11 用户决策更新)

- 角色自由多轮工具调用 loop、统一 streaming tool-call 组件、研讨结果回流主对话上下文 → R3。
- 取消后续跑(resume)/"继续研讨":**不做**,取消即终止。
- 沉淀动作(知识卡/复习/图谱/送审)与杀进程恢复:不作为 P1 gate,R2 后再评估。
- 旧 provider stream 原地续传:**不做**(决策于 2026-06,见 archive)。

## 真机验收记录

| 日期 | 任务 | 结果 | 失败项 |
| --- | --- | --- | --- |
| 2026-06-11 | P1(v1 脚本) | 部分通过 | 运行期界面闪动+卡顿(→F1);打开来源不跳转(→F2);另产生产品修正:对话内工具式发起(→F3) |
| 2026-06-11 | P1 二轮(v2 脚本) | 部分通过 | F2/F3 通过;F1 残余开始瞬间抖动(→F4);白板/分歧/观点点不开(→F5);读者动作强制填文本(→F6);全局轮次缺失(→F7);保存后无查看(→F8) |
| 2026-06-12 | P1 三轮(v3 脚本) | 部分通过 | F4 开始瞬间已稳、F7/F8 可用;生成全程仍上下跳(→F9);整理总结无反应、重新找证据变重跑(→F10);分歧扫描/分歧继续讨论/角色观点仍点不开(→F11);裸 current-N、字面 \n、运行追踪 uuid(→F12/F13) |
| 2026-06-12 | P1 四轮(v4 脚本) | 部分通过 | 滚动跳动/卡顿已清(F9 ✓);用户拍板:读者参与整体重构为"聊天即参与"(→F14);证据编号对不上(→F15);展开仍有四处漏(→F16);需快速滚动(→F17);角色控制漂移不可用(→F14) |
| 2026-06-12 | P1 五轮(v5 脚本,build 6531) | 部分通过 | F15/F16/F17 可用;参与区发送无反应、跳转卡顿、双输入框别扭——参与层五轮未稳,判定结构性问题:冻结(→F19b),移交 R3;研讨上下文孤岛(→F19a 回流) |
| 2026-06-15 | P1 六轮(v6 脚本,build 6532) | 部分通过 | 8 各 tab 展开、13 回底按钮、10a 追问引用结论、10 参与控件已清:均过。残留:角色"生成中"与"思考"标签重叠闪烁(→F20);结束后思考详情仍显示"主持人正在等你插话",自相矛盾(→F21)。另:13 用户提双击标题回顶(移交 R1 后) |
| 2026-06-17 | P1 七轮(v6 脚本,build 6533) | 全量通过 | F20(标签不再叠闪)、F21(结束后无"等待插话")复测通过,完整研讨收尾正常、中途取消干净;用户确认 → P1 收口 done,启动 R1 |
