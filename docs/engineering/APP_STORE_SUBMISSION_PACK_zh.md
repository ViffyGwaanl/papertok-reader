# App Store 提审材料包草稿（PaperTok Reader）

> 目的：为 `PaperTok Reader` 正式提交 App Store 审核准备一套可直接落地的材料草稿。
>
> 本文档覆盖：
> - Review Notes 草稿
> - 商店文案草稿（中/英）
> - 截图清单（iPhone / iPad）
> - 隐私 / 支持信息清单
>
> 配合文档：
> - `docs/engineering/APP_STORE_READINESS_AUDIT_zh.md`
> - `docs/engineering/IOS_IPADOS_QA_CHECKLIST_zh.md`

---

## 1. Review Notes 草稿

> 建议直接在 App Store Connect 的 Review Notes 中填写英文版本。
> 如果审核员需要路径说明，可以把“测试路径”按条列形式直接粘进去。

### 1.1 Review Notes（English draft）

```text
PaperTok Reader is an AI-powered reading and content exploration app for books and visual paper cards.

Primary user flows for review:
1. Open the app and go to the AI tab on the Home screen.
2. In the AI tab, send a text prompt directly, or attach images/files to test multimodal chat.
3. Go to the Papers tab to browse paper cards with images, open details, and test favorites.
4. Open any imported book and use in-reader AI chat / translation features.

Important notes for review:
- The app does not require a social account to browse the main UI.
- If a specific AI provider configuration is required for full AI output during review, please use the review configuration / test account provided in App Review Information.
- The app supports importing content through the iOS share sheet and shortcuts flows. If needed, this can be tested by sharing supported files/images into PaperTok Reader.
- Photo access is used for selecting images to analyze or send in AI chat.
- Camera access is used for capturing images for analysis.
- Calendar / Reminders access is only used when the user explicitly invokes those features.
```

### 1.2 Review Notes 待补人工信息

以下内容需要你在正式提交前补齐：

- [ ] 审核专用测试账号（如果 AI 功能不能匿名直接验证）
- [ ] 审核环境默认 provider 是否可直接使用
- [ ] 是否需要在 Review Notes 中明确某些功能入口为“可选/实验性”
- [ ] 是否需要补充分享导入 / shortcuts 的测试步骤

---

## 2. 商店文案草稿

> 原则：先用“稳妥、易审、不过度承诺”的版本，不把产品定位写得过重或过花。

### 2.1 App Name

- `PaperTok Reader`

> 当前代码与显示名已经统一到这个名称。

### 2.2 Subtitle（英文草稿）

可选版本 A：
- `Read, explore, and chat with AI`

可选版本 B：
- `AI reading, papers, and translation`

可选版本 C：
- `Books, paper cards, and AI chat`

### 2.3 Subtitle（中文草稿）

可选版本 A：
- `用 AI 阅读、探索与对话`

可选版本 B：
- `AI 阅读、论文卡片与翻译`

可选版本 C：
- `书籍、PaperTok 与 AI 对话`

### 2.4 Keywords（英文草稿）

```text
ai reader,reading,books,papers,translation,chat,pdf,epub,study
```

### 2.5 Keywords（中文草稿，仅供整理思路）

```text
AI阅读,读书,论文,翻译,对话,EPUB,PDF,学习,书籍
```

> 最终 ASC keywords 仍建议用英文为主，并控制长度。

### 2.6 Promotional Text（英文草稿）

```text
Explore books and paper cards with AI chat, image/file attachments, translation, and interactive reading workflows.
```

### 2.7 Description（英文草稿）

```text
PaperTok Reader helps you read, explore, and interact with content using AI.

Key features:
- AI chat with text, images, and supported file attachments
- PaperTok card browsing with image-rich paper feeds
- In-reader AI assistance while reading books
- Translation support for reading workflows
- Favorites and content exploration tools
- Share and shortcuts integration for faster input flows

PaperTok Reader is designed for readers who want to move between content discovery, reading, and AI-assisted understanding in one place.
```

### 2.8 Description（中文草稿）

```text
PaperTok Reader 是一款结合 AI 对话、内容探索与阅读体验的应用。

核心能力包括：
- 支持文本、图片与文件附件的 AI 对话
- 浏览图片丰富的 PaperTok 论文卡片流
- 阅读书籍时使用 AI 辅助理解
- 支持翻译等阅读增强能力
- 收藏与内容探索工具
- 分享与快捷指令集成，加快输入流程

PaperTok Reader 适合希望把内容发现、阅读与 AI 理解整合在一起的用户。
```

---

## 3. 截图清单

> 目标：先准备一套“可过审、能讲清主功能”的截图，不追求花哨。
>
> 推荐至少准备：
> - iPhone：6.9" 或 6.5" 一套
> - iPad：13" 或 12.9" 一套（如果继续支持 iPad）

### 3.1 iPhone 截图建议（5 张）

