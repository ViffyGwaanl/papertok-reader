# 体验重建期总控(2026-07 起,6–8 周)

> 性质:本文件是体验重建期的总控计划,补充而不替代 `STATUS_zh.md`(状态仍只看/只改状态表)。
> 背景:用户判定 app 整体使用体验不达标(AI 对话抖动与割裂、阅读翻译工程感、全局糙感)。经审查,根因收敛为三个,对应 A/B/C 三线。
> 执行者:CodeX(或任何执行 agent)。开工必读:`README_zh.md` + `AGENT_PROTOCOL_zh.md` + `STATUS_zh.md` + 本文件 + 当前线 brief,合计 ≤12K token;其余按需 grep,禁止通读 `archive/` 与巨型源文件。

## 三条线与任务映射

| 线 | 内容 | 任务 ID | Brief |
| --- | --- | --- | --- |
| A 线 | AI 对话重建:事件流单一数据源 → 渲染局部化 → 聊天即参与 | A1=R2(已有)、E1(新)、A2=R3(已有) | `briefs/R2_event_ssot_zh.md`、`briefs/E1_chat_render_locality_zh.md`、`briefs/R3_agent_platform_merge_zh.md` |
| B 线 | 阅读翻译体验简化(去工程仪表盘、自动恢复、人话提示) | E2 | `briefs/E2_translate_ux_simplify_zh.md` |
| C 线 | 全局糙感清扫(zh 漏翻、裸错误文案、双击回顶、PaperTok 首屏) | E3 | `briefs/E3_polish_sweep_zh.md` |
| C 线 | 减法与聚焦(7 tab→4、设置树三段式、选区菜单≤5、AI 顶栏收纳、淘汰候选) | E4 | `briefs/E4_subtraction_focus_zh.md` |

## 顺序与并行规则

1. **E3 立刻开工**,不依赖任何线;批次间也可独立验收。
2. **A 线严格串行:R2 → E1 → R3**。R2 删双写/fallback 后,E1 的局部化才不用为兼容层做两套;R3 的统一 streaming 组件必须落在 E1 的按消息重建架构上。
3. **E2 可与 A 线并行**,前提:不碰 A 线文件(E2 只动 `lib/widgets/reading_page/`、`lib/service/translate/`、ARB;A 线只动 `lib/widgets/ai/`、`lib/providers/ai_chat*.dart`、`lib/service/ai/`)。同一 PR/commit 不得跨线。
4. **R2 批次 1 的用户拍板项已定**:放弃旧研讨运行历史,不做迁移批次(用户 2026-07-03 授权方向;正式生效前在 STATUS 行确认一次)。
5. **冻结规则:重建期内不接受任何新功能切片**(P6 批次 5 收尾除外)。新想法一律记入 STATUS backlog,重建期后排。

## 批次 0(全期只做一次,任何线开工前)

在用户 Mac 上记录基线并写进首个 commit message(不新建文档):`flutter analyze` 当前问题数(已知约 224 个存量,分布在 Packages/langchain_openai 等)、`flutter test` 全量结果快照。此后所有"无新增/全绿"门禁均相对此基线判定;若基线本身有红测试,先修或按协议 §5 降级,再开工。

## 验收节奏(防 P6 式积压)

- 任务行推进到"待真机验收"后,用户应在 2 个工作日内出 build 验收;验收结果(过/失败项)当天回写 STATUS 对应行。
- E3 各批次可攒 2–3 个合并进一个 build;R2/E1/R3 每完成一个任务行必须单独验收,不许两行攒一个 build。
- 在飞旧账:P6 批次 5(空态/手机尺寸/ARB/配色收尾)在 P6 验收通过后由执行 agent 按 P6 brief 执行,是冻结规则的唯一例外。

## 全局工作规程(每个切片必须遵守)

- 一批次 = 一切片 = 一 commit;commit message 格式见各 brief。
- 每批收尾必跑:`flutter analyze`(无新增)+ `flutter test`(全绿)+ `bash tool/check_repo_budgets.sh`(通过)。
- 文档改动上限:`STATUS_zh.md` 对应行 + commit message。禁止新建"进展/总结"文档,禁止在任何文档写"最新进展"段。
- 状态只有 backlog / in progress / 待真机验收 / done;**done 只能由用户标**。
- 新代码文件 ≤1500 行;超限老文件(baseline 白名单)只许变短。
- 所有用户可见文案进 ARB(`app_en.arb` + `app_zh.arb`),过 `flutter gen-l10n`。

## 高风险误改区(全线通用,改前三思)

| 区域 | 风险 |
| --- | --- |
| `lib/providers/ai_chat.dart` 的 `conversationV2: _tree.toJson()` 持久化 | 写坏 = 用户历史对话丢失;任何树/消息改动必须带 provider 测试 |
| `lib/widgets/ai/seminar/`(83 个测试护体) | R1 刚抽出的机械搬移;E1 只许改其挂载/订阅方式,不许改内部逻辑 |
| `assets/foliate-js/src/book.js` | 选区、CSS 注入、翻译管线共用;B1 刚改过;本期任何线都不动它 |
| `lib/dao/database.dart`(schema v8) | 本期无任何任务需要动 migration;动了即越界 |
| `lib/config/shared_preference_provider.dart` 的既有 key | 被 `ai_settings_sync.dart` 同步;只许加 key、改默认值,不许删/改名 |
| `lib/widgets/ai/ai_chat_stream.dart`(god file,baseline 白名单) | 只许变短;新逻辑一律进新文件,god file 只留挂钩 |

## 本期结束的定义

R2、E1、E2、E3 四行 done + R3 至少进入"待真机验收";用户真机主观确认:长回答生成全程不晃、研讨在主对话里一个输入框完成、翻译坏了会自己好、中文界面无英文残留。之后才评估 P2(全书理解地图)开工。
