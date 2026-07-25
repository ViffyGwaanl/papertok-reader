# K2 Brief — 网关级可靠性(融合 new-api / CLIProxyAPI 优势)

> 起因:用户问 new-api(43k⭐)与 CLIProxyAPI(44.8k⭐)的优势能否融入。
> 两者的共同本质 = **用户与一堆不稳定上游之间的可靠性层**:失败重试、渠道冷却与自动恢复、多账号轮换、统一协议。
> 关键代码事实(2026-07-25 核实):这套语义本 App 已手写两份 —— `lib/service/ai/index.dart`(聊天,~325-490)与
> `lib/service/rag/ai_embeddings_service.dart`(嵌入,~110-300)逐行近似重复;翻译一份都没有(E2 批次1 正是"自动重试")。
> 结论:该进 `ai_provider_kit` 的路由层,不是猜想,是被写了两遍还差第三遍的需求。
> 最后更新:2026-07-25

## 取舍(逐项对照两个项目)

| 他们的优势 | 融不融 | 方式 |
| --- | --- | --- |
| new-api:失败自动重试、渠道冷却/恢复、多 Key 轮换 | **融,核心** | 提炼 App 两份手写循环成 kit 路由层;再升级出"供应商级自动回退"(App 现在没有) |
| new-api:渠道加权/模型映射 | 部分 | 回退时用目标供应商自己配置的模型,不建映射表(YAGNI) |
| new-api:计费/配额/多用户/兑换码 | 不融 | 那是 papertok.ai 代理的服务端职责(G0 已拍板形状) |
| new-api / CLIProxyAPI:自托管网关本身 | **融,以预设收编** | 预置目录加 new-api(:3000)与 CLIProxyAPI(:8317)两条,自托管用户即插即用 |
| CLIProxyAPI:订阅额度当 API 用(OAuth 包装 Claude Code/Codex 等) | 不融(明确拒绝) | 在移动 App 内做第三方 OAuth 包装有封号/ToS 风险且需常驻进程;正确姿势 = 用户在自己电脑跑 CLIProxyAPI,阅读器用预设指过去 |
| 双方:协议互转(OpenAI⇄Claude⇄Gemini) | 不融 | 我们是客户端,LangChain 适配层已做该职责 |

## 批次

### 批次 1 — kit 路由核心 + 网关预设(纯 Dart,App 行为零变化)
- `AiKeyRotationPolicy`:阈值/三档冷却(auth 60min、限流 5min、服务 1min,阈值 3),从 `api_key_policy_*` 配置键读取,默认与现网逐字一致。
- `planAiKeyAttempts`:单供应商内 Key 尝试序列 —— 可用优先、全冷却则按最早恢复排序仍要尝试、轮换指针偏移、无管理列表时退回单把 `api_key`。语义 = 现有两份手写循环的最小公倍数。
- `classifyAiFailureText` + `applyAiKeySuccess/Failure`:失败文本分类(401/429/5xx…)与 Key 统计更新的纯函数版(连续失败、按类冷却)。
- `AiProviderFailoverRouter`(**新能力,new-api 的渠道管理搬进客户端**):供应商级健康记录(连续失败→冷却→自动恢复)、回退链规划(首选→默认→其余启用且过 accept 的,冷却中的靠后)、快照可持久化。
- 预设 +2:new-api、CLIProxyAPI(端口取自各自官方默认配置)。
- 全部带包内测试;App 侧一行不改。

### 批次 2 — 翻译接入路由层(与 E2 批次1 合并执行,勿做两套)
- `lib/service/translate/ai.dart` / `ai_fulltext.dart` 改走 kit 尝试序列;失败提示用 K1 的分类文案。真机验收:断网/坏 Key/限流三种场景的行为与文案。

### 批次 3 — 聊天与嵌入两处手写循环迁移到 kit(纯去重)
- `index.dart` 与 `ai_embeddings_service.dart` 的轮换/冷却段改为调 kit,行为逐字对齐(现有测试 + 新增对照测试守护)。god file 继续变短。

### 批次 4 — 供应商级自动回退 opt-in + 路由透明度(UI,真机验收)
- 设置加"备用供应商"开关(**默认关**:自动切供应商改变成本与隐私预期,必须用户点头);生效时在结果处可见"本次由 X 完成"。文案进 ARB en+zh。

## 红线

- kit 内仍禁止 flutter/langchain/riverpod/shared_preferences import。
- 供应商级自动回退默认关闭;实际使用的供应商必须对用户可见,不许静默切换。
- 批次 3 是行为等价迁移,任何语义差异(阈值、冷却时长、指针推进时机)都算失败。
- 预设只写各项目官方默认端口;拿不准的不写。
- 每批收尾:包 `dart analyze`+`dart test`、根 `flutter analyze` 无新增、定向 `flutter test`、`bash tool/check_repo_budgets.sh`;STATUS ≤3 行。
