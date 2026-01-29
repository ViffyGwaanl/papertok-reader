# Changelog

## 1.12.0
- Feat(reader): Add heading font size adjustment slider
- Feat(reader): Add glassmorphism history navigation capsule in reader
- Feat(reader): Support manual control of history navigation visibility (no auto-hide)
- Feat(reader): Support manually selecting and remembering day/night background image preference
- Feat(reader): Support custom page turn area configuration with 3x3 grid
- Feat(reader): Add "Use Book Styles" toggle to preserve original book styling
- Feat(reader): Add toggle for mouse hover menu display at top/bottom edges
- Feat(reader): Add mouse wheel zoom support for image viewer
- Feat(bookshelf): Support displaying book title and author on default cover with responsive scaling
- Feat(ai): Support unlimited custom AI prompts with horizontal scrollable quick access
- Feat(ai): Support toggling AI panel position between right side and bottom in large screen mode
- Feat(sync): Add comprehensive WebDAV test (create, upload, download, delete) for connection validation
- Feat(window): Support window position and size memory on macOS
- Feat(import): Use original filename when book metadata title is missing or invalid
- UI(reader): Optimize reading history navigation button design
- Fix(reader): Fix image loading issue in non-standard EPUBs with missing manifest entries
- Fix(reader): Fix AI quick prompt chips overlapping issue
- Fix(reader): Fix PDF files with invalid TOC destinations failing to open
- Fix(reader): Fix reading info center alignment in header and footer
- Fix(reader): Fix search results scroll position not being preserved when returning from a result
- Fix(reader): Fix font-size adjustment not working for CSS keyword values (medium, large, etc.)
- Fix(sync): Fix WebDAV sync showing multiple direction selection dialogs
- Fix(ai_services): update Gemini service URL and model version
- Fix(window): Fix window becoming inaccessible after disconnecting secondary display

- Feat(reader): 添加标题字体大小调节滑块
- Feat(reader): 添加阅读器历史导航玻璃拟态胶囊
- Feat(reader): 支持手动控制历史导航显隐（不自动隐藏）
- Feat(reader): 支持手动选择并记忆日夜背景图偏好
- Feat(reader): 支持自定义翻页区域配置（3x3网格）
- Feat(reader): 添加"使用书籍样式"开关，保留书籍原始样式
- Feat(reader): 添加鼠标悬浮在顶部/底部时显示菜单的开关
- Feat(reader): 添加图片查看器鼠标滚轮缩放支持
- Feat(bookshelf): 支持在默认封面上显示书名和作者，支持响应式缩放
- Feat(ai): 支持无限制自定义AI提示词，快捷访问支持横向滚动
- Feat(ai): 支持切换 AI 面板位置（右侧/底部），适用于大屏模式
- Feat(sync): 添加 WebDAV 完整测试功能（创建、上传、下载、删除），全面验证连接
- Feat(window): 支持 macOS 记忆窗口位置和大小
- Feat(import): 当书籍元数据标题缺失或无效时，使用原始文件名
- UI(reader): 优化阅读历史导航按钮设计
- Fix(reader): 修复不规范 EPUB（manifest 缺失资源声明）中图片无法加载的问题
- Fix(reader): 修复AI快速提示重叠问题
- Fix(reader): 修复包含无效目录的 PDF 文件无法打开的问题
- Fix(reader): 修复页眉页脚阅读信息居中对齐问题
- Fix(reader): 修复点击搜索结果后重新打开搜索抽屉时滚动位置丢失的问题
- Fix(reader): 修复使用 CSS 关键字值（medium、large 等）的字体大小无法调节的问题
- Fix(sync): 修复 WebDAV 同步时出现多个方向选择弹窗的问题
- Fix(ai_services): 更新 Gemini 服务 URL 和模型版本
- Fix(window): 修复断开副屏后窗口位置不可访问的问题

## 1.11.0
- Feat: Support "No Tag" filter in books filter menu
- Feat: Support select to mark
- Feat: Support setting whether to automatically hide the bottom navigation bar on the home page
- Feat: Support using Azure TTS service for narration
- Feat: Support previewing synthesized voice models
- Feat: Optimize online TTS narration stability
- Feat: In scroll page mode, you can turn pages across chapters by dragging up and down @Spixz
- Feat: Windows can remember whether the window is maximized @TimurCravtov
- Feat: Add Microsoft Azure, Google Cloud translation service support
- Feat: Plan to remove unstable translation services (2026-03-01)
- Feat: macOS data path migration to Application Support with automatic data transfer
- Feat: Custom storage location support on Windows
- Fix: Fixed the issue where Epub files could not be imported when the directory did not exist @ZzhouR
- Fix: feat: add gesture handling to ignore bookmark actions from top screen touch
- Fix: feat: add note filtering function to prepare for book review function
- Fix: fix the issue of missing context menu when selecting across pages on iOS
- Fix: fix the issue where HarmonyOS could not sync with other systems
- Fix: fix the issue where some AI services could not be used
- Feat: Support auto select day/night background image
- Feat: Support group day/night background
- Fix: Fix app crash when disabling AI on home page
- Feat: Support replacing book file (maintaining reading progress and notes)
- Fix: Optimize Android, HarmonyOS text selection logic
- UI: Optimize part of the interface design

