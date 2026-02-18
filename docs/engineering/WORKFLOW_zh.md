# papertok-reader 工程工作流（Product + Upstream）

本文档定义 **papertok-reader** 的长期工程工作流：如何在保持产品快速迭代的同时，把可通用的 AI/翻译能力稳定地贡献回上游 Anx Reader。

> TL;DR
> - **产品开发（含 PaperTok）**：在 `ViffyGwaanl/papertok-reader`（private）完成
> - **上游贡献（AI + 翻译）**：在 `ViffyGwaanl/anx-reader` 的 `contrib/ai-translate` 完成，然后提 PR 到 `Anxcye/anx-reader:develop`
> - **同步方向**：Contrib → Product（不要反向）

---

## 1. 仓库与职责（Source of Truth）

### 1.1 `ViffyGwaanl/papertok`（服务端/内容源）
- 负责：论文 feed、paper detail、解释内容、媒体资源
- 不负责：阅读器能力

### 1.2 `ViffyGwaanl/papertok-reader`（本仓库，产品发行版 / private）
- 负责：阅读器 App 的产品体验（包含 PaperTok 一级入口）
- 负责：品牌化（Display Name=**Paper Reader**）与发行版标识（Bundle ID/applicationId 默认：`ai.papertok.paperreader`）
- 负责：TestFlight/签名/默认导航策略/产品文档

### 1.3 `ViffyGwaanl/anx-reader`（public fork，上游贡献工厂）
- 负责：可上游化的通用能力（AI 对话 + 翻译）
- 负责：向 `Anxcye/anx-reader` 提交 PR
- **约束**：不得混入 PaperTok/Papers Tab（避免上游 review/合并阻力）

---

## 2. 分支策略

### 2.1 Product Track（papertok-reader）
- 默认分支：`main`
- 允许：PaperTok、产品默认值、发行版差异

建议约定：
- `feat/<topic>`：功能分支（合并回 main）
- `fix/<topic>`：修复分支
- `release/<version>`：发布准备分支（可选）

### 2.2 Contrib Track（fork: anx-reader）
- 基线分支：`contrib/ai-translate`
- 只包含：AI 对话 + 翻译（不含 PaperTok）

建议约定：
- `upstream/<area>/<topic>`：用于对上游提 PR 的分支（base=upstream develop）

---

## 3. 需求分流（每次开发先做分类）

在开始实现前，先判定属于哪一类：

### A 类：上游可接受（通用增强）
典型：
- AI Provider Center / chat UX / thinking 展示
- OpenAI Responses provider
- WebDAV AI settings sync（不含 api_key）
- EPUB inline 全文翻译（沉浸式）

处理：
1) 在 `ViffyGwaanl/anx-reader` 的 `contrib/ai-translate` 上开分支实现
2) 提交上游 PR 到 `Anxcye/anx-reader:develop`
3) 合适时将改动同步到 `papertok-reader:main`

### B 类：产品专属（发行版差异）
典型：
- PaperTok/Papers Tab
- 首页导航默认值（如 papers mandatory）
- 产品文档、运营入口、私有发布策略

处理：只在 `papertok-reader` 实现，不回灌到 Contrib。

---

## 4. 同步策略（Contrib → Product）

> 原则：**只单向同步**，确保上游 PR 永远干净。

### 4.1 推荐方式：Cherry-pick（干净、可控）
- 选择合并到上游后（或已稳定）的 commits
- cherry-pick 到 `papertok-reader:main`

优点：
- 不会把上游无关历史整包带进产品仓库
- 容易做“同步窗口”的回滚/审计

### 4.2 备选：定期 merge snapshot（省事但更重）
- 把 Contrib Track 的某个稳定 tag/分支合并进产品 main

适用：当上游已大规模合并、且你不介意产品仓库历史变重。

---

## 5. 开发者命令约定（强制）

本项目忽略大量 Dart 生成文件，切分支/拉代码后必须能一键恢复可编译状态：

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

备注：`flutter test -j 1` 用于避免并发导致偶发 SIGKILL（本机已复现）。

---

## 6. 防呆（强烈建议）

由于本地会同时配置多个 remote（fork/product/upstream），为避免误 push：

- 建议使用 `git worktree` 分离两个工作目录：
  - `anx-reader-contrib/`：只连 fork + upstream
  - `papertok-reader-product/`：只连 product

这样可显著降低误操作风险。
