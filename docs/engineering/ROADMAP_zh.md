# PaperTok Reader 路线图（工程视角）

本文档以工程交付为中心，记录已完成内容与下一阶段计划。

> 备注：`product/main` 与 `swift-native` 目前是两条不同节奏的工程轨。若你关心原生迁移分支的最新真实进展，请优先看 `docs/engineering/SWIFT_NATIVE_STATUS_zh.md`。

## 测试覆盖现状

- ✅ iOS（iPhone / iPad）已做真机验证
- ⏳ Android / 桌面端尚未系统性回归（计划中）

> 建议：如果当前需要多端稳定使用，请以上游 **Anx Reader** 为主；PaperTok Reader 仍以 iOS 优先做产品化验证。

## 0. 当前结构

- 产品仓库（private）：`ViffyGwaanl/papertok-reader`（main）
- PaperTok 服务：`ViffyGwaanl/papertok`

> 备注：上游贡献（Anx Reader）当前不是产品交付必需项；如未来要上游化，会再单独建立 / 维护 contrib track。

---

## 1. 已完成（核心能力）

### 1.1 PaperTok / Papers Tab（产品功能）

- PaperTok 作为一级 Home tab
- Feed（PageView）+ Detail（Explain / Original 双 tab）
- EPUB / PDF 下载导入后自动打开阅读
- Home navigation 配置（排序 + 显隐；papers / settings mandatory）

文档：`docs/papertok/README.md`

### 1.2 AI 对话系统（核心能力）

- Provider Center（内置 + 自定义；disabled providers 不出现在 chat selector）
- In-chat provider / model switch
- Thinking 档位 UI；Gemini `includeThoughts`
- Thinking / Answer / Tools 折叠展示；思考内容仅展示 provider 返回
- 对话编辑 / 再生成 / variants；conversation tree v2 rollback
- OpenAI Responses provider（`/v1/responses`）
- dev-mode debug logs toggle
- iPad AI 面板 UX：dock resize / persist、dock left / right、bottom sheet 选项等
- 多模态对话附件（图片 + 纯文本文件，附件上限可配置）
- EPUB 图片解析（点击图片 -> 解析；独立 provider / model 配置；与对话流隔离 scope）

### 1.3 EPUB inline 全文翻译（核心能力）

- 译文在下（沉浸式）
- HUD 进度 + 并发控制 + 缓存（按 book）
- 可靠性：失败原因统计、可见块自动重试、清缓存后重试修复
- started / candidates 重试诊断

### 1.4 Share / Shortcuts 产品化收口

- 统一 `Share & Shortcuts Panel`
- prompt presets（title + preview）
- ask-after-open 流程
- 会话目标 / 附件上限配置
- docx / 文本文件 AI 文本附件支持
- inbox cleanup / TTL / diagnostics
- diagnostics 搜索 / 筛选增强已完成

### 1.5 Memory M1（manual-first）

- 检索层 + 最小写入工作流均已打通
- 已完成：
  - `daily memory`
  - `long-term memory`
  - `review inbox`
  - 候选记忆 / 审核 / 提升最小闭环
  - Markdown 统一写协调器

### 1.6 低风险命名收口

- README / docs 入口已统一为 `PaperTok Reader`
- App 内可见文案 / l10n 已统一为 `PaperTok Reader`
- iOS / Android 显示名已统一为 `PaperTok Reader`
- 仍保留技术底座历史真值：`anx_reader` / bundle id / URL scheme

### 1.7 阅读器质量提升（吸收上游 v1.14 Phase A + B）

> 目标：不动已深改的 AI/chat 主干，优先吸收低耦合的阅读器稳定性修复与可回滚增强。

- Phase A（低风险稳定性）
  - RangeError（read theme 颜色为空/非法）修复
  - TOC 长标题换行（wrap）
  - EPUB 图片溢出修复
  - i18n locale 不支持 fallback 英文
  - Android 10+ 保存图片移除不必要权限