- Feat: 标签筛选菜单支持“无标签”筛选
- Feat: 支持选中即标注功能
- Feat: 支持设置是否自动隐藏主界面底部导航栏
- Feat: 支持使用 Azure TTS 服务进行朗读
- Feat: 支持试听语音模型合成效果
- Feat: 优化在线 TTS 朗读稳定性
- Feat: 滚动翻页模式下可以通过上下拖动来跨章节翻页 @Spixz
- Feat: Windows可以记忆是否最大化窗口 @TimurCravtov
- Feat: 添加 Microsoft Azure，Google Cloud 翻译服务支持
- Feat: 计划移除不稳定的翻译服务（2026-03-01）
- Feat: macOS 数据存储路径迁移至 Application Support 并支持自动数据迁移
- Feat: Windows 支持自定义数据存储位置
- Fix: 修复Epub文件目录不存在时无法导入的问题 @ZzhouR
- Fix: 添加手势处理，忽略来自屏幕顶部触摸的书签操作
- Fix: 添加笔记过滤功能，为书评功能做好准备
- Fix: 解决 iOS 跨页选择时上下文菜单缺失的问题
- Fix: 解决 HarmonyOS 无法与其他系统同步的问题
- Fix: 解决部分 AI 服务无法使用的问题
- Feat: 支持自动选择白天/黑夜的背景图片
- Feat: 支持日夜模式背景图片编组
- Fix: 修复主界面关闭AI时App崩溃的问题
- Feat: 支持替换书籍文件（保留阅读进度和笔记）
- Fix: 优化 Android，HarmonyOS 文本选择逻辑
- UI: 优化部分界面设计

## 1.10.1
- Feat: Choose bookshelf folder style (2x2 grid/stacked)
- Feat: Optimize widow/orphan line display (allow single line content to be displayed when there is a large remaining space on the previous page)
- Feat: AI can add tags to books, change bookmark colors, etc.
- Feat: Support custom tag colors
- Feat: Support adding tags to books
- Feat: Support filtering books by tags
- Feat: Support filtering books by reading progress
- Feat: When backing up/restoring, support cross-platform backup/restore (need to use the new version of the App for backup and restore)
- Feat: When exporting notes, you can sort by chapter order or time order
- Feat: When viewing notes, you can remember the last sorting method
- Feat: When exporting notes, you can choose whether to merge note titles from the same chapter
- Feat: Support managing whether AI tools are enabled
- Feat: Localized titles when AI calls tools
- Fix: Fix the issue where preference settings could not be correctly restored when restoring from backup in some cases (need to use the new version of the App for backup and restore)
- Fix: Optimize page turn smoothness on Android and Windows devices
- Fix: Reduce cache usage on iOS devices
- Fix: Files can be imported through the "Open With" option
- Fix: When displaying tags, they can be displayed in order
- UI: Optimize part of the interface design

- Feat: 可以选择书架文件夹样式（2x2宫格/重叠）
- Feat: 优化孤行显示效果（在前一页剩余空间较大时，允许显示单行内容）
- Feat: 支持AI为书籍添加标签，更改书签颜色等
- Feat: 支持自定义标签颜色
- Feat: 支持为书籍添加标签
- Feat: 支持通过标签筛选书籍
- Feat: 支持按阅读进度筛选书籍
- Feat: 备份/恢复时,支持跨平台备份/恢复(需要用新版App进行备份和恢复)
- Feat: 笔记导出时可以按章节顺序或时间顺序排序
- Feat: 查看笔记时可以记忆上次的排序方式
- Feat: 笔记导出时可以选择是否合并同一章节的笔记标题
- Feat: 支持管理 AI 工具是否启用
- Feat: AI 调用工具时有本地化的标题
- Fix: 修复部分情况下恢复备份时无法正确恢复偏好设置的问题(需要用新版App进行备份和恢复)
- Fix: 优化 Android、Windows 设备翻页流畅度
- Fix: 减少 iOS 设备缓存使用
- Fix: 可以通过打开方式导入文件
- Fix: 展示标签时，能够按顺序展示
- UI: 优化部分界面设计

## 1.10.0
- Feat: More data display in the statistics interface
- Feat: Statistic data display blocks support sorting, adding, and removing
- Feat: Statistic data display blocks support clicking to open the back side
- Feat: Translation can leverage context for more accurate understanding and expression
- Feat: Add haptic feedback
- Feat: More granular reading data statistics
- Fix: Smoother page turn animation
- Fix: Optimize context menu styles
- Fix: Reading time statistics accuracy issue
- Fix: Abnormal underline display issue
- Fix: Optimize txt file chaptering rules
- UI: Optimize part of the interface design

- Feat: 统计界面添加更多数据展示
- Feat: 统计数据展示块支持排序、新增、移除
- Feat: 统计数据展示块支持点击打开背面
- Feat: 翻译内容可以结合上下文进行更准确的理解和表达
- Feat: 添加震动反馈
- Feat: 更精细的阅读数据统计
- Fix: 更流畅的滑动翻页动画
- Fix: 优化上下文菜单样式
- Fix: 阅读时长统计不准确的问题
- Fix: 划线显示异常的问题
- Fix: 优化 txt 文件分章规则
- UI: 优化部分界面设计

