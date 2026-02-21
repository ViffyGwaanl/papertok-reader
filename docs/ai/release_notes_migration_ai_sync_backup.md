# Release Notes / Migration Notes — AI sync, backup, Provider Center, streaming

This note summarizes user-visible behavior changes introduced by the AI/translation stack in the product repo (`papertok-reader:main`).

---

## 1) WebDAV AI settings sync (no API key)

### What users get

- AI configuration (provider list + url/model/prompts/UI prefs) can be synced via WebDAV.
- Reduces repetitive setup across devices.
- WebDAV remote root is **`paper_reader/`** (legacy fallback: `anx/`).

### Security policy

- **API keys are not synced** via WebDAV.

### Merge semantics

- Phase 1: whole-file snapshot `updatedAt` newer-wins.

---

## 2) Manual backup/restore v4 (Files/iCloud) + optional encrypted API keys

### What users get

- Export creates a `-v4.zip` backup including `manifest.json`.
- Optionally include API keys **encrypted** with a password.
- Import shows a warning confirmation and performs rollback-safe restore.

### Security policy

- Plain prefs backup **never contains** `api_key`.
- Importing a plaintext backup **never overwrites/clears** existing local API keys.
- API keys are only restored when:
  - the backup was created with encrypted API keys enabled, and
  - the correct password is provided during import.

---

## 3) Provider Center (Cherry-inspired)

### What users get

- A dedicated Provider Center to manage:
  - built-in providers
  - custom providers
  - enable/disable
  - apply/select provider
- In-chat provider/model switching.

---

## 4) Reading page AI bottom sheet: minimize/continue streaming

### What users get

- Bottom sheet can be minimized to a small bar so you can keep reading.
- **Streaming is provider-managed** (not UI-managed): minimizing/closing the panel should not interrupt ongoing generation.

### Notes

- “Stop” still cancels generation immediately.

---

## 5) Thinking content display

- Gemini: optional includeThoughts to display Thinking section.
- OpenAI-compatible: if backend returns `reasoning_content`/`reasoning`, it is displayed as Thinking content.

---

## 6) Multimodal attachments + EPUB image analysis

### What users get

- Chat attachments (v1): images + plain text files.
- EPUB image analysis: tap an image → analyze with a multimodal model + surrounding context.
- Image analysis can use a dedicated provider/model (separate from chat/translation).

### Privacy / sync policy

- Attachments are **not synced** and **not included in backup**.

---

## Recommended user guidance

- Use WebDAV sync for day-to-day config sync.
- Use v4 backup export/import for device migration and offline safety.
- Do not paste API keys into chat logs; treat leaked keys as compromised and rotate them.