- Phase B（中风险增强，模块拆分）
  - 背景图：Blur / Opacity + Fit（Cover/Stretch）
  - Header/Footer：section 模型（margin/fontSize）+ Prefs 迁移 + 设置项 UI
  - TTS：SystemTts crash 修复 + 阅读页播放快捷 FAB

证据：PR `https://github.com/ViffyGwaanl/papertok-reader/pull/7`；TestFlight `1.68.5 (6376)`

### 1.8 AI Agent 系统优化（2026-04-01）

> 详细设计见 `docs/ai/agent_system_architecture_zh.md`

- Service/UI 解耦：`CancelableLangchainRunner` 不再依赖 `flutter/material.dart`
- 场景感知工具过滤：`AiToolScene` 枚举，按阅读/书架场景减少工具 token ~50%
- 工具字母序排列：稳定 prompt cache 命中
- 并发工具执行引擎：`ToolOrchestrator`（isConcurrencySafe 分区调度）
- CreateHighlightTool + CreateNoteTool：AI 书内标注写工具
- LLM 摘要式上下文压缩：替代简单消息截断
- SSE 心跳 15s：防移动端代理断连
- JSON 修复层 / 标注台账 / Token 成本追踪 / 动态 max_tokens / 章节缓存

---

## 2. 下一阶段

### 2.0 Swift Native 工程轨（并行 P1）

- 已完成：
  - `swift-native` 用户可见中文增强闭环（已审计范围）
  - catalog 完整性测试
  - helper-based key extraction 覆盖
  - 硬编码英文审计
  - 用户可见错误映射回归
- 接下来建议：
  - 扩大验证面到更多 package / app surfaces
  - 做 iPhone / iPad / macOS 的人工本地化 walkthrough
  - 继续把高频 tool error 从 UI 兜底推进到源头本地化
  - 在 full-spec closure 语境下，重新核对 parity / verification truth source
- 详见：`docs/engineering/SWIFT_NATIVE_STATUS_zh.md`

### 2.1 Memory 工作流后续增强

- session-end candidate digest
- 可选 auto-daily
- 更细的策略开关
- Review Inbox 来源跳转 / 审阅体验增强

策略保持不变：
- `daily` 半自动 / 可选自动
- `long-term` 确认后写入
- 不默认开启完全静默长期写入

详见：`docs/ai/memory_workflow_openclaw_alignment_zh.md`

### 2.2 命名收口第二阶段

- 统一 repo / workspace / release artifact 口径
- macOS / 桌面 artifact naming 收口
- package rename 单独立项，不与当前收口混做

详见：`docs/engineering/NAMING_CLEANUP_PLAN_zh.md`

### 2.3 构建 / 发布回归

- iOS / iPadOS checklist 按版本执行
- 如需新测试包，继续走离线 TestFlight 流程
- 当前回归包：`1.68.5 (6376)`（对应 PR #7：上游 v1.14 Phase A+B 吸收）
- Android checklist / 桌面 smoke 回归补齐

### 2.4 文档体系维护（持续）

- README + docs（engineering / ai / papertok）与当前实现保持一致
- 将“上游贡献”相关内容维持为可选项，不阻塞产品交付

---

## 3. 建议优先级

### P0（发布稳定性）

- iOS 构建 / TestFlight 回归稳定
- iPhone / iPad 关键交互的 smoke 验证持续执行

### P1（产品质量）

- Memory M1.5：digest / 策略开关 / Inbox 体验增强
- Android 真机回归
- 错误提示与日志继续增强，减少“黑盒报错”
- Swift Native：扩大验证面并继续推进源头级错误本地化

### P2（能力扩展）

- 译后 EPUB 导出管线（REPLACE / APPEND_BLOCK）
- 翻译失败诊断再增强
- 命名第二阶段 / 高风险 rename 预研
- 桌面端适配与 packaging 验证
- **Agent 系统集成**：将已完成的优化模块（ToolOrchestrator / ConversationCompressor / BookContentCache / AiUsageTracker / AnnotationLedger）接入主 agent loop
- **Sub-Agent 系统**：explore / summarize / verify 子 Agent
- **Skills 系统**：可安装提示模板（论文分析 / 抽认卡 / 辩论伙伴）
