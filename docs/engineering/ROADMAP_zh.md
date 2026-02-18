# papertok-reader 路线图（工程视角）

本文档以工程交付为中心，记录已完成内容与下一阶段计划。

## 0. 当前结构
- 产品仓库（private）：`ViffyGwaanl/papertok-reader`（main）
- 上游贡献仓库（public fork）：`ViffyGwaanl/anx-reader`（contrib/ai-translate）
- PaperTok 服务：`ViffyGwaanl/papertok`

---

## 1. 已完成（核心能力）

### 1.1 PaperTok / Papers Tab（产品功能）
- PaperTok 作为一级 Home tab
- Feed（PageView）+ Detail（Explain/Original 双 tab）
- EPUB/PDF 下载导入后自动打开阅读
- Home navigation 配置（排序+显隐；papers/settings mandatory）

文档：`docs/papertok/README.md`

### 1.2 AI 对话系统（通用能力，可上游）
- Provider Center（内置+自定义；disabled providers 不出现在 chat selector）
- In-chat provider/model switch
- Thinking 档位 UI；Gemini includeThoughts
- Thinking/Answer/Tools 折叠展示；思考内容仅展示 provider 返回
- 对话编辑/再生成/variants；conversation tree v2 rollback
- OpenAI Responses provider（/v1/responses）
- dev-mode debug logs toggle
- iPad AI 面板 UX：dock resize/persist、dock left/right、bottom sheet 选项等

### 1.3 EPUB inline 全文翻译（通用能力，可上游）
- 译文在下（沉浸式）
- HUD 进度 + 并发控制 + 缓存（按 book）
- 可靠性：失败原因统计、可见块自动重试、清缓存后重试修复
- started/candidates 重试诊断

---

## 2. 进行中

### 2.1 上游 PR
- 入口 Draft PR：`Anxcye/anx-reader#780`（AI+翻译，不含 PaperTok）
- 根据维护者反馈决定是否拆分为 PR 系列

### 2.2 iOS/Android 产品发布“新项目化”
- 建议改 Bundle ID / applicationId（避免与原版/其他分支冲突）
- 建议统一版本号策略、TestFlight 流程

---

## 3. 下一阶段计划（建议优先级）

P0（阻塞发布/上游合并）：
- 与上游维护者对齐 PR 拆分边界；按反馈拆分 PR 系列
- 修复/补齐上游 CI 所需的细节（如有）

P1（产品质量）：
- Bundle ID / appId 改造 + 签名/entitlements 梳理（TestFlight 友好）
- 将 AI/翻译稳定版本从 Contrib Track 同步到产品 main（cherry-pick）

P2（翻译能力扩展）：
- 导出“译后 EPUB”管线（REPLACE/APPEND_BLOCK）与 UI（此前规划项）
- 失败诊断进一步增强（HUD 显示 Top1 failure reason / started=candidates 细化等）
