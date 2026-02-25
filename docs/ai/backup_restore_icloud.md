# Manual Backup/Restore via Files / iCloud Drive — Tech Design (PR-7)

## 0. Implementation Status

See also:
- `docs/ai/mcp_servers_zh.md` (MCP secrets and server meta policies)

- Implementation status: integrated in product repo `main`
- Adds:
  - v5 backup ZIP with `manifest.json`
  - optional: include **Memory** directory (`memory/`)
  - optional: include AI index database (`databases/ai_index.db` + `-wal/-shm`, default OFF)
  - optional encrypted API keys
  - optional encrypted MCP secrets (headers/tokens; local-only by default)
  - import confirmation + rollback using `.bak.<timestamp>`

## 1. Background

Anx Reader already has **Export/Import** in `Settings → Sync`:

- Export creates a ZIP (legacy: `...-v3.zip`; current: `...-v5.zip`) containing:
  - documents assets (file/cover/font/bgimg)
  - database dir
  - shared prefs backup map (`paper_reader_shared_prefs.json`, legacy: `anx_shared_prefs.json`)
- Import picks a ZIP via `file_picker` and then **overwrites local** data.

This is already close to “manual iCloud backup/restore” on iOS because the Files picker can access iCloud Drive.

## 1. Goals (enhancements)

1. Make the feature iCloud-friendly and explicit in UX copy.
2. Offer **directional overwrite** clarity:
   - Local → iCloud (export)
   - iCloud → Local (import)
3. Optional: include **secrets encrypted** (password-based), for Apple-only migration:
   - API keys (Provider Center: built-in + custom providers)
     - Supports multi-key list (`api_keys`) and active key (`api_key`)
   - MCP server secrets (headers/tokens)
     - Only stored when user explicitly enables the option
4. Safe restore with rollback and WAL cleanup (reuse DB replacement approach).

## 2. UX Design

### Entry

`Settings → Sync → Export & Import`

- Export: “Export backup to Files/iCloud Drive”
- Import: “Import backup from Files/iCloud Drive (overwrite local)”

### Import confirmation

- Show a clear warning:
  - local database and files will be replaced
  - encrypted secrets (API keys / MCP secrets) are *not* restored unless user explicitly enabled the encrypted inclusion options

### Encrypted secrets options

On Export:

- Toggle: “Include API keys (encrypted)”
- Toggle: “Include MCP secrets (encrypted)”
- If any encrypted option is enabled:
  - prompt for password (twice)
  - store `encryptedApiKeys` and/or `encryptedMcpSecrets` blobs in manifest

On Import:

- If manifest indicates encrypted data:
  - prompt for password (once)
  - decrypt and apply to local-only storage

## 3. Backup Package Format (v5)

Export produces a v5 ZIP (filename suffix `-v5.zip`) and adds:

- `manifest.json` (schemaVersion = 5)
- Optional payload flags:
  - `containsMemory`
  - `containsAiIndexDb`

Example (as implemented in the product repo):

```json
{
  "schemaVersion": 5,
  "createdAt": 1730000000000,
  "containsMemory": true,
  "containsAiIndexDb": false,
  "containsEncryptedApiKeys": true,
  "containsEncryptedMcpSecrets": true,
  "encryptedApiKeys": {
    "kdf": {
      "alg": "PBKDF2-HMAC-SHA256",
      "saltB64": "...",
      "iterations": 150000
    },
    "encryption": {
      "alg": "AES-256-GCM",
      "nonceB64": "..."
    },
    "cipherTextB64": "..."
  },
  "encryptedMcpSecrets": {
    "kdf": {
      "alg": "PBKDF2-HMAC-SHA256",
      "saltB64": "...",
      "iterations": 150000
    },
    "encryption": {
      "alg": "AES-256-GCM",
      "nonceB64": "..."
    },
    "cipherTextB64": "..."
  }
}
```

Notes:
- API keys are only stored if the user explicitly enables the option.
- `paper_reader_shared_prefs.json` never contains plain `api_key` / `api_keys` entries (older backups may use `anx_shared_prefs.json`).
- `memory/` is only included if the user enables the option.
- `databases/ai_index.db` is only included if the user enables the option (default OFF). When included, its SQLite sidecars (`ai_index.db-wal` / `ai_index.db-shm`) are included as well.
- Encrypted payload stores per-provider keys:
  - `api_key` (active key)
  - `api_keys` (managed list; JSON)
- Multimodal chat attachments are **not included** in backups.

## 4. Crypto Details

Implementation (product): uses `package:cryptography`.

- KDF: PBKDF2-HMAC-SHA256, 150000 iterations, 16-byte salt
- Cipher: AES-256-GCM, 12-byte nonce, 16-byte tag

## 5. Safe Restore Procedure

1. Validate ZIP structure and manifest.
2. Extract to temp dir.
3. Close DB and stop readers (`DBHelper.close()` etc.)
4. **In-place backup** existing local dirs by renaming to `.bak.<timestamp>` (cheap + same filesystem):
   - documents: `file/ cover/ font/ bgimg`
   - optionally: `memory/` (only if user chooses to restore it)
   - databases dir (`databases/`)
5. Copy extracted dirs into the original locations.
   - if user does **not** restore `ai_index.db`, keep the local index by copying it back from the `.bak.*` databases backup
6. Reopen DB.
7. Apply prefs backup map.
8. If encrypted secrets included and password ok, apply to local-only storage:
   - API keys → aiConfig
   - MCP secrets → mcpServerSecretV1_*
9. If any step fails: rollback by deleting partial new dirs and renaming `.bak.*` back.

Implementation status (product): rollback-safe restore is implemented.

## 6. Testing

- iOS: export to iCloud Drive; import from iCloud Drive
- Wrong password behavior
- Partial/corrupt ZIP handling
- Large library performance

