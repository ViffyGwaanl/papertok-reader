# iOS EventKit（MethodChannel）系统工具：Reminders / Calendar

> 适用项目：Paper Reader（papertok-reader）
>
> 目标：为 AI Tools 提供一套 **可稳定调用、风险可控（Human-in-the-loop）** 的 iOS 原生系统能力。
>
> 说明：iOS 的日历/提醒事项由 **EventKit** 提供；Flutter 侧通过 MethodChannel 调用 Swift 实现。

## 安全策略（重要）

- **read-only** 工具：默认不需要额外确认（但仍受全局审批策略影响）。
- **write / destructive** 工具：会触发工具审批弹窗（Tool Safety）。
- destructive 操作（删除类）默认要求 **强制二次确认**（forceConfirmDestructive）。

## Reminders（提醒事项）

Channel：`ai.papertok.paperreader/reminders`

### 1) reminders_list_lists（只读）
列出 iOS Reminders 的清单（EventKit 里的 calendars for .reminder）。

返回：
- `lists[]`: `{id,title,isDefault}`

### 2) reminders_list（只读）
按时间窗口列出提醒事项。

输入：
- `listIds[]`（必填）
- `startIso`（可选，默认 now）
- `endIso`（可选，默认 start + 7 days）
- `days`（可选，默认 7，1..60；当 endIso 省略时生效）
- `includeCompleted`（可选，默认 false）
- `includeUndated`（可选，默认 false；会额外查询未设置 due 的提醒）
- `limit`（可选，默认 200，最大 1000）
- `includeNotes`（可选，默认 false）
- `notesMaxLen`（可选，默认 400，最大 8000）

返回：
- `startIso/endIso/count/truncated`
- `reminders[]`：
  - `id,title,listId,completed,dueIso,completionIso`
  - 可选：`priority,url,notes,notesTruncated`

### 3) reminders_get（只读）
按 id 获取单条提醒事项。

输入：
- `reminderId`（必填）
- `includeNotes`/`notesMaxLen`（可选）

返回：`reminder`（结构同 reminders_list 的元素）

### 4) reminders_create（写入，需要确认）
创建提醒事项。

输入：
- `title`（必填）
- `notes`（可选）
- `dueIso`（可选；若设置 alarmMinutes 必须提供 dueIso）
- `listId` / `calendarId`（可选；calendarId 作为兼容别名）
- `priority`（可选 0..9）
- `url`（可选）
- `alarmMinutes`（可选：number 或 number[]；表示在 dueDate 前 N 分钟提醒）

返回：`id,title,listId`

### 5) reminders_update（写入，需要确认）
更新提醒事项字段。

输入：
- `reminderId`（必填）
- 可更新字段：`title, notes, dueIso, clearDue, listId, priority, url, alarmMinutes, clearAlarms`

返回：`ok,id`

### 6) reminders_complete / reminders_uncomplete（写入，需要确认）
标记完成 / 取消完成。

输入：`reminderId`（必填）

返回：`ok,id,completed`

### 7) reminders_delete（删除，destructive，需要确认）
删除提醒事项。

输入：`reminderId`（必填）

返回：`ok,id`

### 8) reminders_list_create / reminders_list_rename / reminders_list_delete（写入/删除）
清单（list）管理。

- create：`title`
- rename：`listId,title`
- delete（destructive）：`listId`

> 注意：删除清单属于高风险操作，建议在设置里关闭该工具或保持默认“始终确认”。

---

## Calendar（日历事件，iOS EventKit 通道）

Channel：`ai.papertok.paperreader/calendar_eventkit`

> Flutter 层对外保持工具 id 为 `calendar_*`，但在 iOS 上已路由到 EventKit 通道以支持：
> - `alarmMinutes[]`
> - `span`（重复事件：仅本次 / 未来）
> - `recurrence`（基础重复规则）

### 1) calendar_list_calendars（只读）
返回：
- `calendars[]`: `{id,name,readOnly}`

### 2) calendar_list_events（只读）
输入：
- `startIso/endIso/days/calendarIds/maxResults/includeDescription/includeAlarms`

返回：
- `events[]`：`{title,startIso,endIso,allDay,location?,description?,calendarId,eventId,instanceId,isRecurring,alarmMinutes?}`

### 3) calendar_get_event（只读）
输入：
- `eventId`（必填，支持 eventId 或 instanceId）
- `includeDescription/includeAlarms`

返回：`event`

### 4) calendar_create_event（写入，需要确认）
输入：
- 基础：`title,startIso,endIso,isAllDay,location,description,calendarId`
- iOS-only：
  - `timeZone`
  - `alarmMinutes`（number 或 number[]）
  - `recurrence`：`{frequency: daily|weekly|monthly|yearly, interval?, count?, untilIso?}`

返回：包含 `ok,eventId,instanceId,...`

### 5) calendar_update_event（写入，需要确认）
输入：
- `eventId`（必填，可为 instanceId）
- 可选字段：`title,startIso,endIso,isAllDay,location,description,timeZone,calendarId`
- iOS-only：`span`（thisEvent|futureEvents）、`alarmMinutes/clearAlarms`、`recurrence/clearRecurrence`

返回：`ok,eventId,span`

### 6) calendar_delete_event（删除，destructive，需要确认）
输入：
- `eventId`（必填，可为 instanceId）
- iOS-only：`span`（thisEvent|futureEvents）

返回：`ok,eventId,span`

---

## 兼容性说明

- Android：仍使用 `device_calendar_plus` 的跨平台实现（不支持 alarms/span/recurrence 的完整能力）。
- iOS：通过 EventKit 通道实现高级能力，并兼容 `device_calendar_plus` 的 instanceId 结构（`eventId@startMillis`）。

## QA 建议（最小闭环）

1) Reminders：listLists → list(未来7天) → create → update(改期) → complete → uncomplete → delete
2) Calendar：listCalendars → create(alarmMinutes=10) → listEvents(includeAlarms) → update(span=thisEvent) → delete
3) 重复事件：create(recurrence weekly) → listEvents → update(span=futureEvents) 验证只影响未来
