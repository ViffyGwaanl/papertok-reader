# E4 决策清单(批次 1 产出,用户已拍板 2026-07-03)

> 本文件 = E4 批次 2–6 的唯一执行依据;逐项状态:**执行** / 保留 / 待定。执行 agent 不得自行增删项。
> 宏观决策(用户拍板):① 首页默认 4 tab;② 选区一级菜单 5 项;③ 极客能力移开发者选项;④ 图片分析与标题生成**保留可见**,概念图谱入口与知识远程导出收纳(暂不删码,删码需另行拍板)。

## 一、首页 tab(批次 2)

现状 7 tab:Papers / 书架 / 统计 / AI / 笔记 / 记忆 / 设置(`home_page.dart` 行 174–204;自定义基建 `home_navigation.dart`)。

| 项 | 处置 |
| --- | --- |
| 新默认集 | **执行**:书架(默认首屏)→ 发现(Papers)→ AI → 我的 |
| "我的"聚合页 | **执行**:新文件 `lib/page/home_page/mine_page.dart`,含 统计 / 笔记 / 记忆 / 设置 四入口(列表式,复用现有页面,不改其内部) |
| Papers 改名"发现" | **执行**:ARB 新 key(en: Discover / zh: 发现),不删旧 key |
| 老用户已有自定义 | 保留:Prefs 有自定义 tab 配置的用户不迁移、不打扰 |
| home_navigation 自定义功能 | 保留:可选项加入"我的";统计/笔记/记忆仍可被用户手动加回一级 tab |

## 二、设置树(批次 3)

现状:6 组卡片(阅读/AI/同步与数据/个性化/高级/关于)结构保留;问题集中在 AI 区 6 入口 + 深层极客页。开发者开关基建已存在(`Prefs().developerOptionsEnabled` + `DeveloperOptionsPage`,`settings_page.dart` 行 228–235)。

| 项 | 现状位置 | 处置 |
| --- | --- | --- |
| Provider Center | AI 区一级 | 保留原位 |
| AI 设置(ai.dart) | AI 区一级 | 保留原位 |
| Review Inbox | AI 区一级 | 保留原位 |
| AI 工具管理(52 个,ai_tools.dart) | AI 区一级 | **执行**:移入 DeveloperOptionsPage |
| AI 库索引(ai_library_index_page) | AI 区一级 | **执行**:移入 DeveloperOptionsPage |
| 图片分析(ai_image_analysis) | AI 区一级 | **执行**:降为 `ai.dart` 内入口(用户要求保留可见,不进开发者区) |
| 标题生成(ai_title_generation) | ai.dart 内 | 保留可见(用户要求) |
| MCP 服务器三页(mcp_servers/auth_editor/server_detail) | ai.dart 或深层链接(执行时确认入口路径) | **执行**:入口移入 DeveloperOptionsPage |
| custom_skills / ai_quick_prompts_editor / ai_seminar_config | 深层 | **执行**:入口移入 DeveloperOptionsPage(seminar 高频参数若在研讨发起面板已有,则设置页入口收走无损) |
| concept_graph_explorer | 深层 | **执行**:入口移入 DeveloperOptionsPage(收纳,不删码) |
| knowledge_asset_export(含远程同步/ETag 提示) | 深层 | **执行**:入口移入 DeveloperOptionsPage(收纳,不删码) |
| log_page / share_inbox_diagnostics / developer/ | advanced 或深层 | **执行**:统一挂 DeveloperOptionsPage 下"诊断"分组 |
| spaced_review / memory 设置 | 阅读区(memory)等 | 保留原位(G2 每日回顾的宿主) |

规则:只移动入口与分组,**不删任何页面代码、不改页面内部逻辑**;所有被移入开发者区的页面,开关打开后功能完好。

## 三、选区菜单(批次 4)

现状一级 9 动作一行:copy / search / translate / highlight / writeIdea / knowledgeCard / seminar / conceptGraph / share(`lib/widgets/context_menu/excerpt_menu.dart` 行 577–662,757 行文件)。

| 项 | 处置 |
| --- | --- |
| 一级 5 项 | **执行**:高亮(带既有样式二级)/ 翻译 / 问 AI / 复制 / 分享 |
| "问 AI"二级面板 | **执行**:向 AI 提问(默认,带选区入聊天)/ 发起研讨 / 存知识卡 / 写想法 / 书内搜索(search 从一级移入;位置执行时可微调) |
| conceptGraph 动作 | **执行**:从选区菜单移除(功能经开发者区仍可达);commit message 注明可一行回退 |
| 各动作行为 | 不改:仅重排与分层,所有 onTap 逻辑原样复用 |

## 四、AI Chat 顶栏(批次 5,降级为可选)

实测修正:顶栏仅 5 键(历史抽屉/对话树/字号/清空/结束会话,god file 行 5541–5589),**不臃肿,原"25 按钮"系全文件统计,多在消息卡内**。批次 5 缩水为:输入区快捷件(skills 选择 行1023、最小化等)盘点一次,只有明显冗余才收纳;否则跳过,消息卡内动作留给 E1 组件化时顺带。**禁止为收纳而收纳。**

## 执行顺序与验证

批次 2(tab)→ 3(设置树)→ 4(选区菜单)→ 5(可选)。每批:`flutter analyze` 无新增 + `flutter test` + `bash tool/check_repo_budgets.sh`;新页面文件 ≤1500 行;god file 与 excerpt_menu 净不增(excerpt_menu 757 行未超限可小增,但目标是变简单);全部新文案 ARB en+zh 同批。真机验收按 `E4_subtraction_focus_zh.md` §验收。