#### 图 1：首页 / AI Tab
- 画面：AI Tab 主界面
- 重点：输入框、聊天区、底部 TabBar 风格
- 目的：让审核员和用户一眼知道“这是 AI 阅读 / 对话产品”

#### 图 2：多模态 AI 对话
- 画面：带图片/文件附件的 AI 对话
- 重点：附件能力、消息结构
- 目的：体现核心 AI 使用方式

#### 图 3：PaperTok 论文卡片流
- 画面：Papers Tab，全屏卡片+图片
- 重点：图片驱动的 paper feed
- 目的：体现与普通阅读器不同的内容探索特征

#### 图 4：阅读页 + AI 辅助
- 画面：书籍阅读页，带 AI 面板/翻译入口
- 重点：阅读场景中的 AI 帮助
- 目的：说明主场景不是纯聊天，而是阅读增强

#### 图 5：编辑附件 / 图片查看 / 收藏等增强体验
- 画面：用户消息附件查看 / Paper 收藏 / 细节体验之一
- 重点：展示完成度
- 目的：提升可信度

### 3.2 iPad 截图建议（4-5 张）

#### 图 1：首页 / AI Tab（大屏）
- 展示 iPad 更宽的对话布局

#### 图 2：阅读页 + AI / dock / bottom sheet
- 强调 iPad 的阅读工作流体验

#### 图 3：PaperTok feed 大屏效果
- 展示大图内容体验

#### 图 4：多模态 AI 附件能力
- 展示多张图片或文件附件输入

#### 图 5（可选）：Provider Center / 高级功能
- 如果想突出“可配置、面向高级用户”的差异点，可放这一张

### 3.3 截图生产注意事项

- [ ] 使用真实、稳定、不含敏感信息的内容
- [ ] 避免测试文案、错误弹窗、调试信息出现在截图里
- [ ] 如果需要展示 AI 回答，尽量使用稳定、通顺的示例内容
- [ ] 不要在截图里出现需要用户自己配置 key 才能理解的内容
- [ ] 同一组截图尽量统一视觉风格与语言

---

## 4. 隐私 / 支持信息清单

### 4.1 需要补齐的 URL

以下是正式提审前建议一定准备的 URL：

- [ ] `Support URL`
- [ ] `Privacy Policy URL`
- [ ] `Marketing URL`（可选）

### 4.2 推荐 URL 结构（示意）

> 下面只是建议路径，最终请替换成你实际可访问的地址。

- `https://papertok.ai/support`
- `https://papertok.ai/privacy`
- `https://papertok.ai`

### 4.3 Support 页面至少应包含

- 产品名称：PaperTok Reader
- 联系方式（邮箱）
- 常见问题：
  - AI 对话如何使用
  - 图片/文件附件如何发送
  - 书籍导入如何使用
  - PaperTok 是什么
- 问题反馈入口

### 4.4 Privacy Policy 至少应覆盖

- 会处理哪些用户内容（文本、图片、文件）
- 是否会把内容发送给第三方 AI provider
- 是否会使用日志 / 崩溃 / 分析数据
- 数据是否与身份关联
- 是否用于广告追踪（如果没有，明确写无）
- 用户如何联系支持与删除数据（如果适用）

### 4.5 App Privacy 问卷准备说明

> 此项需要你在 ASC 后台人工填写，但建议先按功能清点。

待确认清单：
- [ ] 是否收集用户上传的文本/图片/文件内容
- [ ] 是否与账户或设备标识关联
- [ ] 是否有 analytics / diagnostics / crash reporting
- [ ] 是否有第三方 AI provider 处理用户内容
- [ ] 是否存在跨应用/跨站点追踪（默认应无）

---

## 5. 审核员可验证性清单

> Apple 审核最常卡的不是代码，而是“审核员能不能无障碍验证你的主功能”。

### 当前建议

- [ ] 审核员无需找你要 key，也能体验主功能
- [ ] 审核员无需复杂配置，也能进入 AI chat 主路径
- [ ] 审核员可以看到至少一个明确的核心亮点：
  - AI chat
  - PaperTok cards
  - 阅读页 AI
- [ ] 如果有分享导入 / shortcuts 作为亮点，需要在 Review Notes 中写清测试方式

---

## 6. 提审前建议的最终动作

### Step 1：冻结 build
- 选定准备提审的 build
- 不再继续叠高风险功能改动

### Step 2：跑 QA
- 以冻结 build 跑 iPhone + iPad checklist
- 记录 blocker

### Step 3：补 ASC 材料
- Review Notes
- Metadata
- 截图
- Support/Privacy URL
- App Privacy 问卷

### Step 4：正式提交审核
- 提交 App Store Review

---

## 7. 当前最适合继续补的内容

按照性价比排序，建议后续优先完成：

1. `Review Notes` 最终版
2. `Support URL / Privacy Policy URL` 页面
3. iPhone / iPad 商店截图
4. 冻结版 QA 执行结果记录
