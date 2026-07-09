# S1 Brief — 数据完整性与崩溃修复

> 前置:无,不受体验重建期冻结规则约束(与 P6 批次5 同为唯一例外)。理由:批次1/2 影响的是"功能是否存在",不是"体验好不好"——冻结规则挡的是新功能,不是让产品回归级 bug 排队。
> 来源:2026-07 全域功能/UX 审查(9 域、63 个对抗验证 agent),本 brief 只收录 severity=crash/data-loss 且已核实的项;functional/ux 级发现分别已挂 E3 批次2/5、R2/R3 前置观察项,不在本文重复。
> DoD:7 项逐一有修复 + 回归测试;真机验收通过后收口。
> 最后更新:2026-07-09

## 高风险声明(全批次通用)

本 brief 涉及 DB migration 和 WebDAV 同步——全仓库爆炸半径最大的两块代码。**任何批次落地前必须:**
1. 在全新模拟器/真机(无任何既存数据)+ 老版本升级路径(从 v7 数据库文件)两条链路都过一遍,不能只测其中一条。
2. 涉及 sync 的批次額外要求:两台设备(或一台+一份历史 WebDAV 快照)交叉验证,不能单机验收。
3. 每个批次改动前先用现有数据做一次本地备份文件,验收失败可秒回滚,不许"先改再说"。

## 批次 1 — 全新安装无法保存高亮/笔记/书签(最高优先级)

- 根因:`lib/dao/database.dart:134` `onCreate` 回调里 `onUpgradeDatabase(db, 0, version)` **没有 await**(fire-and-forget);`onUpgradeDatabase` 的 `case 1` 对 `tb_books` 执行 `ALTER TABLE ADD COLUMN rating`,而 `rating` 已经在 `case 0` 的 `createBookSQL`([:18-35](../../../../lib/dao/database.dart))里建表时就存在——抛 `duplicate column` 异常,导致 `case 2` 之后(含 `tb_groups` 建表、`tb_notes.reader_note` 加列)全部不执行。
- 做法:① 在 `onCreate`/`onUpgrade` 两处调用点补 `await`;② `case 0` 的 `createBookSQL` 已经包含 `rating/group_id/file_md5/bookmark_data/source_kind`,`case 1/5` 等针对这些列的 `ALTER TABLE ADD COLUMN` 对全新安装(oldVersion=0)要跳过——用 `if (oldVersion > 0)` 包一层,或者给每个后续 `ALTER` 加 `PRAGMA table_info` 探测列是否已存在再执行,选后者更安全(不依赖 case fallthrough 顺序假设)。
- 验证:全新模拟器(删除 app 数据后首次安装)导入一本书、选中文字点高亮、新建分组——三者都要成功落库;`sqlite3 <db> ".schema tb_books"` 确认无重复列错误;`sqlite3 <db> ".tables"` 确认 `tb_groups` 存在;老版本升级路径(从 v7 数据库跑一次 `onUpgradeDatabase(db,7,8)`)不能受影响。
- commit:`fix(db): fresh-install migration chain completes past duplicate-column throw (S1 batch 1)`

## 批次 2 — 崩溃类(TTS 强制解包 / 书架布局)

- TTS:`lib/service/tts/tts_handler.dart:93` `play()` 用 `epubPlayerKey.currentState!` 等强制解包构造 `MediaItem`,书本已关闭时(蓝牙耳机按键、来电结束回调)`currentState` 为 null,崩溃。做法:解包前判空,为 null 时忽略本次 play 请求或走"无活动书籍"降级 `MediaItem`(标题走 ARB 占位文案),不崩。
- 书架网格:`lib/page/home_page/bookshelf_page.dart:513` `crossAxisCount: constraints.maxWidth ~/ Prefs().bookCoverWidth` 在窄窗口(macOS 缩到比 `bookCoverWidth` 还窄)时整除结果为 0,`SliverGridDelegateWithFixedCrossAxisCount` 要求 `crossAxisCount >= 1`,抛异常。做法:`math.max(1, ...)` 兜底。
- 验证:TTS 场景——播放中关闭书本再按耳机播放键,不崩溃;书架场景——macOS 窗口拖到 200pt 宽,网格正常渲染(可以只有1列)。`flutter test` 覆盖两处的 widget/unit 测试。
- commit:`fix(stability): guard TTS null-book play and bookshelf zero-column grid (S1 batch 2)`

