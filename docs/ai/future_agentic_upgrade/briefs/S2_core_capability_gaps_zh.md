# S2 Brief — 核心能力缺口修复(PDF AI 取证 / KnowledgeCard 主页)

> 前置:无,不受体验重建期冻结规则约束(与 S1、P6 批次5 同为例外)。理由同 S1:两项都是"承诺的功能对用户不存在/不可达",不是"体验不够好"——批次1让"有据可查"这条核心定位对 PDF 书籍完全失效,批次2让最高频的存卡动作变成黑洞。都只碰各自独立模块,不touch `ai_chat.dart`/`seminar/`/`book.js`/`database.dart`/`ai_chat_stream.dart` 等高风险区,和 R2/R3 无技术依赖。
> 来源:2026-07 竞争力/产品缺口审查(6镜头、7个agent交叉核实)。
> DoD:2 项逐一验证 + 回归测试;真机验收通过后收口。
> 最后更新:2026-07-09

## 批次 1 — PDF 书籍对全部 AI 取证工具静默返回空内容

- 根因:`assets/foliate-js/src/pdf.js` 的 `makePDF()`(:568-614)给每个 section 只赋值 `{id, load, size}`,`load()` 只把整页渲染成图片 URL(`renderPage`,:496),**没有实现 `createDocument`**。而 `book.js` 里所有面向 AI 的抓取函数都会显式短路:`getChapterContentByHref`([:1370](../../../../assets/foliate-js/src/book.js))、`getBookContent`([:1416](../../../../assets/foliate-js/src/book.js))都是 `if (!section?.createDocument) return ''`/`continue`。这条链路正是 `lib/service/rag/library/ai_headless_reader_bridge.dart`、`current_book_fulltext_tool.dart` 等全部 AI 工具实际调用的链路——不分是否扫描版,**今天 100% 的 PDF 书籍**(含 Papers/arXiv 论文 feed 下载的 PDF,走的是同一条导入管线)对 AI 提问都是零原文依据。
- 做法:给每个 section 补一个 `createDocument` 异步方法,复用 `renderPage` 里已经调用的 `page.getTextContent()`([:526](../../../../assets/foliate-js/src/pdf.js))取到的文字位置数据,拼成一段合理阅读顺序的正文(按 `item.transform` 的 y 坐标分行/分段),再用 `DOMParser` 包成一个有 `body`/`documentElement`/`createRange()` 的 `Document`——`book.js` 的 `#getOriginalTextContent(doc?.body)` 和 `doc.createRange()` 都要求这个形状,参考 `epub.js:959` `createDocument: () => this.loadDocument(item)` 的既有模式,不要自己发明新接口。
- 边界:只解决"能不能拿到文字",不做 OCR(扫描版 PDF 本来就没有文字层,`getTextContent()` 对扫描页返回空是预期行为,不在本批次范围,继续留给 `docs/ai/pdf_ai_chaptering_and_ocr.md` 规划的 OCR 路径);不改分页渲染(`renderPage`/`load()` 保持不变,用户阅读体验不受影响,只新增取文字的旁路)。
- 验证:导入一本文字层完整的 PDF(非扫描版),在 AI Chat 里问一个只有该 PDF 才有答案的问题,回答必须带书内引用而非空/瞎编;`current_book_fulltext_tool`/`book_content_search_tool`/`semantic_search_current_book_tool` 补一条 PDF fixture 测试;`flutter test` 全绿。
- commit:`fix(pdf): implement createDocument for AI text extraction (S2 batch 1)`

## 批次 2 — KnowledgeCard 本体没有主页,存卡后即从用户视角消失

- 根因:四个卡片生产者(`lib/service/knowledge/{selection,ai_chat,rag_evidence,image_analysis}_knowledge_card_producer.dart`)的唯一 UI 调用点 `lib/widgets/context_menu/excerpt_menu.dart:293` 写死 `createReviewItem: false`,卡片永远停在 `draft` 状态;全仓库 `lib/page/` 下没有任何页面引用 `KnowledgeCardStore`;详情页 `lib/widgets/knowledge/knowledge_card_detail_page.dart`(138行)没有任何操作按钮,`card.reviewState.asString` 把原始英文 enum 值直接渲染成正文。用户存卡后除非当场点 SnackBar 里的"查看",这张卡就彻底从视野消失,直到世界尽头停留在本地 `.knowledge/knowledge_cards_v1.json` 里。对照组:同样源自 Seminar 的"加入复习"/"加入图谱"两个动作已各自有独立浏览页(`SpacedReviewPage`/`ConceptGraphExplorerPage`),说明底层 store/状态机/`applyReviewDecision` 都是好的,只是 KnowledgeCard 本体这个对象类型本身漏做了主页。
- 做法:① 新增 `lib/page/knowledge/knowledge_card_list_page.dart`(参考 `ConceptGraphExplorerPage`/`SpacedReviewPage` 的既有列表页模式),列出 `KnowledgeCardStore` 里全部卡片,分组或筛选 draft/approved/applied 状态,点击进详情页;② 入口挂在既有导航里合理的位置(例如"我的"/统计/设置区,不新增顶级 tab,避免撞上 E4 减法方向);③ 详情页补操作按钮:跳转来源(复用既有 `PaperReaderReaderIntent`/jump audit)、提交审核(把 `createReviewItem` 打开或调用 `applyReviewDecision`)、删除;④ `reviewState.asString` 换成人话文案(进 ARB),不展示裸 enum 值。
- 边界:不改变四个 producer 的默认 `createReviewItem: false` 行为本身是否合理(那是另一个产品判断,若要改默认值需要额外拍板)——本批次的最小闭环是"用户能找到并操作自己存过的卡",不是"改变卡片默认审批流程"。
- 验证:阅读页选中文本存一张知识卡,不点 SnackBar 查看,切到其他页面再回来,能在新列表页里找到这张卡;点开详情页能跳回原文、能提交审核、能删除;`flutter test` 覆盖列表页/详情页新增交互。
- commit:`feat(knowledge): add KnowledgeCard list page and detail actions (S2 batch 2)`

## 验证规程(每批通用)

```bash
flutter analyze  # 无新增
flutter test     # 全绿(相对基线:1115 passed / 2 skipped / 7 failed,后者均为存量 flaky)
bash tool/check_repo_budgets.sh
```

## 红线

- 不做 OCR、不碰扫描版 PDF 判定逻辑(留给 P2/`pdf_ai_chaptering_and_ocr.md`)。
- 不改四个 KnowledgeCard producer 的默认审批策略,只补可达的操作入口。
- 每批结束更新 `STATUS_zh.md` 对应行(≤3 行)+ commit message,不新增其他文档。
