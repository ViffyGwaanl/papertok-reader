# MCP Servers（外部工具）— 产品说明与实现要点（Paper Reader）

> 本文描述 Paper Reader（papertok-reader）中 **External MCP Servers** 的产品行为、配置策略、同步/备份规则与关键实现点。
>
> 目标：让用户能够把第三方 MCP Server 的 tools 注入到 AI Agent 工具箱中，并在移动端稳定可用（连接测试、缓存、超时、取消、输出裁剪、安全审批）。

---

## 1. 你能在 App 里做什么（用户视角）

入口：Settings → MCP Servers

- 添加/编辑 MCP Server
  - 名称
  - Endpoint（URL）
  - Transport Mode：Auto / Streamable HTTP / Legacy HTTP+SSE
  - Enable 开关（启用后其 tools 才会注入 Agent 工具箱）
- 认证（Auth）配置（本地保存；默认不同步）
  - None
  - Bearer Token
  - API Key（header 名可配置）
  - Basic Auth
  - Custom headers
- Test Connection
  - 发送 initialize + tools/list
  - 探测 Streamable SSE（GET）支持情况（例如 405/Allow）
- Tools cache
  - 查看缓存状态（最后刷新时间/是否为空）
  - Refresh all / Clear cache
  - 查看 tools 列表与 schema
- 运行时参数（per-server）
  - tools/list timeout
  - tools/call timeout
  - Max tool result length（输出裁剪上限）

---

## 2. 同步与备份策略（安全与可用性）

### 2.1 WebDAV 同步（跨设备）
- **会同步**（non-secret）：
  - server metas（id/name/endpoint/enabled/transportMode…）
  - `mcp.autoRefreshToolsV1`（默认 OFF）
- **不会同步**（secret）：
  - 认证信息（headers/tokens/bearer/basic 等）默认仅本机

对应说明文档：
- `docs/ai/ai_settings_sync_webdav.md`（mcp.servers / autoRefreshToolsV1）

### 2.2 手动备份/恢复（Files/iCloud）
- 明文备份：
  - 不包含任何 API keys
  - 不包含 MCP secrets
- 加密备份（可选）：
  - **可选包含 MCP secrets（headers/tokens）**

对应说明文档：
- `docs/ai/backup_restore_icloud.md`

---

## 3. 传输协议支持（Transport）

Paper Reader 支持 MCP 两类 transport，并提供 Auto 探测：

### 3.1 Streamable HTTP（优先）
- initialize：POST
- tools/list：POST
- tools/call：POST
- streaming：SSE（GET；必要时支持 Last-Event-ID resume；解析 retry:）

### 3.2 Legacy HTTP + SSE（兼容）
- 当 Streamable initialize 遇到 400/404/405 时自动 fallback
- 使用 GET SSE 的 event:message / event:endpoint 风格

---

## 4. Tool 注入与命名约束（重要）

### 4.1 工具注入时机
- MCP tools 会在 Agent 模式下被注入到可调用工具集。
- 通过缓存优先策略避免每次都 tools/list。

### 4.2 OpenAI 工具名正则约束
OpenAI（尤其 Responses）对 `tools[].name` 有硬约束：
- 只允许：`^[a-zA-Z0-9_-]+$`

因此 MCP tools **不能使用包含点号的命名空间**（例如 `mcp.server.tool` 会导致 400）。

Paper Reader 已采用：
- `mcp_<serverKey>_<toolKey>`

（并对 server/tool 名做清洗与长度预算，以避免超长 name 被后端拒绝。）

---

## 5. Tool Safety（人类审批）

MCP tools 的执行受 Tool Safety 体系保护：
- 对写入/破坏性操作需要审批
- 输出会进行 sanitize + truncation，避免把超长/不安全内容直接注入对话

---

## 6. 可靠性策略（超时/取消/输出裁剪）

- per-server 超时：tools/list 与 tools/call 分别可配
- 输出裁剪：按 server.maxResultCharsV1（clamp 1000..50000）
- 取消语义：Stop/timeout best-effort 发送 `notifications/cancelled`
- SSE 健壮性：
  - 缓冲解析
  - 早结束时按 Last-Event-ID resume
  - retry: 支持

---

## 7. 实现定位（开发者）

### UI
- `lib/page/settings_page/mcp_servers.dart`
- `lib/page/settings_page/mcp_server_detail_page.dart`
- `lib/page/settings_page/mcp_auth_editor.dart`

### Models
- `lib/models/mcp_server_meta.dart`
- `lib/models/mcp_tool_meta.dart`
- `lib/models/mcp_transport_mode.dart`

### Client / Registry
- `lib/service/mcp/mcp_client_service.dart`
- `lib/service/mcp/mcp_streamable_http_client.dart`
- `lib/service/mcp/mcp_legacy_http_sse_client.dart`
- `lib/service/mcp/mcp_tool_registry.dart`

### Sync / Prefs
- `lib/service/sync/ai_settings_sync.dart`
- `lib/config/shared_preference_provider.dart`

---

## 8. QA Checklist（建议）

1) 添加 server（Auto）→ Test Connection 成功
2) 启用 server → Refresh tools cache → tools 列表可见
3) Agent 调用某个 MCP tool：
   - 输出被裁剪（如超过上限）
   - 超时触发取消
4) 关闭 server enabled → 不应出现在工具列表里
5) WebDAV 同步：另一台设备只同步 server meta，不同步 secrets
6) 加密备份勾选 MCP secrets：导入后 secrets 恢复；明文备份不包含
