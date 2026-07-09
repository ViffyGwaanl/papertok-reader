# S3 Brief — 信任快赢集(成本可见 / CBZ / 隐私可见化 / 零配置查词)

> 前置:无技术依赖。定位:四个"数据/引擎已就绪、只缺最后一层"的小批次,不单独占用真机验收带宽——**随 S1/S2/P6 的验收 build 搭车验收**,不为本 brief 单独出包。
> 来源:2026-07 竞争力审查快赢簇(发现 5/6/8/3),全部经代码核实。
> 用户拍板(2026-07-09):按推荐执行。
> 最后更新:2026-07-09

## 批次 1 — 研讨会花费估算展示

- 现状:`lib/service/ai/ai_seminar_runtime_service.dart` 已按 provider/model 单价实时算出 `estimatedCostUsd`/`billingSnapshot`,但全仓库 `lib/widgets/`+`lib/page/` 无一处引用——BYOK 用户对花费完全无感。
- 做法:研讨收尾卡(completed 状态)加一行"本次估算成本 ≈ $X.XX"(有 pricing metadata 时才显示;缺价目时显示既有的"成本未知"原因,不编数字);文案进 ARB en+zh。纯 UI 挂载,不动 runtime 计算。
- 验证:跑一场研讨,收尾卡显示估算;切到无 pricing metadata 的 provider,不显示或显示"成本未知"。
- commit:`feat(seminar): show estimated run cost on completed card (S3 batch 1)`

## 批次 2 — CBZ 漫画格式放行

- 现状:`lib/utils/book_file_types.dart:8` 的 `kAllowBookExtensions` 不含 cbz,但 foliate-js 的 `isCBZ()`/`makeComicBook()`(`assets/foliate-js/src/book.js:466-488`、`comic-book.js`)是完整实现;导入弹窗还把白名单原样展示给用户。"引擎支持却不让用"。
- 做法:白名单加 `cbz`;导入弹窗文案随白名单自动更新;真机导入一本 cbz 验证翻页/封面正常。注意:漫画无文字层,AI 功能对 cbz 显示为不可用是预期行为,不要为它加假降级。
- 验证:导入 cbz 正常阅读;epub 回归不受影响。
- commit:`feat(reader): allow cbz comic import (S3 batch 2)`

## 批次 3 — "本地优先/隐私"可见化

- 现状:`aboutPrivacyPolicy` 字符串在 en/zh ARB 里存在但**从未被任何 Dart 文件引用**;无隐私说明页;无"书籍文本会发送给你配置的 LLM provider"披露。行为上隐私主张是真的(opt-in 同步、无第三方 SDK),产品里完全不可见。
- 做法:① 关于页挂接 `aboutPrivacyPolicy` 入口,打开一个静态说明页(本地渲染,不联网):数据存哪里、什么情况下离开设备(WebDAV 由你配置、AI 调用发给你选的 provider)、我们不运营收集数据的服务器;② 设置-同步区加一句常驻说明文案。全部文案 ARB en+zh。
- 验证:关于页可打开隐私说明;文案与实际行为一致(不许夸大,例如 PaperTok feed 请求 papertok.ai 属于联网行为,要如实写)。
- commit:`feat(settings): surface privacy & data-locality page (S3 batch 3)`

## 批次 4 — 零配置查词兜底(iOS 先行)

- 现状:选区菜单里唯一免配置动作"Search"是跳出 App 去 Bing;"翻译"必须先配 AI provider。未配 Key 的用户查一个生词只能离开 App,而查词是阅读 App 最高频动作(Kindle/微信读书都是离线免配置词典)。
- 做法:iOS 用系统自带 `UIReferenceLibraryViewController`(离线、免费、零配置、支持中英)做 platform channel,选中词直接弹系统词典。**入口位置服从 E4 决策清单**(一级菜单 5 项已拍板):词典动作放入"问 AI"二级面板或与翻译并列,由 E4 批次 4 执行时一并落位;若 S3 先做,入口暂挂现有菜单,E4 重排时迁移。Android 词典兜底记入 P7 批次 1 的检查项,本批不做。
- 验证:未配置任何 AI provider 的新装机,选中英文/中文词,能在 App 内弹出系统词典。
- commit:`feat(reader): zero-config dictionary lookup via system dictionary (S3 batch 4)`

## 红线

- 不引第三方词典/分析 SDK;批次 4 只用系统能力。
- 批次 1 不得改研讨 runtime 逻辑,只读已有快照字段。
- 与 E4 的选区菜单重排协调,不制造两套入口。
- 每批收尾:`flutter analyze` 无新增 + `flutter test` + `bash tool/check_repo_budgets.sh`;STATUS 对应行 ≤3 行。
