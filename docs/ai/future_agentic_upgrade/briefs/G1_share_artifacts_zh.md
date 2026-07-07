# G1 Brief — 分享资产三件套

> 前置:体验重建期收口(A/B/C 线,见 `../EXPERIENCE_REBUILD_PLAN_zh.md`);研讨实录长图依赖 R2 后的干净事件流。
> DoD:三种可分享产物(书摘卡 2.0 / 研讨会实录长图 / 读书报告)均可一键生成精美图片并调起系统分享;真机验收通过;用户主观认可"愿意发朋友圈"。
> 最后更新:2026-07-03

## 为什么(一句话)

读书 app 的自发传播靠的不是功能,是**好看的产出物**(微信读书书摘卡、Spotify Wrapped 先例);本 app 独有的研讨会实录是全市场没有的分享素材。

## 批次

1. **现状审计(先看后做)**:通读 `lib/widgets/book_share/excerpt_share_card.dart` + `excerpt_share_bottom_sheet.dart` + `lib/utils/share_file.dart`,产出 ≤20 行差距清单(现有卡片渲染什么、缺什么、样式基线),贴在本批 commit message,不新建文档。
2. **书摘卡 2.0**:升级现有卡片——书封+书名+作者+页码出处、2–3 套排版模板(引文长短自适应)、Claude/terracotta 设计系统配色、可选 app 名或二维码角标(按用户拍板)。渲染走 `RepaintBoundary`→图片,复用现有分享通道。
3. **研讨会实录长图**:从研讨事件流(R2 后的 `AgentRunGraphStore`)选材渲染长图:书封 + 议题 + 各角色最锋利的 1–2 条观点(带角色标识)+ 1–2 条书内证据引文(带出处)+ 结论摘要。入口放研讨结束后的收尾卡上。**引文必须带出处,无证据结论不上卡**(红线)。
4. **读书报告(月/年)**:复用 `lib/widgets/statistic/`(热力图、时长、书目)生成竖版长图:本月/本年读了 N 本/N 小时、最长连续、划线最多的书、一条年度最佳书摘。入口在统计页;12 月默认引导年度版。
5. **收尾**:三件套 ARB(en+zh)、暗色模式渲染正确、iPad 尺寸、真机验收。

## 验收(真机,用户执行)

1. 阅读页选中一段 → 分享 → 卡片美观、出处完整、可存图/调起系统分享。
2. 跑完一场研讨 → 收尾卡点分享 → 长图含角色观点与带出处引文,截断合理不溢出。
3. 统计页生成月度报告长图,数据与统计页一致。
4. 三件套在暗色模式与 iPad 上渲染正常。

## 红线

- 不引第三方分享/分析 SDK(用现有 `share_file.dart` 通道)。
- 分享图上的 AI 结论必须可溯源;引文不得截断到失真。
- 不动阅读器选区逻辑与 `book.js`(入口复用现有选区菜单)。

## 验证命令

```bash
flutter analyze && flutter test test/widgets/book_share/ 2>/dev/null; flutter test
bash tool/check_repo_budgets.sh
```

commit 格式:`feat(share): <批次> (G1 batch N)`