## 批次 3 — 启动自动同步崩溃阻断 App 初始化

- 根因:`lib/page/home_page.dart:146` 附近对 `Sync()` 单例的调用在其 `@Riverpod(keepAlive:true)` provider 尚未附着时触发,抛 `LateInitializationError`,且该异常发生在 `initState`/启动链路里未被捕获,导致本次会话内自定义字体加载、分享意图(share-intent)注册等后续初始化代码整体不执行。
- 做法:把启动时的 `Sync()` 调用改为通过 `ref.read(syncProvider.notifier)` 走 Riverpod 正常生命周期获取,不使用裸单例;若仍有直接实例化路径,加 try-catch 保证同步失败不阻断后续初始化(把 sync 启动包成独立的 fire-and-forget 分支,不参与主 initState 的顺序执行)。
- 验证:开启 WebDAV 同步后冷启动 App,确认(a)分享文件到 App 在本次会话内立即可用,(b)自定义阅读字体正常加载,(c)同步本身仍然正常触发(不能为了"不阻断"而误伤同步本体)。
- commit:`fix(sync): decouple startup auto-sync failure from app init sequence (S1 batch 3)`

## 批次 4 — WebDAV 同步数据丢失簇(高风险,单独批次,双设备验收)

- 根因三处,建议一起看一起改(都在同一条同步链路上):
  1. `lib/providers/sync.dart:701` 附近 `isSyncing` 在 `uploadFile`/`downloadFile` 每次单文件传输结束就被置 `false`,而不是整个 `syncData()` 结束才置 `false`——重入锁形同虚设,两次同步可交叉跑。
  2. `lib/providers/sync.dart:541` 附近上传方向同步是整库覆盖 + 删除远端其它设备已有的书文件。
  3. `lib/service/sync/webdav_client.dart:239` 远程数据库替换是"先 DELETE 远端文件、再 PUT 新文件"两步操作,中间网络中断则远端库为空。
- 做法:① 重入锁只在 `syncData()` 顶层置位/复位,不在子函数里提前清零;② 上传方向不做"整库覆盖+删除对方文件",改为((最小改动)加一个"仅新增/更新本地有对方没有的书",不删除远端多出的文件;或(更彻底)按 `book.file_md5` 做去重合并而非整表覆盖——具体选哪种在开工前找用户拍板,不要自己定;③ 远程替换改成"先 PUT 到临时文件名、成功后 rename/move 覆盖旧文件"的原子操作(WebDAV `MOVE` 方法),避免中间态。
- 验证:双设备(或一台+一份历史快照)交叉验证——设备A导入书上传,设备B同步应该看到新书且原有书不丢;模拟传输中断(断网重连)后重试同步,远端库不应处于"无数据库文件"的中间态。
- commit:`fix(sync): remove whole-db clobber and delete-then-put race in webdav sync (S1 batch 4)`

## 批次 5 — AI 聊天历史损坏时静默删库

- 根因:`lib/service/ai/ai_history.dart:186` 解析历史文件失败时直接删除该文件,等于一次写坏 = 全部历史对话清零。
- 做法:解析失败时,把损坏文件重命名为 `.corrupt-<timestamp>` 备份而不是删除,再以空历史继续;可选:下次进入历史页时提示"检测到历史文件损坏,已备份,请联系反馈"(文案进 ARB)。
- 验证:手工写入一份非法 JSON 到历史文件路径,启动 App 打开历史——不崩溃、旧文件仍在磁盘(改名后)、当前历史从空列表开始。
- commit:`fix(ai-history): quarantine corrupt history file instead of deleting (S1 batch 5)`

## 验证规程(每批通用)

```bash
flutter analyze  # 无新增
flutter test     # 全绿(相对于 2026-07-06 记录的基线:1115 passed / 2 skipped / 7 failed,后者均为存量 flaky)
bash tool/check_repo_budgets.sh
```

## 红线

- 不在本 brief 顺带改动 UI 视觉、不做 E3/E4 已认领的文案/布局工作。
- 批次 4(WebDAV)开工前必须让用户对"整库覆盖 vs 按 md5 合并"二选一拍板,不得自行决定数据合并策略。
- 每批结束更新 `STATUS_zh.md` 对应行(≤3 行)+ commit message,不新增其他文档。
