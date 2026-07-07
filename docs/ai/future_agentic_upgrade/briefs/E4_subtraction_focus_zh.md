# E4 Brief — 减法与聚焦

> 前置:无(与 E3 并行;批次 1 纯提案不动代码)。归属:体验重建期 C 线。
> DoD:首页 tab、设置树、选区菜单、AI Chat 顶栏四个界面的可见复杂度按用户勾选的清单收缩;默认形态是"阅读器",工程能力退到幕后;真机验收通过。
> 最后更新:2026-07-03

## 问题(2026-07-03 盘点数字)

- 首页 **7 个 tab**:Papers / 书架 / 统计 / AI / 笔记 / 记忆 / 设置(`home_page.dart` 行 174–204;`home_navigation.dart` 已支持自定义,说明问题早被感知)。
- 设置 **30+ 子页**,AI 相关 17 个:ai / ai_image_analysis / ai_library_index / ai_provider_center / ai_quick_prompts_editor / ai_seminar_config / ai_title_generation / ai_tools(52 个工具管理)/ custom_skills / mcp_servers / mcp_auth_editor / mcp_server_detail / concept_graph_explorer / knowledge_asset_export / review_inbox / memory / spaced_review。MCP 服务器配置出现在一个阅读 app 的主设置里。
- 阅读页选区菜单 **~11 个动作**(copy/search/translate/writeIdea/highlight/underline/knowledgeCard/conceptGraph/seminar/share/note)。
- AI Chat 顶部/工具栏 **25 处 IconButton/PopupMenu**。

诊断:每个功能都对,加在一起是认知税。默认界面应该只呈现"读书—理解—沉淀"主干;其余能力保留但退场。

## 目标形态(用户逐项拍板后执行)

1. **首页 4 tab**:书架(默认)/ 发现(PaperTok)/ AI / 我的。统计、笔记、记忆、设置收进"我的";`home_navigation.dart` 自定义能力保留,只改默认集与新用户默认。
2. **设置三段式**:常用(外观/阅读/翻译/同步)· AI(唯一入口 = Provider Center,tools/skills/MCP/seminar 配置/标题生成/图片分析/快捷 prompt 全部收进其"高级"区;MCP + custom skills + 52 工具管理默认隐藏,开发者开关后可见)· 数据(记忆/复习/知识导出/存储)。诊断类(log/share_inbox_diagnostics/developer)收进 高级>诊断。
3. **选区菜单一级 ≤5**:高亮(含样式)/ 复制 / 翻译 / 问 AI / 分享;writeIdea、知识卡、概念图谱、研讨并入"问 AI"二级或对话内路由(与 R3"聊天即参与"同向)。
4. **AI Chat 顶栏**:保留 新对话/历史/对话树/模型选择,其余进 overflow 菜单(执行时先盘点 25 处,产出保留/收纳清单)。
5. **淘汰候选(默认隐藏一个版本,下个大版本删码)**:concept_graph_explorer 独立入口、knowledge_asset_export 远程同步(含 ETag/CAS 提示那套)、ai_title_generation / ai_image_analysis 独立子页(降为 AI 设置里的开关)、`storege.dart`(拼写即警示)与 migration_page 归属审查。

## 批次

1. **盘点与提案(不动代码)**:已完成(2026-07-03),产出 `E4_DECISION_LIST_zh.md`(用户已拍板:4 tab / 选区 5 项 / 极客能力进开发者选项 / 图片分析与标题生成保留)。批次 2–6 以该清单为唯一依据。
2. 首页 tab 默认集收缩(只改默认与新用户默认,自定义保留)。
3. 设置树重组(纯移动+分组,不删任何页面代码;隐藏项挂开发者开关)。
4. 选区菜单收纳(一级 ≤5 + "问 AI"二级;不改各动作行为)。
5. AI Chat 顶栏收纳(overflow 化;god file 净变短或持平)。
6. 淘汰候选执行(按用户勾选:先隐藏;删码排下个大版本,单独切片)。

## 验收(真机,用户执行)

1. 新装视角走一遍:首页 4 tab,设置一屏能看懂,选中文字弹的菜单 ≤5 项。
2. 自己的高频路径(你真实的日常操作)全部 ≤ 原点击数,无一变深(拍板时逐项确认)。
3. 开发者开关打开后,MCP/工具/skills 等全部能力完好可达。
4. 无任何功能行为变化(纯排布);E3/E2 改动无回归。

## 红线

- 批次 1 用户勾选前,不删、不藏任何东西;用户日常在用的项(拍板时标注)不许动。
- 只做排布与可见性,不改功能逻辑、不删数据、不动 DB。
- 隐藏 ≠ 兼容层:一个开发者开关统一控制,禁止散落多个 flag。
- god file 与 baseline 白名单文件净不增。

## 验证命令

```bash
flutter analyze && flutter test
bash tool/check_repo_budgets.sh
```

commit 格式:`refactor(ux-focus): <批次> (E4 batch N)`
