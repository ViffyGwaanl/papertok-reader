[English](README.md) | **简体中文**

<br>

# PaperTok Reader（papertok-reader）

**PaperTok Reader** 是一个以 iOS/iPadOS 为主验证的 AI 阅读产品发行版，基于上游
**[Anx Reader](https://github.com/Anxcye/anx-reader)**（MIT）定制与增强。

这个仓库的核心方向是“有来源、有证据、可复习、可回到原文”的深度阅读工作流：

- 通过 PaperTok 发现和导入论文；
- 在移动端阅读 EPUB/PDF；
- 围绕当前书籍和书库证据向 AI 提问；
- 把有价值的回答沉淀成待审知识卡、概念关系、记忆和复习项；
- 默认保护 API key 与用户知识资产。

## 多端状态

- 本仓库已测试：**iOS（iPhone）**、**iPadOS（iPad）**。
- 本仓库尚未系统性验证：**Android** 与桌面端。
- 如果你现在需要稳定的广泛多端阅读器，建议使用上游 **Anx Reader**。

## 和上游有什么不同

PaperTok Reader 不只是换名版本。当前产品分支加入了 PaperTok 论文流、AI
供应商中心、阅读器内 AI 工作流、本地 RAG 索引、Memory、Review Inbox、
知识卡、概念图谱、多角色研讨会、知识资产同步/导出等能力。

通用能力未来可以走干净的 upstream contrib track；PaperTok 与产品专属 AI
知识工作流继续在本仓库演进。

## 功能亮点

### PaperTok 论文流

- 一级 **Papers** Tab，集成 PaperTok 学术论文流。
- TikTok 风格纵向信息流；论文详情页包含解释、图片与原文入口。
- 详情页支持导入 EPUB/PDF；如果服务端提供英文、中文、双语版本，会显示版本选择。
- 导入成功后可直接打开阅读页，减少“导入后再去书架找”的步骤。

### 阅读、翻译与深链

- iPhone/iPad 阅读页针对论文阅读做了产品默认值和交互调优。
- EPUB 沉浸式全文翻译：译文显示在原文下方。
- 按书翻译缓存、失败段落重试、右上角进度 HUD、独立翻译供应商/模型设置。
- 统一阅读器深链：`paperreader://reader/open?...`。AI 证据、知识卡、Review
  item、概念图谱、Memory 来源在具备 `bookId` / `href` / `cfi` 时都可以回跳原文。

### AI 对话与 Provider Center

- Flutter 原生 Provider Center，支持内置供应商与自定义供应商：
  OpenAI-compatible、OpenAI Responses、Anthropic、Gemini。
- 对话内切换供应商与模型。
- 思考档位选择；Thinking / Answer / Tools 折叠展示。
- OpenAI Responses 兼容开关：`previous_response_id` 续写、reasoning summary。
- 可编辑历史消息、从任意用户轮次重新生成、对话树多版本/回滚。
- 多模态附件：图片与文本类文件，附件上限可配置。
- EPUB 图片解析：点图后调用多模态模型分析，并可把结果送入知识待审流程。

### RAG 与 AI 索引

- 书库 AI 索引数据库 `ai_index.db`，支持队列控制、暂停/继续/取消、失败重试、重建和重启恢复。
- 当前书与全书库语义检索工具：`semantic_search_current_book`、
  `semantic_search_library`。
- 混合检索：FTS/BM25 候选、向量评分、证据来源、阅读器跳转链接。
- 当前书搜索加入移动端资源保护：FTS 预筛、fallback 向量扫描预算、取消、降低 AI
  请求期间 UI 刷新压力。
- 需要时可用本地 OpenAI-like endpoint 跑 embedding / rerank smoke test。

### Memory 与 Review Inbox

- 本地 Markdown Memory：长期 `MEMORY.md` + 每日笔记。
- AI 对话可以生成 Memory 候选，而不是静默写入长期记忆。
- Memory 搜索支持本地文本检索；embedding 可用时支持语义检索。
- Review Inbox 是 AI 生成内容和导入知识资产的安全闸门：先 approve / dismiss /
  apply，再进入正式资产。
- Review item 保留来源；没有阅读器深链时显示“来源详情”，而不是报错。

### 知识卡、概念图谱与间隔复习

- **知识卡**借鉴 MarginNote 的摘录卡/知识卡/复习/回跳原文思路。
- 选中文本、AI Chat 回答、Seminar 结论、图片解析、RAG 证据都可以进入知识卡待审流程。
- 知识卡默认是 draft / pending，需要来源证据与用户确认后才会成为正式知识资产。
- Review Inbox 中知识卡正文按 Markdown 渲染，并显示证据与来源状态。
- 已通过审核的知识卡可以生成 spaced review 复习项。
- **概念图谱**融合 WikiLinks 的局部概念探索思路，以及 Understand-Anything
  的概念图谱/影响关系思路。
- 图谱节点/边来自已审核知识卡、Seminar 交接和 RAG/GraphRAG 候选；正式关系仍然经过 Review。

### AI Seminar（多角色研讨会）

- 借鉴 OpenMAIC 的多角色讨论形式。
- 默认角色：批判者、支持者、综合者；可选核验者。
- Seminar 是“角色 agent + 角色提示词编排”，不是单条静态 prompt。每个角色都会接收证据包、前序发言和输出规则。
- 运行页展示角色卡片、证据 chip、Markdown 发言、共享白板、综合结论、用量/费用估算、取消/重试和 Send to Review。
- 独立 **研讨会设置**页面可配置默认核验者与本地预算保护。

### Share Sheet、Shortcuts 与工具

- 统一 Share & Shortcuts Panel：默认路由、提示词预设、回传行为、清理策略、诊断与附件上限。
- iOS Shortcuts 通过 `paperreader://shortcuts/...` 回传结果，不会和阅读器打开深链混淆。
- AI 工具包括 Memory 读/搜/追加/覆盖、当前书检索、全书库检索、受治理的工具执行。
- 自定义 Skills 有 schema 校验、parser/runtime 注入门、场景收窄和工具白名单。

### 同步、备份与导出

- WebDAV 同步非敏感 AI 设置，例如供应商、模型、提示词和 UI 偏好。
- 明文备份绝不包含 API key；只有加密备份才允许包含 API key。
- 手动备份/恢复支持 Memory 与 AI 索引选项。
- 知识资产导出和远端同步遇到冲突、远端待引入、远端复习记录时，会进入 Review Inbox，而不是直接覆盖本地数据。
- 远端写回有安全检查、回滚路径和知识卡冲突暂存流程。

## 用户入口

- 论文流：`Home -> Papers`
- AI 供应商：`Settings -> AI -> AI Provider Center`
- 书库 AI 索引：`Settings -> AI Index (Library)` / AI 索引设置入口
- 知识待审：`Settings -> AI -> Review Inbox`
- 概念图谱：`Settings -> AI -> Concept graph`
- 间隔复习：`Settings -> AI -> Spaced review`
- AI Seminar：`Settings -> AI -> Seminar Mode`
- 研讨会默认设置：`Settings -> AI -> Seminar settings`
- 阅读页选中文本：上下文菜单中的 Knowledge Card / Seminar / Concept Graph
- Memory：Memory 设置页/页面，可选加入 Home Tab
- 分享与快捷指令：`Settings -> Share & Shortcuts Panel`

## 隐私与安全默认值

- API key 默认只保存在本地，不进入明文同步和明文备份。
- AI 生成内容默认是 draft 或 pending review。
- 正式知识卡、概念关系、Review item 和复习项尽量保留来源引用。
- 只有 AI Chat 历史来源、没有阅读器锚点的内容可以被审核，但不能静默升级成“有原文证据”的正式阅读知识资产。
- `ai_index.db` 等派生索引是可重建缓存，不是用户知识资产的唯一真值源。

## 文档入口

- 文档索引：**[`docs/README.md`](./docs/README.md)**
- AI / RAG / Memory 总览：**[`docs/ai/README.md`](./docs/ai/README.md)**
- Future Agentic Upgrade 规格：
  **[`docs/ai/future_agentic_upgrade/README_zh.md`](./docs/ai/future_agentic_upgrade/README_zh.md)**
- 当前实现状态：
  **[`docs/ai/future_agentic_upgrade/implementation_status_zh.md`](./docs/ai/future_agentic_upgrade/implementation_status_zh.md)**
- PaperTok 论文流集成：
  **[`docs/papertok/README.md`](./docs/papertok/README.md)**

### 工程 / 发布

- iOS 真机安装 / 签名 / TestFlight：
  **[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- Identifiers 真值源：
  **[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**
- iOS TestFlight 发布清单：
  **[`docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md`](./docs/engineering/RELEASE_IOS_TESTFLIGHT_zh.md)**
- 平台测试状态：
  **[`docs/engineering/PLATFORM_TEST_STATUS_zh.md`](./docs/engineering/PLATFORM_TEST_STATUS_zh.md)**
- 故障排除：**[`docs/troubleshooting.md`](./docs/troubleshooting.md)**

## 开发快速开始

```bash
flutter pub get
flutter gen-l10n
# 本仓库忽略部分生成文件，需要时再跑 build_runner。
# dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

如果 `build_runner` 遇到 Flutter/Dart SDK 不匹配问题，可以试：

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## 与上游的关系 / 工作流

本仓库以产品交付为主：

- PaperTok 与产品专属 AI/知识 UX 在本仓库演进。
- 通用 AI/翻译改进未来可以走干净的 contrib track，不混入 PaperTok 产品专属改动。

详见：
**[`docs/engineering/WORKFLOW_zh.md`](./docs/engineering/WORKFLOW_zh.md)**
和
**[`docs/engineering/UPSTREAM_CONTRIB_zh.md`](./docs/engineering/UPSTREAM_CONTRIB_zh.md)**。

## License

MIT（与上游 Anx Reader 保持一致）。
见 [LICENSE](./LICENSE)。