## 1.9.2
- Feat: Directory interface is displayed as a drawer from the side
- Feat: AI output can be more easily selected and copied
- Feat: In vertical layout, optimize the quotation mark style
- Fix: Fix the issue where external links could not be opened
- Fix: Fix the issue of abnormal indentation
- Fix: The issue of being unable to adjust paragraph spacing in some files
- Fix: Optimize the timing of context menu popup and close
- Fix: The issue where the table of contents could not locate the current chapter
- Fix: Optimize TTS function to improve performance in unstable network environments (experimental)
- Fix: Optimize image size display
- Fix: Optimize txt file chaptering rules to improve chapter title recognition rate
- Fix: The issue where some files could not be paginated correctly
- Fix: The issue where the page turn position may be inaccurate during TTS
- Fix: Optimize the display effect of boundaries
- Fix: Optimize the display effect of images as footnotes
- Fix: Optimize timer logic to improve the accuracy of reading progress recording
- Fix: Ensure that notes deleted in the note list are synchronously updated in the reading interface
- Fix: The issue where AI reply content could not be read sometimes
- Fix: The issue of inaccurate click position recognition
- Fix: Context menu adaptation for vertical layout
- Fix: Optimize the issue of abnormal display after some style adjustments
- UI: Optimize part of the interface design

- Feat: 目录界面以抽屉形式从侧面显示
- Feat: AI 的输出可以更方便的选择和复制了
- Feat: 直排模式下,引号样式优化
- Fix: 修复外链无法打开的问题
- Fix: 修复缩进异常的问题
- Fix: 部分文件无法调节段间距的问题
- Fix: 优化上下文菜单弹出和关闭的时机
- Fix: 目录无法定位到当前章节的问题
- Fix: 优化朗读功能，提升不稳定网络环境下的表现（实验）
- Fix: 优化图片大小的显示效果
- Fix: 优化 txt 文件分章规则，提升章节标题的识别率
- Fix: 部分文件无法正确分页的问题
- Fix: TTS 时翻页位置可能不准确的问题
- Fix: 优化边界的显示效果
- Fix: 优化图片作为脚注的显示效果
- Fix: 优化计时器逻辑，提升阅读进度记录的准确性
- Fix: 保证笔记列表中的笔记删除时在阅读界面同步更新
- Fix: 有时 AI 回复内容无法阅读的问题
- Fix: 点击位置识别不准确的问题
- Fix: 上下文菜单适配直排模式
- Fix: 优化部分样式调整后显示异常的问题
- UI: 优化部分界面设计


## 1.9.1

- Feat: On touch devices, a long press is required to open images
- Fix: Fix the issue where iOS26 devices cannot turn pages by touch
- Fix: Optimized indentation display effect, fixed the issue where indentation caused abnormal image positioning
- Fix: Fixed the issue where text output by AI could not be read after copying
- UI: Optimized part of the interface design

- Feat: 在触摸设备上需要长按才能打开图片
- Fix: 修复 iOS26 设备无法触摸翻页的问题
- Fix: 优化缩进的显示效果，修复了缩进引起图片位置异常的问题
- Fix: 修复 AI 输出的文本复制后无法阅读的问题
- UI: 优化部分界面设计

## 1.9.0
- Feat: Add AI page in navigation bar
- Feat: AI can draw mind maps and organize bookshelf
- Feat: View AI chat history
- Feat: AI can call tools to assist in answering
- Feat: Add AI tools, AI can call tools such as note search, bookshelf lookup, reading history to assist in answering
- Feat: Enhance AI chat streaming with cancellation support
- Feat: Optimize the interface design of the thinking model
- Feat: On touch devices, a long press is required to open images
- Feat: Optimize the interface design of chapter summaries
- Feat: Adjustable width for AI chat panel
- Fix: Fix the issue of some AI services loading indefinitely
- Fix: The bottom details on the bookshelf page sometimes do not work when clicked
- Fix: Gemini model cannot be used
- Fix: Fix the issue of blank content not updating after modifying underline notes
- Fix: AI line breaks sometimes display abnormally
- UI: Optimize part of the interface design

- Feat: 在 导航栏 添加 AI 页面
- Feat: AI 可以绘制思维导图、整理书架了
- Feat: 可以查看 AI 对话历史记录
- Feat: AI 可以调用工具来辅助回答
- Feat: 添加 AI 工具,AI 可以调用笔记搜索、书架查询、阅读记录等工具来辅助回答
- Feat: 增强 AI 对话流，支持终止当前对话
- Feat: 优化思考模型的界面设计
- Feat: 在触摸设备上需要长按才能打开图片
- Feat: 优化章节总结的界面设计
- Feat: 可以调节 AI 对话面板的宽度
- Fix: 修复部分 AI 服务无限加载的问题
- Fix: 书架页面底部详情有时点击后不起作用的问题
- Fix: Gemini 模型无法使用的问题
- Fix: 修复划线笔记修改后内容空白不更新的问题
- Fix: AI 换行符有时显示异常的问题
- UI: 优化部分界面设计

## 1.8.1
- Fix: Fix some AI services not working issues
- Fix: Optimize full-text translation effect

- Fix: 修复部分 AI 服务无法使用的问题
- Fix: 优化全文翻译的效果

