# QA 方法论（跨平台，可复现，可回归）

如果说 `docs/engineering/*_QA_CHECKLIST_zh.md` 是“要检查哪些按钮”，那本文就是“为什么要这样检查，以及怎样把结果变成可用的工程信号”。

你可以把一次高质量 QA 想象成做一道物理实验。

实验不是“看起来差不多就行”，而是把变量锁住，让别人按同样步骤也能得到同样结论。

## 1. 我们在验证什么

一次 QA 的目标是回答三个问题。

第一，这一版能不能完成用户的关键任务。

第二，这一版有没有引入回归。

第三，这一版有没有明显的稳定性或资源风险，导致“短期能用，长期会炸”。

为了让结果更像一份严谨的报告，我们把验证内容拆成九个维度。每次 QA 不一定全覆盖，但必须清楚写出本次覆盖了哪些。

- 功能正确性
- 跨平台一致性
- 内容与渲染
- 离线与网络
- 同步与迁移
- 性能与资源
- 稳定性与恢复
- 权限与隐私
- 可用性与可达性

## 2. 一次 QA Session 的三段式节奏

推荐把一次 QA 控制在 60 到 120 分钟。节奏分三段。

第一段是冒烟测试。你只要证明底座没塌。

第二段是围绕本次风险点深挖。用“任务卡”驱动，而不是漫无目的地点。

第三段是回归对比。把历史最容易坏的点快速过一遍，并尽量与基线版本对比。

## 3. 环境记录

环境记录不是为了写得多，而是为了把关键变量写全。

你可以直接复制下面这段当作每次 QA 的开头。

```text
App:
- 分支/渠道: (product/main, TestFlight, APK...)
- Version / Build:
- Commit hash: (可选)
- 安装方式: 升级安装 / 全新安装

Device:
- 平台: iOS / Android / macOS
- 设备型号:
- OS 版本:
- 语言/地区:
- 时区:

Runtime:
- 网络: Wi-Fi / 蜂窝 / 离线 / 弱网
- 账号: (脱敏)
- 关键开关: (例如 Responses compat toggles, Memory semantic override)
- 测试样本: (你选的三本书)
```

常见坑是只写“最新版”。这种记录等于没写。

## 4. 如何避免假阳性

遇到问题后，先做三件便宜又有效的事。

第一，用同样路径重试一次，确认不是偶发手误。

第二，冷启动再复现一次，确认不是瞬时 UI 状态。

第三，确认安装形态。升级安装和全新安装对迁移类 bug 是两种世界。

如果问题依赖网络，再做一次网络切换或飞行模式验证。

## 5. 回归分诊

判断回归最有用的两个信息是。

- Last Known Good (LKG)
- First Known Bad (FKB)

你不一定每次都能精确给出，但只要你在基线版本上跑一遍同样路径，就能把问题从“猜测”变成“证据”。

## 6. 严重程度（Severity）

你可以用下面这张表给问题定性。

- S0 Blocker：阻断发布或核心链路完全不可用
- S1 Critical：核心体验严重受损或有数据风险
- S2 Major：重要功能异常但影响面有限或有 workaround
- S3 Minor：不影响主要任务但影响体验
- S4 Trivial：微小瑕疵或建议

## 7. 标准 bug 报告模板

把下面模板当成“工程可用”的最低标准。

```markdown
## Title
[Platform] [Module] 动作 + 结果 + 条件

## Environment
- Version/Build:
- Install method:
- Device/OS:
- Network:
- Key toggles:

## Steps
1.
2.
3.

## Expected

## Actual

## Frequency

## Evidence
- Screenshot/Screen recording:
- Logs:

## Notes
- Workaround:
- Regression (LKG/FKB):
```

当你能提供“复现步骤 + 证据 + 环境”，修复速度会从“天级”变成“小时级”。

## 8. 与本项目的结合

- deep link 规范：`paperreader://reader/open?bookId=...&href=...` 或 `...&cfi=...`（见 `docs/engineering/IDENTIFIERS_zh.md`）。
- Phase 3 关键链路：AI 索引（书库）队列 + `semantic_search_library` evidence jumpLink。
- Memory 关键链路：Markdown source-of-truth + `memory_index.db` 派生索引 + 语义检索 Auto-on + A–D（对齐 OpenClaw）。
- OpenAI Responses：第三方网关兼容开关 `responses_use_previous_response_id` / `responses_request_reasoning_summary`。
