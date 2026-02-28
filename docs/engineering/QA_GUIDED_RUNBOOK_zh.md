# 带你跑 QA：Paper Reader（papertok-reader）真机验收讲解稿

你可以把 QA 想成一次“飞机起飞前的绕机检查”。它不追求把所有零件拆开测一遍，而是用最短的路径证明两件事。

如果你想把 QA 跑得更像一场可复现的实验，而不是凭感觉点点点，可以配合阅读：`docs/engineering/QA_METHOD_zh.md`。

第一，这架飞机能按预期起飞并安全飞完一段航程。第二，如果某个关键部件有问题，我们能稳定复现并精确定位。

本文就是这份“绕机检查讲解稿”。它是通俗版的带跑说明，配合平台 checklist 使用。

- iOS / iPadOS checklist：`docs/engineering/IOS_IPADOS_QA_CHECKLIST_zh.md`
- Android checklist：`docs/engineering/ANDROID_QA_CHECKLIST_zh.md`
- AI 总体 test plan：`docs/ai/test_plan.md`

## 0. 你会得到什么

当你按本文跑完一次 QA，你会得到一份很像“教科书习题答案”的结果。

你能清楚地说出哪些功能在什么设备上验证通过，哪些没通过，没通过时的复现步骤是什么。更重要的是，我可以基于你给出的材料，快速做到“最小修复、补测试、补文档”，让系统整体质量真正收敛。

## 1. 在开始之前先做两件小事

### 1.1 选一个你现在最方便的设备

优先级建议是 iOS/iPadOS 先跑，因为它离 TestFlight 最近。

如果你现在只在 Android 上方便，也完全可以先跑 Android。

### 1.2 准备一套最小测试素材

准备 3 本书就够。

第一本是小 EPUB，章节短一点，方便验证跳转。

第二本是中等 EPUB，内容包含中英文混排，方便验证检索。

第三本是大 EPUB，章节多一点，方便观察索引队列在“压力下”是否稳定。

如果你已经有常用书库，直接从现有书里挑三本即可。

## 2. QA 的基本套路（你只要记住这一个节奏）

每个功能验证都按同一套节奏走。

先让它跑起来，再给它一个小压力，然后在边界条件下试一次，最后记录结果。

举个例子。索引队列的“跑起来”是能正常入队和完成一两本书；“小压力”是同时排队三本；“边界条件”是 pause/resume、取消 running、杀进程后重启。

这套节奏的好处是你不会陷入无穷无尽的点点点。它把验证聚焦在系统的关键不变量上。

## 3. 如何拿到 deep link 测试所需的 bookId、href、cfi

很多人第一次看到 `paperreader://reader/open?...` 会感觉像在看一段“魔法咒语”。其实它只是把“你要打开哪本书、跳到哪一段”这两件事用 URL 说清楚。

最省心的方法不是你手写。

你让系统自己产出。

### 3.1 用 RAG evidence 直接拿 jumpLink

当你在 AI 对话里触发 `semantic_search_library` 或 `semantic_search_current_book`，返回的 evidence 会带一个 `jumpLink`。

这个 `jumpLink` 就是可点击测试链接。

你要做的事情很简单。

把它复制出来，粘贴到备忘录或聊天框，然后点击。

如果 App 能被拉起并定位到对应位置，这个链路就通过了。

### 3.2 用书架检索工具拿到 bookId

如果你想自己构造链接，先需要 bookId。

最简单的方法是让 AI 调用工具 `bookshelf_lookup`。

你可以在 AI 里说一句类似这样的话。

“帮我查一下书架上标题包含 XXX 的书，给我它的 bookId。”

工具返回里会有 `bookId` 字段。

深链规范与注册位置可以参考：`docs/engineering/IDENTIFIERS_zh.md` 的 4.5 节。

## 4. iOS / iPadOS：带跑流程（建议第一条路线）

这部分是“讲解版流程”。你跑的时候仍然以 checklist 为准。

### 4.1 先做一次 smoke test

你只需要证明一件事。App 能冷启动，能打开一本书，能打开 AI 面板，能发出一次请求并拿到返回。

这一步如果不过，后面的所有 QA 都不值得跑，因为底座不稳。

### 4.2 Phase 3：AI 索引（书库）与全库检索

你可以把索引队列想成一个“排队叫号的厨房”。

厨房一次只做一道菜，这就是并发=1。做砸了会重做一次，这就是 retry-once。你把 App 杀掉再打开，正在做的菜回到队列里继续排队，这就是 running→queued 归一化。

你要验证的是这些厨房规则始终成立。

跑法建议是。

先选两本小书入队，观察它们从 queued 到 running，再到 succeeded。

然后再选一本大书入队，期间做 pause/resume。

最后做一次 cancel（对 running 或 queued）。

当你确认队列行为稳定，再去 AI 对话里让模型触发 `semantic_search_library`。

