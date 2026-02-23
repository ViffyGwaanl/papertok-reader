# 快捷指令（Shortcuts）AI 工具：回到 App + 回传结果（x-callback-url）

> 适用项目：Paper Reader（papertok-reader）
>
> 对应工具：`shortcuts_run`
>
> 目标：
> 1) 运行某个快捷指令后 **自动回到 Paper Reader**
> 2) （可选）快捷指令把一个 **小结果** 回传给 Paper Reader，让 AI 继续推理

---

## 1. App 侧能力（你已经集成）

- 工具会以 `shortcuts://x-callback-url/run-shortcut` 的方式启动快捷指令
- 并设置回调：
  - `x-success` → `paperreader://shortcuts/success?runId=...`
  - `x-cancel`  → `paperreader://shortcuts/cancel?runId=...`
  - `x-error`   → `paperreader://shortcuts/error?runId=...`

因此：即使快捷指令不主动回传结果，执行结束也会回到 App，并让工具调用结束。

---

## 2. 如何在快捷指令里“回传结果”（推荐）

### 回传 URL（文本小结果）
在快捷指令最后添加一个动作：**打开 URL**。

URL 形式：

```
paperreader://shortcuts/result?runId=<runId>&data=<text>
```

其中：
- `<runId>`：从“快捷指令输入（Shortcut Input）”里拿到
- `<text>`：你希望回传给 AI 的文本（建议短一点）

### 回传 Base64URL（更稳，避免特殊字符）
如果结果文本包含很多特殊字符/换行，建议回传 `dataB64`：

```
paperreader://shortcuts/result?runId=<runId>&dataB64=<base64url>
```

> base64url = base64 的变体：把 `+` 替换成 `-`，把 `/` 替换成 `_`，并去掉尾部 `=`。

---

## 3. runId 怎么从快捷指令输入里取？

当 `shortcuts_run` 开启 `waitForCallback=true`（默认）时，工具会把一个 JSON 作为“快捷指令输入”传入：

```json
{"runId":"...","text":"...","inputModeRequested":"text|clipboard"}
```

快捷指令里推荐这样取：

1) 动作：**获取快捷指令输入**（Get Shortcut Input）
2) 动作：**从输入/文本获取词典（Dictionary）**（把 JSON 解析成 Dictionary）
   - 不同 iOS 版本动作名称略有差异，核心就是“JSON → Dictionary”
3) 动作：**从词典获取值**（Get Dictionary Value），Key 填 `runId`

得到 `runId` 后，就可以拼接回传 URL。

---

## 4. 回传结果长度限制（可在设置里调）

设置位置：
- 设置 → AI 工具 → **快捷指令回传结果长度上限**

说明：
- 回传数据过长会被截断（避免 URL 太长导致系统/Shortcuts/回调不稳定，也避免 AI 上下文膨胀）。
- 默认值建议 8000 字符。

## 5. 回传等待超时（可在设置里调）

设置位置：
- 设置 → AI 工具 → **快捷指令回传等待超时**

说明：
- 工具会“最多等待 N 秒”，一旦 Shortcuts 回传（success/result/error/cancel）就会立刻结束，不会强制等满。
- 适用场景：
  - 很快返回：可以设置 5~10 秒
  - 长任务：可以设置 120 秒甚至更高（上限 300 秒）

## 6. 等待策略（更智能，可在设置里调）

设置位置：
- 设置 → AI 工具 → **快捷指令回传等待策略**

模式说明：
- **自适应（推荐）**：如果某个快捷指令曾经回传过 `/result`，之后就会更倾向“优先等结果”；否则收到 `/success` 就快速结束（避免无结果的快捷指令卡住）。
- **自动（更快）**：收到 `/success` 后只短暂等一下（几百毫秒），只有 `/result` 立刻到达才会使用。
- **优先等结果**：即使先收到 `/success`，也会继续等 `/result` 直到超时；如果超时则返回 `/success`。
- **只看成功**：收到 `/success` 立刻结束，不再等 `/result`。

另外：
- App 会“学习”哪些快捷指令会回传 `/result`，你可以在该设置页里清空学习记录。

---

## 5. 最小示例（伪流程）

快捷指令动作顺序示意：
1) Get Shortcut Input
2) Parse JSON → Dictionary
3) Get Value for Key `runId`
4) 生成你想回传的 `resultText`
5) URL = `paperreader://shortcuts/result?runId=<runId>&data=<resultText>`
6) Open URL

完成。
