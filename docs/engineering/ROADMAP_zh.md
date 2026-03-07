# PaperTok Reader 路线图（工程视角）

本文档以工程交付为中心，记录已完成内容与下一阶段计划。

## 测试覆盖现状

- ✅ iOS（iPhone/iPad）已做真机验证
- ⏳ Android / 桌面端尚未系统性回归（计划中）

> 建议：如你现在需要多端稳定使用，请以 **Anx Reader** 上游版本为主；PaperTok Reader 当前以 iOS 优先做产品化验证。

## 0. 当前结构
- 产品仓库（private）：`ViffyGwaanl/papertok-reader`（main）
- PaperTok 服务：`ViffyGwaanl/papertok`

> 备注：上游贡献（Anx Reader）当前不是产品交付必需项；如未来要上游化，会再单独建立/维护 contrib track。

---

## 1. 已完成（核心能力）

### 1.1 PaperTok / Papers Tab（产品功能）
- PaperTok 作为一级 Home tab
- Feed（PageView）+ Detail（Explain/Original 双 tab）
- EPUB/PDF 下载导入后自动打开阅读
- Home navigation 配置（排序+显隐；papers/settings mandatory）

文档：`docs/papertok/README.md`

### 1.2 AI 对话系统（核心能力）
- Provider Center（内置+自定义；disabled providers 不出现在 chat selector）
- In-chat provider/model switch
- Thinking 档位 UI；Gemini includeThoughts
- Thinking/Answer/Tools 折叠展示；思考内容仅展示 provider 返回
- 对话编辑/再生成/variants；conversation tree v2 rollback
- OpenAI Responses provider（/v1/responses）
- dev-mode debug logs toggle
- iPad AI 面板 UX：dock resize/persist、dock left/right、bottom sheet 选项等
- 多模态对话附件（图片 + 纯文本文件，max 4 图；不进备份/不走 WebDAV sync）
- EPUB 图片解析（点击图片 → 解析；独立 provider/model 配置；与对话流隔离 scope）

### 1.3 EPUB inline 全文翻译（核心能力）
- 译文在下（沉浸式）
- HUD 进度 + 并发控制 + 缓存（按 book）
- 可靠性：失败原因统计、可见块自动重试、清缓存后重试修复
- started/candidates 重试诊断

---

## 2. 进行中

### 2.1 Memory 工作流补齐
- 现状：M1（manual-first）已落地，检索层 + 最小写入工作流都已打通。
- 已完成：
  - `daily memory`
  - `long-term memory`
  - `review inbox`
  - 候选记忆 / 审核 / 提升最小闭环
- 下一阶段：
  - session-end candidate digest
  - 可选 auto-daily
  - 更细的策略开关
- 策略：
  - `daily` 半自动 / 可选自动
  - `long-term` 确认后写入
  - 不默认开启完全静默长期写入
- 详见：`docs/ai/memory_workflow_openclaw_alignment_zh.md`

### 2.2 命名收口
- 现状：产品口径已偏向 `PaperTok Reader`，但内部工程真值源仍大量残留 `anx-reader` / `anx_reader`。
- 下一阶段：
  - 先统一文档与对外口径
  - 再评估工作区 / 产物名收口
  - package rename 单独立项，不与当前收口混做
- 详见：`docs/engineering/NAMING_CLEANUP_PLAN_zh.md`

### 2.3 Share diagnostics 增强
- 现状：diagnostics 页已具备基础列表与 cleanup 状态
- 下一阶段：
  - 搜索
  - 状态筛选
  - destination 筛选
  - 文件类型筛选
- 目标：把 diagnostics 从“可查看”升级成“可高效排障”

### 2.4 文档体系更新（持续）
- README + docs（engineering/ai/papertok）与当前实现保持一致。
- 将“上游贡献”相关内容降级为可选项（不阻塞产品交付）。

---

## 3. 下一阶段计划（建议优先级）

P0（阻塞发布）：
- iPhone TabBar 视觉/交互最后收敛（不遮挡、不挤压、参数稳定）。
- iOS 构建环境稳定（Xcode Platform 组件齐全），保证 TestFlight 出包可复现。

P1（产品质量）：
- 完整 iOS/iPadOS QA checklist 按版本执行（回归脚本化）。
- PaperTok / AI / 翻译三个核心链路的日志与错误提示再增强（减少“黑盒报错”）。

P2（能力扩展）：
- 导出“译后 EPUB”管线（REPLACE/APPEND_BLOCK）与 UI（此前规划项）。
- 翻译失败诊断进一步增强（HUD 显示 Top1 failure reason / started=candidates 细化等）。
- Android/桌面端回归与适配（以产品实际需求驱动）。
