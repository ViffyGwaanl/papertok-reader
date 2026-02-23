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