## 1.8.0
- Feat: Custom txt chaptering rules
- Feat: Search books or notes
- Feat: Menu bar does not close after jumping to chapter
- Feat: Add more hints to help understand features
- Feat: Optimize Windows Touch Experience
- Fix: Underline style highlights do not display correctly in vertical mode
- Fix: Inappropriate sentence segmentation during TTS reading
- Fix: TTS skips annotation markers during reading
- Fix: Table of contents supports locating the current chapter
- Fix: Some interface elements overflow in certain cases
- Fix: Abnormal generation of txt file directory
- Fix: Crash when restoring backup
- UI: Optimize part of the interface design
- Perf: Reduce device GPU usage

- Feat: 自定义的 txt 分章规则
- Feat: 可以搜索图书或笔记
- Feat: 跳转章节后不关闭菜单栏
- Feat: 添加更多提示信息来帮助了解功能
- Feat: 优化 Windows 触摸屏体验
- Fix: 竖排模式下，下划线样式的划线显示不正确的问题
- Fix: 修复 TTS 朗读时分句不恰当的问题
- Fix: TTS 朗读时跳过注解角标
- Fix: 目录支持定位到当前章节
- Fix: 某些情况下部分界面元素溢出的问题
- Fix: txt 文件目录生成不正常的问题
- Fix: 恢复备份时闪退的问题
- UI: 优化部分界面设计
- Perf: 降低设备 GPU 使用

## 1.7.0
- Feat: TTS can be configured to play together with other audio
- Feat: Support swapping page turn area
- Feat: Support full-text bilingual translation
- Feat: Support translation only mode
- Feat: Support book-specific translation settings
- Feat: Support sharing book files
- Feat: Support text alignment settings
- Feat: Translation language follows app interface language
- Fix: Improved garbled text detection in txt file encoding handling
- Fix: Issue with WebDAV initialization
- Fix: Fix multiple tools bar
- L10n: Add literally Chinese, Spanish, French, Italian, Japanese, Korean, Portuguese, Russian
- UI: Optimize part of the interface design

- Feat: TTS可配置是否和其他音频一起播放  
- Feat: 支持交换翻页区域
- Feat: 支持全文双语对照翻译
- Feat: 支持仅显示翻译
- Feat: 支持每本书独立的翻译设置
- Feat: 支持分享书籍文件
- Feat: 支持文本对齐设置
- Feat: 翻译语言跟随应用界面语言
- Fix: 改进 txt 文件编码处理中的乱码检测
- Fix: WebDAV初始化的问题
- Fix: 修复工具栏无法正确关闭的问题
- L10n: 添加文言文、 西班牙语、法语、意大利语、日语、韩语、葡萄牙语、俄语
- UI: 优化部分界面设计

## 1.6.2
- UI: Modify bottom navigation bar style
- Feat: Import previously deleted files and automatically associate notes, progress, etc.
- Feat: Support preventing duplicate file imports
- Feat: Support calculating feature values of existing files to prevent duplicate imports
- Feat: Support custom CSS styles
- Fix: Fix sync failure when WebDAV is empty
- Fix: Fix issue where txt files could not be correctly judged as duplicates

- UI: 修改底部导航栏样式
- Feat: 导入曾经删除的文件时自动关联笔记、进度等信息
- Feat: 支持防止文件重复导入
- Feat: 支持计算已有文件特征值，用于防止重复导入
- Feat: 支持自定义 CSS 样式
- Fix: WebDAV 为空时同步失败的问题
- Fix: 修复 txt 文件无法正确判断是否重复的问题

## 1.6.1
- Feat: Support following book indentation
- Feat: Support choosing whether to enable auto-sync
- Feat: Add a guide page for first-time users
- Feat: Show update log after updating
- Feat: Support restoring old versions from history after downloading and overwriting the local database from remote (experimental feature)
- Fix: Some Android devices cannot select text and pop up context menu
- Fix: Compatibility with older WebView versions, now it may run on WebView version 70 and above
- Fix: WebDAV configuration changes now take effect immediately after saving
- Fix: Improved sync logic to replace the current database only after confirming the integrity of the new database
- Fix: Preserve historical versions when replacing the local database
- Fix: PDF files could not be read in the previouo version
- Fix: covers could not be synced
- Fix: files with uppercase extensioos could not be imported
- Fix: books could not be imported on somo Windows devices
- Fix: Fixed issue where user notes were lost after changing highlight style
- Fix: Fixed issue where PDF files could not be imported
- Chore: Prepare for supporting more sync protocols
- Build: Optimize build number

- Feat: 支持跟随书籍缩进
- Feat: 支持选择是否开启自动同步功能
- Feat: 添加首次启动的引导页
- Feat: 更新后能够展示更新日志
- Feat: 从远端下载数据库覆盖本地后，能够从历史版本中选择旧版本恢复（实验性功能）
- Fix: 部分安卓设备无法在选择文段后弹出上下文菜单
- Fix: 兼容较旧的 WebView 版本，现在或许可以在 WebView 70 以上的版本上运行了
- Fix: 修复保存 WebDAV 配置信息后未能立即生效的问题
- Fix: 修复同步逻辑，能够在判断新数据库完整后再替换当前数据库
- Fix: 在替换本地数据库时能够保留历史版本
- Fix: 修复上一版本中 PDF 无法阅读的问题
- Fix: 修复封面无法同步的问题
- Fix: 修复大写扩展名的文件无法导入的问题
- Fix: 部分情况下 Windows 端无法导入书籍
- Fix: 修复修改划线样式后用户笔记丢失的问题
- Fix: pdf 无法导入的问题
- Chore: 为更多同步协议做好准备
- Build: 优化构建号

