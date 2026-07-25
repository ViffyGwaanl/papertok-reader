# K1 Brief — 供应商中心抽包(ai_provider_kit)

> 起因:用户要把"模型供应商"能力提出来给其他 AI 项目复用,并问 GitHub 有无更好的现成替代。
> 调研结论(2026-07-24):**没有替代品**。Dart 生态只有"客户端抽象层"(langchain_dart 685⭐、flutter/ai 275⭐、llm_dart 24⭐),
> 没有任何一个提供"供应商管理层"(多供应商注册 + 多 Key 轮换与连通性 + 模型目录拉取与缓存 + 按功能选模型)。
> Cherry Studio(49k⭐)/LobeHub(81k⭐)是 TS/Electron,只能借鉴设计不能复用代码。**本仓库这套是 Dart 生态里的空白位。**
> 最后更新:2026-07-24

## 决策(agent 主动判断,已对齐用户长期拍板)

- **不推倒重构**:用户授权"可以完全重构",但重写只会得到同样的东西外加一次回归风险。真正的升级是**把它从 App 里解出来变成地基**,而不是重写。
- **抽出的是"客户端栈无关"的层**:包内**不依赖 langchain / Riverpod / Flutter UI**。现有 `LangchainAiConfig` 把归一化配置和 langchain 的 `toXxxOptions()` 焊在一起,是最大锁死点 —— 拆成包内纯 `AiEndpointConfig` + App 侧 langchain 适配。新项目用 openai_dart、裸 http 还是 langchain,包都不关心。
- **不抽 UI**(两页 1890 行):成本最高、复用价值最低(每个 App 视觉不同),且 UI 里的逻辑(测 Key、拉模型)本来就在核心层。留作可选后续批次。
- **阅读器行为零变化**:SharedPreferences 物理 key、JSON 形状、回退语义全部不变,不做数据迁移。

## 包边界

| 做 | 不做(明确划界) |
| --- | --- |
| 供应商注册表(内置目录 + 自定义)、启用/禁用 | 聊天/流式/工具调用 —— 那是 langchain/openai_dart 的活 |
| 多 API Key:轮换、冷却、连通性测试与统计 | Prompt/Agent/RAG/记忆 |
| 模型列表与能力拉取(OpenAI 兼容 / Anthropic / Gemini)+ 缓存 | UI 组件 |
| 按功能选模型(chat/翻译/标题/嵌入/重排…的通用槽位) | 账号体系、计费 |
| 配置导入导出(可选含密钥) | 服务端网关(那是 papertok.ai 代理的事,与本包正交) |

## 批次

### 批次 1 — 包骨架 + 纯核心迁移
- 建 `packages/ai_provider_kit`(纯 Dart,唯一依赖 dio),路径依赖挂进根 pubspec(与 `langchain_openai` fork 同机制,不用 workspace)。
- 迁移(逻辑不改,只搬家 + 去掉 App import):`ai_provider_meta` / `ai_model_capability` / `ai_api_key_entry` / `ai_thinking_mode` / `api_key_rotation` / `ai_models_service`。
- 新增 `AiEndpointConfig`:从 `LangchainAiConfig` 抽出**客户端无关**的归一化(含 `_deriveBaseUrl` 的 URL 后缀剥离、headers/extra 解析、merge)。App 侧 `LangchainAiConfig` 保留同名同 API,内部委托,只留 `toOpenAIOptions/toAnthropicOptions/toGoogleOptions`(358→约 150 行)。
- 新增 `AiProviderPresets` 预置目录:在现有 6 家基础上补齐常用 OpenAI 兼容站点(硅基流动/月之暗面/智谱/百炼/火山方舟/Groq/xAI/Mistral/Together/Ollama/LM Studio 等),每条带 `apiKeyUrl`(去哪申请 Key)与 `docsUrl`。**只收录能确认的地址,拿不准的不写**;`defaultModel` 只作首次填充种子,真值以拉取的模型列表为准。
- App 侧约 45 个文件的 import 机械改写(`package:papertok_reader/...` → `package:ai_provider_kit/ai_provider_kit.dart`)。
- 验证:包内 `dart analyze` + `dart test`;根 `flutter analyze`、`flutter test`(定向)、`bash tool/check_repo_budgets.sh`。

