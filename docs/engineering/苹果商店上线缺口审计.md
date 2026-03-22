# App Store 上线缺口审计（PaperTok Reader）

> 目的：评估当前仓库与发布状态，判断距离正式提交 Apple App Store 审核还差哪些关键项。
>
> 说明：本清单分为两类：
> - **仓库内可验证**：可通过代码、文档、配置、工作流直接确认
> - **ASC / Apple 后台需人工确认**：仓库内无法确认，需去 App Store Connect / Apple Developer 后台核对

---

## 1. 总体结论

- 当前状态：**技术发布通路已具备，正式上架准备未完全收口**
- 粗略判断：
  - **构建 / 上传 / TestFlight readiness**：80-90%
  - **正式 App Store 上线 readiness**：60-70%

一句话：

> 现在不是“不能上”，而是“还缺最后一轮提审材料、审核说明与发布级 QA 收口”。

---

## 2. 仓库内可验证项

### 2.1 发布通路

- [x] iOS App Store 构建导出配置存在
  - `ios/ExportOptions-AppStore.plist`
  - `ios/ExportOptions-AppStore-Manual.plist`
- [x] App Store Connect 构建工作流存在
  - `.github/workflows/build-appstore.yaml`
- [x] dSYM / symbols 上传已配置
  - `ios/ExportOptions-AppStore.plist` 中启用 `uploadSymbols`
- [x] TestFlight 内外测链路已跑通
  - 当前已跑到 `1.68.5 (6367)`
- [ ] 正式 App Store 提审 SOP 未沉淀完整
  - 当前 `docs/engineering/IOS_DEPLOY_zh.md` 主要覆盖真机安装与 TestFlight 分发，不是完整正式提审 runbook

### 2.2 QA / 平台验证

- [x] iOS / iPadOS QA checklist 已存在
  - `docs/engineering/IOS_IPADOS_QA_CHECKLIST_zh.md`
- [x] 平台测试状态文档已存在
  - `docs/engineering/PLATFORM_TEST_STATUS_zh.md`
- [x] 文档中明确 iPhone / iPad 已验证
- [ ] 最近一轮“冻结 build 的正式提审 QA 完成记录”未见明确沉淀
- [ ] Android 系统性回归未完成
  - `docs/engineering/PLATFORM_TEST_STATUS_zh.md`
- [ ] 桌面端系统性验证未完成
  - `docs/engineering/PLATFORM_TEST_STATUS_zh.md`

### 2.3 App Store 元数据 / 素材（仓库资产）

- [ ] iOS App Store metadata 资产未见
- [ ] iPhone / iPad App Store 截图资产未见
- [ ] iOS 商店描述 / subtitle / keywords 文件未见
- [x] `fastlane/metadata` 目录存在
- [ ] 但当前仅发现 Android metadata
  - `fastlane/metadata/android/...`

### 2.4 权限 / 隐私基础配置

- [x] `Info.plist` 中已有主要权限文案
  - Camera
  - Photo Library
  - Calendar
  - Reminders
- [ ] 照片权限文案与实际用途可能不完全匹配
  - 当前 `NSPhotoLibraryUsageDescription` / `NSPhotoLibraryAddUsageDescription` 均为 “save images” 口径
  - 但产品实际也有“读取/选择图片用于分析/发送”的场景
- [ ] 仓库中未见 Privacy Policy 落地页/文档资产
- [ ] 仓库中未见 Support URL / Marketing URL 沉淀

### 2.5 审核辅助材料

- [ ] Review Notes 模板未见
- [ ] 审核专用测试路径说明未见
- [ ] 审核测试账号/演示账号资料未见
- [ ] AI 主功能在“无人工协助”下如何被审核员验证，未见文档沉淀

---

## 3. ASC / Apple 后台需人工确认项

> 这些项目仓库内无法确认，默认视为“待人工确认”。

- [ ] App Privacy 问卷是否已完整填写
- [ ] Support URL 是否已配置
- [ ] Privacy Policy URL 是否已配置
- [ ] Marketing URL 是否已配置（如需要）
- [ ] 分类 / 年龄分级 / 地区 / 定价是否已配置
- [ ] Export Compliance 是否已确认
- [ ] App Review Information 是否已填写
- [ ] 审核员是否有可直接验证主功能的账号/路径
- [ ] 如果涉及 AI provider / key，审核员是否能在无外部协助下体验主流程

---

## 4. 高优先级缺口（P0）

以下是正式提审前建议必须收口的项：

- [ ] 跑一轮冻结 build 的 iPhone + iPad 正式 QA
- [ ] 准备 iOS App Store 截图素材
- [ ] 准备 App Store metadata
  - App Name
  - Subtitle
  - Keywords
  - Description
  - Promotional Text（可选）
- [ ] 准备 Review Notes
- [ ] 确认审核员可实际进入 AI 主功能
- [ ] 补齐 Privacy Policy / Support URL
- [ ] 校准权限用途文案（至少照片权限）

---

## 5. 次优先级缺口（P1）

- [ ] Android / 桌面端发布级验证
- [ ] 更完整的线上崩溃 / 观测材料
- [ ] 更明确的商店页品牌文案统一
- [ ] 若后续涉及订阅 / 收费，补 IAP / Restore / 合规路径

---

## 6. 建议的下一步执行顺序

### Wave 1：提审材料包
- [ ] Review Notes 草稿
- [ ] 商店文案草稿
- [ ] 截图清单
- [ ] 隐私/支持信息清单

### Wave 2：冻结版 QA
- [ ] 以当前准备提审的 build 跑完整 iPhone / iPad checklist
- [ ] 记录 blocker 与结论

### Wave 3：ASC 后台补齐
- [ ] App Privacy
- [ ] Support / Privacy URL
- [ ] Review Information
- [ ] 分类 / 分级 / 定价 / 地区

### Wave 4：正式提交审核
- [ ] 选定提审 build
- [ ] 提交 App Store Review

---

## 7. 当前判断（简版）

- **能发 TestFlight**：是
- **能切内外测**：是
- **能正式提审**：技术上可以
- **现在就建议提审**：**不建议直接提**
- **原因**：提审材料与审核可验证性还没完全收口