## 1.6.0
‼️If WebDAV sync is enabled, please upgrade all devices to this version, otherwise the book notes list will not be displayed‼️
‼️如果启用了 WebDAV 同步，需要将各端都升级至此版本，否则书籍笔记列表将无法显示‼️

- Feat: Support locating the current chapter in the table of contents
- Feat: Custom page header and footer position
- Feat: Support displaying page numbers in the table of contents
- Feat: Support running JavaScript in books
- Feat: Support pull up to exit reading page
- Feat: Support adding bookmarks by pulling down
- Feat: Support opening the menu bar by pulling up
- Feat: Support adding/removing bookmarks via the bookmark button
- Feat: Show bookmark list in the table of contents page
- Feat: Support deleting the current bookmark by pulling down
- Feat: Support choosing whether to display bookmarks when filtering
- Feat: Display book name in two lines
- Feat: Add two background image in share card
- Feat: Opening a book from the note list will not record reading progress
- Fix: Fix inaccurate click position recognition in vertical scroll layout
- Fix: Optimize page-turning animation stuttering
- Fix: improve version comparison logic in update check
- Fix: Better app icon for Android
- Fix: Optimize the timing of the context menu popup on Android devices
- Dx: Improved JS debugging process for easier debugging

- Feat: 在目录上定位当前章节
- Feat: 自定义页眉和页脚的位置
- Feat: 在目录上显示页码 
- Feat: 支持运行Epub书中的 JavaScript
- Feat: 支持上划退出阅读页面
- Feat: 支持下拉添加书签
- Feat: 支持上拉呼出菜单栏
- Feat: 支持通过书签按钮添加/删除书签
- Feat: 在目录页显示书签列表
- Feat: 支持下拉删除当前书签
- Feat: 支持在笔记列表筛选时选择是否显示书签
- Feat: 书名显示为两行
- Feat: 分享卡片新增两个背景图
- Feat: 从笔记列表打开书不会记录阅读进度
- Fix: 修复竖向滚动排版点击位置识别不准确的问题
- Fix: 优化翻页动画卡顿的问题
- Fix: 优化检查更新时版本比较逻辑
- Fix: 优化 Android 端应用图标
- Fix: 优化 Android 设备上下文菜单弹出时机
- Dx: 修改js的调试流程，更方便调试