### 批次 2 — 存储接口 + AiProviderCenter + Prefs 委托
- 包内 `AiProviderKitStore`(KV 抽象,**普通值与密钥分成两组方法**,为将来 Keychain 留缝)+ `MemoryAiProviderStore`(测试/新项目开箱即用)。
- 包内 `AiProviderCenter`:供应商 CRUD、内置合并(保留用户开关)、配置读写、模型缓存、默认供应商,以及**通用 feature slot** —— 现在 Prefs 里 translate/title/imageAnalysis/libraryIndex/rerank 各手写一份 `...Effective` 回退链(≈50 行 × 5),合并成一个泛化实现,回退语义逐字保持(选中且启用 → 默认聊天供应商且启用 → 首个启用 → 兜底)。
- App 侧 `Prefs` 对应方法改为**委托**(保留 `notifyListeners()` / `touchAiSettingsUpdatedAt()` 语义),god file 变短(ratchet 只许变短,方向正确)。
- 测试:内存 store 上覆盖内置合并/upsert/删除连带清缓存/缓存回环/五种 feature slot 回退。

### 批次 3 — 连通性测试服务 + 配置导入导出
- `AiProviderTester`:包装模型拉取,返回**延迟 + 分类错误**(unauthorized / notFound / network / timeout / badResponse),供上层出人话文案(与 E3 批次 2「裸错误文案人话化」同向)。detail page 的 `_testKey` 改走它(最小 diff)。
- `AiProviderPortfolio`:导出/导入供应商配置 JSON,`includeSecrets` 显式开关,默认**不含密钥**。这是"把我的供应商搬到另一个项目"的正式答案。
- 测试:导入导出回环、密钥开关生效、错误分类。

### 批次 4 — 收尾
- 包 `README.md`(其他项目 5 分钟接入指南)、grep 清扫无残留旧 import、全套定向测试 + budgets、STATUS 行改 `待真机验收`。

## 验收(真机,全部是"和以前一样"或"更清楚")

1. 设置 → AI → 模型供应商:内置 6 家与原来一致,之前开/关的状态、自定义供应商、密钥全部还在(**升级安装验,不要全新安装**)。
2. 任一供应商详情:地址/模型/密钥照旧;点测试成功显示"N 个模型,X ms"。
3. 把密钥故意改错再测 → 显示「API Key 无效或没有权限」;把地址故意改错再测 → 显示「接口不存在,请检查 API 地址」(不再是一长串英文异常)。
4. 点获取模型列表能拉到并可选择。
5. 聊天正常出字;翻译 / 生成标题 / 图片分析 / 书库索引 / 重排 五个选择页都能正常显示与切换。
6. 关掉当前默认供应商 → 各功能自动落到下一个可用供应商;**书库索引/重排只会落到 OpenAI 兼容的那种**(不会落到 Claude/Gemini)。
7. 做一次 WebDAV 同步,确认云端 AI 设置里没有 `api_key` / `api_keys`。

## 已知短板(本次记录,不在本 brief 内修)

1. **密钥明文存 SharedPreferences**:`AiApiKeyEntry` 自己的注释就写着"含密钥、禁止同步、禁止进明文备份",但落盘仍是 App 容器里的明文 plist(靠沙箱 + 设备加密,不是 Keychain)。批次 2 先把**密钥通道在接口上分开**;真正切 Keychain 需要一次性迁移函数 + 与 WebDAV 同步(`ai_settings_sync.dart:33` 已剔除密钥)联测,单独立批次、单独真机验收。
2. **模型价格/能力目录无数据源**:`AiModelCapability` 有 pricing 字段,但除 Gemini 外几乎拉不到,S3 批次 1 的成本显示因此常年"成本未知"。选项是内置一份静态目录(类 models.dev),但要背数据陈旧的长期维护责任 —— 单独评估,不顺手做。
3. 内置目录里 `通用` 预设指向百炼且 key 是 `YOUR_API_KEY` 占位,首启体验仍是"必须先配 Key"。G0 零配置首航 + papertok.ai 免费额度代理是它的正解,与本包正交(代理只是又一个 openaiCompatible 预设)。

## 红线

- 包内禁止出现 `package:flutter`、`package:langchain*`、`package:riverpod`、`package:shared_preferences` 的 import。
- 不改任何 SharedPreferences 物理 key 与 JSON 形状;不写数据迁移;不新增兼容 fallback 层。
- 预置目录只写能确认的 URL;宁可少收录,不可编造。
- 每批收尾:包 `dart analyze` + 根 `flutter analyze` 无新增 + 定向 `flutter test` + `bash tool/check_repo_budgets.sh`;STATUS 对应行 ≤3 行。
