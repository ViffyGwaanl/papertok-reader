# Product North Star

## 1. 北极星体验

PaperTok Reader 的未来形态不是“阅读器旁边加一个聊天框”，而是：

> 用户读到不懂的地方，点一下，就能拉起一场有证据、有分歧、有总结、能沉淀、能复习、能跳回原文的学习讨论。

这句话是所有 Epic 的验收方向。任何新能力如果不能改善阅读理解、证据追踪、知识沉淀或复习闭环，就不进入本计划。

## 2. 产品定位

PaperTok Reader 未来应成为本地优先的 AI 深度学习阅读器：

- 阅读页是主场：选中文本、图片、章节标题或概念即可触发 AI 学习动作。
- AI Seminar 是旗舰体验：多个角色围绕书内证据讨论，而不是无来源的角色扮演。
- KnowledgeCard 是沉淀单位：高亮、笔记、AI 摘要、Seminar 结论、RAG evidence、图片分析都能进入同一知识对象。
- ConceptGraph 是理解结构：概念、实体、论点、关系和证据形成局部可探索网络。
- Review 是写入门：AI 生成内容默认进入 Review，用户确认后才成为知识资产。

## 3. 外部项目融合决策

| 来源 | 借鉴能力 | PaperTok 决策 | 不做什么 |
| --- | --- | --- | --- |
| OpenMAIC | 多角色讨论、Reading Director、Shared Whiteboard、Action Protocol | 建 PaperTok 原生 AI Seminar，角色由服务层编排，所有结论带证据。 | 不复刻完整 Web 课堂，不复制 AGPL 代码，不做热闹但无沉淀的角色秀。 |
| MarginNote | 摘录卡、脑图节点、flashcard、源文档双向跳转 | 建 KnowledgeCard 和 Review/Spaced Review，将卡片绑定 source ref。 | 不先做复杂无限画布，不强迫用户手动整理所有材料。 |
| WikiLinks | 概念页、关联路径、局部知识探索 | 建 Concept Dossier 和局部概念探索路径，保留返回阅读位置。 | 不做完整 Wikipedia 客户端，不默认联网补全知识。 |
| Understand-Anything | 概念图谱、关系抽取、影响分析思路 | 把书库 chunk、卡片、笔记转成有证据的 ConceptGraph。 | 不把它的代码库分析产品照搬到移动端运行时。 |

## 4. 关键用户旅程

### 4.1 读中讨论

1. 用户选中文段。
2. 点击 `Seminar`。
3. 系统基于 current book 取证据，默认不开 web。
4. `critical / supportive / synthesizer` 角色生成有来源的讨论。
5. 系统产出候选 KnowledgeCard 和复习题。
6. 用户确认后进入 Review 或卡片库。

### 4.2 跨书理解

1. 用户在 AI 面板或概念页提出主题。
2. 系统使用 library RAG 和 ConceptGraph 找相关书内证据。
3. AI Seminar 比较不同书的解释、冲突和例子。
4. 输出 Concept Dossier、关联路径和可跳回原文的证据列表。

### 4.3 长期复习

1. 用户确认卡片或复习题。
2. Review 系统记录来源、状态和复习历史。
3. 到期复习时，用户可以答题、看解释、跳回原文、重新开 Seminar。
4. 错误和模糊概念回流到 ConceptGraph 和下一次 Study Session。

## 5. 产品级非目标

- 不做独立 OpenMAIC clone。
- 不做完整 Wikipedia/WikiLinks clone。
- 不做 MarginNote 式全量手动知识管理套件。
- 不把 AI 生成内容静默写进长期记忆、笔记、标签或同步产物。
- 不把派生索引当作跨设备 source-of-truth。
- 不在移动端默认并行跑大量子 agent。