## 1.5.3
- Feat: Support AI translation and dictionary(#145, #249)
- Feat: Support setting DeepL URL
- Feat: Show data update time while choosing sync direction
- Feat: Add Crimean Tatar translation support
- Feat: Support modifying the original text content in the note editing diaglog
- Feat: Support import books via share
- Feat: Add this app to open with
- Fix: adjust margin icons in style settings
- Fix: TTS may get stuck on punctuation
- Fix: Fix garbled text when importing some TXT files
- Fix: Fix excessive spacing between some file segments(#325)
- UI: Update background and button styles in BookDetail
- Fix: Fix inaccurate click position in pdf files
- Fix: macOS Launchpad icon edge anomaly(#331)
- Fix: Fix issue where short TXT files cannot be imported(#329)
- Fix: Fix DeepL translation error(#327)

- 新增: 支持 AI 翻译和词典(#145, #249)
- 新增: 支持设置 DeepL URL
- 新增: 在选择同步方向时提示两端的数据更新时间
- 新增: 添加克里米亚鞑靼语翻译支持
- 新增: 支持在笔记编辑界面中修改笔记的原文内容
- 新增: iOS 支持通过分享的方式导入图书
- 新增: 支持 打开方式 中选择本App
- 修复: 修改样式设置中的边距图标
- 修复: TTS 有时会被标点符号卡住
- 修复: 部分 TXT 文件导入乱码的问题
- 修复: 部分文件段间距过大(#325)
- UI: 修改书籍详情页背景和按钮样式
- 修复: pdf 文件点击位置不准确的问题
- 修复: macOS 启动台中图标边缘异常(#331)
- 修复: 内容较短的 TXT 文件无法导入的问题(#329)
- 修复: DeepL 翻译出错(#327)

## 1.5.2
- Feat: iOS dark and tinted icons
- Feat: Custom reading background image
- Feat: Import any custom reading background
- Feat: Custom writing direction(Horizontal, Vertical)
- Fix: WebDAV sync may override cloud data(#274)
- Fix: TTS may stop when encountering some punctuation(#291)
- Fix: Background image stretched in scroll mode
- Fix: Hide scrollbar in scroll mode
- Fix: Vertical margin prompt is not clear in vertical mode
- Fix: Click position cannot be recognized in vertical mode
- Fix: WebDAV sync may override cloud data with special characters
- Fix: Reduce TTS reading interval time
- Fix: Some interfaces are difficult to identify in E-ink mode
- Fix: Book status icon not updated after releasing space
- Fix: WebDAV sync error Not Found and Conflict

- 新增: iOS 深色、着色图标
- 新增: 设置阅读背景图片
- 新增: 导入任意自定义阅读背景
- 新增: 可以选择文字方向（横排、竖排）
- 修复: WebDAV 同步时可能会覆盖云端数据(#274)
- 修复: 遇到部分标点时朗读停止(#291)
- 修复: 滚动模式下，背景图片被拉伸
- 修复: 在滚动模式下隐藏滚动条
- 修复: 竖排模式下，边距调节提示不够明确
- 修复: 竖排模式下，点击位置无法正确识别
- 修复: 包含特殊字符的文件名无法通过 WebDAV 同步
- 修复: 减小 TTS 朗读间隔时间
- 修复: E-ink 模式下，部分界面难以辨认
- 修复: 释放空间后，书籍状态图标不更新
- 修复: WebDAV 同步时报错 Not Found 和 Conflict 的问题

## 1.5.1
- Fix: Can't open book note list in some cases
- Fix: WebDAV sync show Not Found
- Fix: Context menu is difficult to distinguish in e-ink mode
- L10n: Optimized Arabic translation
- 修复: 某些特殊情况下笔记列表无法显示
- 修复: 某些情况下 WebDAV 同步时显示 Not Found 的问题
- 修复: E-ink 模式下上下文菜单难以辨认
- L10n: 优化阿拉伯语部分翻译

## 1.5.0
- Feat: Cache in-app purchase status(#281, #242)
- Feat: Name a group
- Feat: E-ink mode(#264)
- Feat: Add DeepL translation service(#223, #145)
- Feat: Edit notes in list
- Feat: Download all books
- L10n: Add Arabic and German language
- Feat: Download remote files on demand
- Feat: Release local space(#269)
- Feat: Add share excerpt card(#263)
- Feat: Notes in list can be shared as cards
- Fix: Incorrect click position detection on macOS
- Fix: Sort menu sometimes fails to open
- Fix: WebDAV Unauthorized(#273)
- Fix: Optimize book opening speed
- Fix: Touchpad cannot scroll(#271, #261)
- Fix: Edge TTS when network exception, it will stop reading

- 新增: 缓存内购状态(#281, #242)
- 新增: 书籍分组支持命名
- 新增: E-ink 模式(#264)
- 新增: DeepL 翻译服务(#223, #145)
- 新增: 笔记列表可以编辑笔记
- 新增: 下载所有书籍文件
- L10n: 新增阿拉伯语和德语
- 新增: 按需下载远程的文件
- 新增: 释放本地空间功能(#269)
- 新增: 通过卡片的方式分享划线笔记(#263)
- 新增: 笔记列表的笔记可以以卡片的形式分享
- 修复: macOS 端无法正确判断点击位置的问题
- 修复: 排序菜单有时无法打开的问题
- 修复: WebDAV提示未授权(#273)
- 修复: 优化打开书籍速度
- 修复: 触摸板无法滚动(#271, #261)
- 修复: Edge TTS 朗读时，网络异常时会停止朗读的问题

## 1.4.4
- Feat: Import pdf files
- Feat: Sort books
- Feat: More available fonts
- Feat: Delete reading records of a book
- Feat: Add webdav sync direction dialog
- Feat: Add font delete
- Fix: Webdav sync aborted dialog content
- Fix: if webdav is empty, sync will upload
- Fix: avoid image following paragraph indent
- Fix: optimize book loading speed
- Fix: sync custom book cover

- 新增: 导入 pdf 文件
- 新增: 书架排序功能
- 新增: 更多可选字体
- 新增: 删除一本书的阅读记录
- 新增: 添加 WebDAV 同步方向对话框
- 新增: 添加字体删除功能
- 修复: WebDAV 同步中止对话框内容
- 修复: 如果 WebDAV 为空，则同步时默认上传
- 修复: 避免图片跟随段落缩进
- 修复: 提升图书加载速度
- 修复: 同步自定义的书籍封面

## 1.4.3
- Feat: Storage space management
- Feat: Add auto translate selection switch in translate settings(#217)
- Feat: Handle txt files with failed chapter division by word count
- Feat: Import txt file with utf-16 or utf-32 encoding
- Feat: recover system TTS(#197)
- Fix: TTS cannot play after resume from background(#196)
- Fix: TTS cannot play when encountering images or cross-chapter
- Fix: System TTS continuous backward movement(#197)
- Fix: Copy translated text instead of original text(#190)
- Fix: Cross-segment highlight cannot be displayed immediately
- Fix: Highlight only the first word of the selection on Android(#189)
- Fix: Scroll page turn cannot be used in scroll mode(#201)

- 新增: 存储空间查看和管理
- 新增: 翻译设置页增加自动翻译开关(#217)
- 新增: 按字数对分章失败的txt文件进行处理
- 新增: 支持导入UTF-16、UTF-32编码的txt文件
- 新增: 重新引入了系统 TTS(#197)
- 修复: TTS 无法在从后台恢复后播放(#196)
- 修复: 集成 TTS 遇到图片或跨章节时无法播放
- 修复: 系统 TTS 连续向后移动
- 修复: 复制翻译内容而不是原文(#190)
- 修复: 跨段划线无法立即显示
- 修复: 安卓设备有时划线只能显示第一个字词(#189)
- 修复: 滚动翻页模式下，鼠标滚轮翻页一次翻一整页的问题(#201)

## 1.4.2
- Feat: add link icon
- Feat: AI chat regenerate and copy
- Feat: TTS integration
- Feat: Reading info custom
- Feat: Navigation bar custom
- Feat: Sync completed toast
- Fix: Some old versions of Webview cannot import books
- Fix: Footnotes cannot be displayed on some devices
- Fix: Image as link cannot be clicked
- Fix: Reading information does not follow style changes
- Fix: First line indent affects images
- Fix: Context menu position error when it exceeds the screen
- Fix: Optimize book opening speed
- Fix: some device cant open footnote
- Fix: Android click page turn button may return to previous page
- Fix: iOS blank screen after resume from background
- Fix: note input box may be covered by keyboard(#183)
- Fix: txt file with special characters cannot be imported
- Fix: some Android devices cannot export backup file

- 新增: 添加更多社区链接
- 新增: AI 对话可重新生成和复制
- 新增: 集成的 TTS
- 新增: 阅读信息自定义
- 新增: 导航栏自定义
- 新增: 同步完成是否显示提示
- 修复: 部分旧版本Webview无法导入图书
- 修复: 部分设备无法显示脚注
- 修复: 以图片作为脚注时无法点击
- 修复: 阅读信息无法跟随样式变化
- 修复: 首行缩进影响图片
- 修复: 上下文菜单超出屏幕时位置错误
- 修复: 优化书籍打开速度
- 修复: 部分设备无法打开脚注
- 修复: Android 跨章节后无法点击翻页的问题
- 修复: iOS 设备从后台恢复后有时白屏的问题
- 修复: 写想法的输入框有时被键盘遮挡(#183)
- 修复: 部分含有特殊字符的 txt 文件无法导入的问题
- 修复: 部分 Android 设备无法导出备份文件

## 1.4.1
- Feat: excerpt AI chat
- Feat: add AI chat in reading page
- Feat: control webdav sync only when wifi is connected
- Feat: manage open book animation
- Feat: add text for context menu
- Feat: add text for slider(#48)
- Feat: add tips for AI configuration
- Feat: custom shelf cover width
- Feat: toc item scroll to current chapter(#141)
- Fix: save image on iOS
- Fix: click page turn button may return to previous page
- Fix: scroll page turn cannot set margin(#139)

- 新增: 划线 AI 对话
- 新增: 阅读界面可以与 AI 对话
- 新增: 控制 WebDAV 是否仅在 WiFi 下同步
- 新增: 管理打开书的动画
- 新增: 上下文菜单文字提示
- 新增: 样式调节滑块的文字说明(#48)
- 新增: AI 配置提示
- 新增: 自定义书架封面宽度
- 新增: 目录项滚动到当前章节(#141)
- 修复: iOS 端保存图片
- 修复: 有时点击翻页会返回上一页
- 修复: 滚动翻页无法设置上下边距(#139)

## 1.3.1
> MacOs 版本处于测试阶段
> MacOS version in beta

- Fix: Some Android devices cannot import txt format books
- 修复: 部分安卓设备无法导入 txt 格式的书籍

## 1.3.0

> MacOs 版本处于测试阶段
> MacOS version in beta

- Feat: Add font weight slider
- Fix: AI answer cache(#124)
- Feat: Expand the range of custom font size
- Feat: Add volume key page turn switch
- Feat: Add custom Gemini api url
- Fix: Android TTS slider value not updating
- Fix: Txt file chapter title detection(#107)
- Fix: DeepSeek default model name(#123)
- Fix: Sync problem(#94，#89)

- 新增: 调整字体粗细
- 新增: AI 回答缓存
- 新增: 扩大自定义字体大小范围
- 新增: 音量键翻页开关
- 新增: 自定义 Gemini api url
- 修复: Android TTS 滑块数值不更新
- 修复: txt 文件章节标题检测(#107)
- 修复: DeepSeek 默认模型名称(#123)
- 修复: 无法同步的问题(#94，#89)

## 1.2.6
- Fix: Fix ai stream error
- 修复: 修复 AI 流错误
  
## 1.2.5
- Feat: Add volume key page turn(#95)
- Feat: Add auto background color(#78)
- Feat: Add OpenAI、Claude、DeepSeek AI models(#100)
- Perf: Optimize txt file import speed
- UI: Optimize multiple UI interfaces

- 新增: 音量键翻页(#95)
- 功能: 自动背景色(#78)
- 功能: 接入 OpenAI、Claude、DeepSeek 等多个 AI 模型
- 性能: 大幅提高了 txt 文件的导入速度
- UI: 优化多个 UI 界面

## 1.2.4 2025-01-21
* Feat: Remember last window position and size(#67)
* Feat: Color picker input hex code(#69)
* Feat: Export notes in CSV format(#71)
* Feat: Add TTS stop timer(#81)
* Feat: Add heat map to show reading time(#69)
* Feat: Import progress prompt(#61)
* Feat:  Add statistics chart switch time
* Fix: some Windows systems cannot import books(#75)
* Fix: enhance Webdav sync stability
* Fix: Reading settings interface is incomplete on some devices(#70)

* 新增: 记忆上次窗口位置和大小(#67)
* 新增: 选择颜色时能够输入十六进制代码(#69)
* 新增: 以 CSV 格式导出笔记(#71)
* 新增: TTS 定时停止(#81)
* 新增: 用热力图展示阅读时长(#69)
* 新增: 导入进度提示(#61)
* 新增: 统计图表切换时间
* 修复: 部分 Windows 系统下无法导入图书(#75)
* 修复: 增强 Webdav 同步稳定性
* 修复: 部分设备下阅读设置界面显示不完整(#70)

## 1.2.3 2024-12-26
* Feat: Reader could add notes
* Feat: Search books
* Feat(Android): Display TTS control buttons in the notification screen
* Feat(Android): Import books through system sharing
* Feat(Windows): Drag to import books
* Feat(Windows): Webview2 check and prompt
* Fix: Fixed garbled text when importing txt files
* Fix: Optimized import efficiency
* Fix(Windows): Fixed crash issue when opening books on some Windows devices

* 新增: 读者添加批注
* 新增: 书籍搜索
* 新增（Android）: 在通知栏中显示 TTS 控制按钮
* 新增（Android）: 通过系统分享导入书籍
* 新增（Windows）: 拖拽导入书籍
* 新增(Windows): Webview2 检查和提示
* 修复: txt 文件导入时乱码问题(添加了 GBK 解码)
* 修复: 大幅优化导入效率
* 修复（Windows）: 部分Windows 端打开书时闪退问题

## 1.2.2 2024-12-02
🚀 Support txt files now!
🚀 支持了 txt 文件导入

- Feat: Setting reading column count
- Feat: Import txt format books
- Fix: Book progress record is not timely
- Fix: Windows import book error

- 新增: 设置阅读栏数
- 新增: 导入 txt 格式书籍
- 修复: 书籍进度记录不及时
- 修复: Windows 端部分设备无法导入书籍

## 1.2.1 2024-11-23
- Feat: Drag to group books
- Fix: Bottom navigation bar covers menu bar
- Fix: Windows no longer deletes original files when importing
- Fix: Books with single quotes cannot be opened

- 新增: 拖拽实现书籍分组
- 修复: 底部导航栏覆盖菜单栏
- 修复: Windows 端导入时删除原文件的问题
- 修复: 包含单引号的书籍无法打开

## 1.2.0 2024-11-17
❗Anx-Reader has changed the Android version signature, please back up and reinstall Anx-Reader❗
❗安读更换了 Android 版本的签名, 请做好备份重新安装安读❗

🚀You can now use Anx-Reader on Windows!
🚀现在可以在 Windows 上使用安读了！

- Feat: Translate selected content
- Feat: Note add time
- Feat: Webview version check
- Feat: convert chinese mode
- UI: Optimized the statistic card
- Fix: Context menu cannot be closed once
- Fix: Cannot correctly judge the version when checking for updates

- 新增: 翻译选中内容
- 新增: 简繁转换
- 新增: Webview版本检查
- 新增: 显示笔记添加时间
- UI: 优化了统计卡片
- 修复: 上下文菜单不能一次关闭
- 修复: 检查更新时不能正确判断版本

## 1.1.8 2024-10-23

- Added: Modify import/export file structure
- Fixed: Book font size cannot maintain relative relationship
- Fixed: Can be used in lower webview versions (about 92.0.0.0 and above)

- 修改: 修改了导入导出的文件结构
- 修复: 书籍字体大小不能保持相对关系
- 修复: 能够在较低的 webview 版本中使用(约92.0.0.0及以上)

Windows version is coming soon!
Windows端即将发布，敬请期待！

## 1.1.7 2024-09-11
- Backup: Export/import all data
- Ability to click and view large images
- Convenient back arrow after navigation
- Multiple pop-up annotations within a pop-up annotation
- Customizable text indentation size
- Text selection within pop-up annotations
- Optimization of status bar and navigation key areas to avoid obstruction by navigation keys
- Fixed white screen issue when opening files
- Fixed issue with importing font files with Chinese filenames
- Shortened TTS reading intervals, especially when using TTS-Server

- 备份: 导出/导入全部数据
- 能够点击查看大图了
- 跳转后能够有方便地返回箭头
- 弹注中多次弹注
- 弹注字体跟随设置
- 自定义文本缩进大小
- 弹注中选择文字
- 状态栏和导航键区域优化，避免了被导航键遮盖
- 修复打开文件白屏
- 修复字体文件中中文文件名无法导入
-  缩短了TTS朗读间隔，尤其是使用TTS-Server时
- 根据弹注内容调整弹注框大小


## 1.1.6 2024-09-03
This release includes a number of new features and improvements, as well as bug fixes.
Feature: Added support for importing books in mobi, azw3, and fb2 formats
Feature: Added TTS (Text-to-Speech) voice reading functionality
Feature: Added filter, sort, and open book at the note location features in the note list
Feature: Added more page-turning methods
Feature: Added support for importing custom fonts
Feature: Added full-text search functionality
Fix: Resolved issues where book styles were not applied (#24, #28)
Other: For more new features and bug fixes

众多新增功能！
功能: 新增mobi、azw3、fb2格式书籍导入
功能: 新增TTS语音朗读
功能: 笔记列表可筛选、排序、打开书到笔记的位置
功能: 新增更多翻页方式
功能: 导入自定义字体
功能: 全文搜索
修复: 书籍样式不生效 #24，#28
以及其他众多新功能和修复