拿到 evidence 后复制 `jumpLink` 并点击，验证跨书跳转。

### 4.3 Memory（A–D 对齐 OpenClaw）

你可以把 Memory 当成“个人知识库的索引卡片柜”。

Markdown 文件是纸卡片，是事实来源。

`memory_index.db` 是你为了快速查卡片做的目录。目录可以丢掉再重建，纸卡片才是根。

你要验证的是。

第一，纸卡片能写能读。

第二，你能用关键词快速翻到相关卡片。

第三，当目录需要重建时，搜索不会卡死，而是先给你一个可用的结果，然后后台补齐。

第四，当你启用语义检索时，它能在“字面不完全匹配”的情况下找回相关内容。

跑法建议是。

先在 `MEMORY.md` 写一条含关键词的句子，再在某天 daily 写另一条。

然后在 Memory 页搜索这个关键词，看是否命中两个文件。

接着改一条内容并立刻再次搜索，观察非阻塞刷新是否符合预期。

如果你配置了 embeddings provider，就把语义检索设为 Auto，看 Effective 是否为 ON，并尝试用同义表达搜索。

最后把 embedding cache 上限设小一点，再多跑几次搜索，看看是否稳定。

### 4.4 OpenAI Responses 第三方兼容开关

你可以把 `previous_response_id` 想成“服务端记住了上一次对话的上下文编号”。

官方 OpenAI 会接受它，很多第三方网关会拒绝它。

所以我们把选择权交给你。

你要验证的是。

严格模式下工具调用链路稳定。

兼容模式下不会因为某个网关的 400 把整个链路打断。

你不需要抓包。

你只需要在 Provider Center 里把两个开关切换一次，再触发一次带工具调用的对话，观察是否仍能完成。

### 4.5 如何把问题反馈给我（这是最关键的一步）

当你遇到问题，先别急着描述“它坏了”。

我们更希望你给出可复现的实验记录。

把下面这段模板复制出来填一填就够。

```text
【设备】iPhone 15 Pro / iPad / Pixel 8 / 其他
【系统】iOS 18.x / Android 14
【App 版本】（TestFlight build / APK build / 或你能看到的版本号）
【安装方式】升级安装 / 全新安装
【Commit】（可选，若你能在 Mac 上运行 `git rev-parse --short HEAD`）

【复现步骤】
1.
2.
3.

【期望结果】

【实际结果】

【复现频率】必现 / 偶现（例如 3/10）
【截图/录屏】有 / 无
【补充信息】例如：embeddings 是否可用、Memory 语义检索 Effective 状态、Responses 两个开关当前状态
```

## 5. Android：带跑流程

Android 的整体跑法与 iOS 相同。差别在两点。

第一，deep link 测试环境可能更复杂，不同 App 对 scheme 点击的限制不一样。

第二，你有更强的日志工具，尤其是 `adb logcat`。

### 5.1 deep link 测试

把 `paperreader://reader/open?...` 粘贴到你常用的聊天工具或浏览器地址栏，点击。

如果不容易点击，就用“复制到浏览器地址栏再回车”的方式。

如果你电脑上有 adb，而且你想把复现过程变成一条可复制的命令，可以用这样的方式直接触发。

```bash
adb shell am start -W \
  -a android.intent.action.VIEW \
  -d "paperreader://reader/open?bookId=1&href=Text%2Fch1.xhtml"

adb shell am start -W \
  -a android.intent.action.VIEW \
  -d "paperreader://reader/open?bookId=1&cfi=epubcfi(%2F6%2F2%5Bchapter1%5D!%2F4%2F2%2F2%5Bpara1%5D)"
```

注意这里的 `bookId/href/cfi` 只是示例，你最好从 RAG evidence 的 `jumpLink` 里复制真实链接。

### 5.2 观察索引队列在压力下的稳定性

Android 更适合观察“资源约束下的行为”。

你可以在索引运行时。

切到后台，再切回来。

或者锁屏 30 秒再解锁。

如果系统杀进程，重启后队列是否能恢复，这是很重要的稳定性信号。

### 5.3 拿日志的最小方法（可选但很有用）

如果你电脑上有 adb，建议在复现时跑。

`adb logcat | rg -i "anx|paperreader|flutter"`

你不需要把所有日志发给我。

你只要把错误那几行贴出来就够。

## 6. macOS / Desktop（目前为 best-effort）

桌面端目前不作为发布 gate，但你可以做一条很轻量的 smoke。

能启动。

能打开一本书。

能打开 AI 面板并发出一次请求。

如果这些都没问题，我们就把桌面端的风险降到“后续再系统化回归”。

## 7. 结束标准（什么时候算“全部任务完成”）

我们完成任务的标准不是“代码合并了”。

而是。

iOS/iPadOS checklist 跑完，关键链路通过。

Android checklist 跑完，关键链路通过。

然后按 release 文档出包并回归。

做到这一步，才算真正意义上的 end-to-end 交付。
