# PaperTok Reader — Swift Native Migration Requirements Document (PRD)

**Date:** 2026-04-03
**Type:** Full 1:1 Migration + Apple-style UI Redesign
**Source:** Flutter project analysis (551+ Dart files, 217 services, 47 pages, 46 AI tools)

---

## 1. Product Overview

### 1.1 Product Name
PaperTok Reader (native Swift iOS/macOS)

### 1.2 Product Vision
A premium e-book reader for iOS and macOS with integrated academic paper discovery, AI-powered chat/analysis, and comprehensive reading management — rebuilt as a native Apple platform app with SwiftUI.

### 1.3 Target Platforms
- iOS 17.0+ (iPhone + iPad)
- macOS 14.0+ (Sonnet)

### 1.4 Bundle ID
`ai.papertok.paperreader` (preserved from Flutter)

---

## 2. Feature Requirements

### FR-01: App Navigation & Layout

**FR-01.1 iOS Navigation (iPhone)**
- Bottom tab bar with 6 tabs: Papers, Bookshelf, Notes, Statistics, AI, Settings
- Floating glass morphism tab bar with blur effect on mobile
- Tab bar auto-hides when keyboard is visible
- Tab bar animates in/out (220ms)
- Acceptance: All 6 tabs accessible, smooth transitions

**FR-01.2 iOS Navigation (iPad)**
- NavigationSplitView with sidebar + detail
- Split view support in landscape
- Acceptance: Sidebar navigation, detail pane updates correctly

**FR-01.3 macOS Navigation**
- Sidebar navigation (NavigationSplitView)
- Menu bar commands (File > Import Book, Reading shortcuts)
- Keyboard shortcuts (Cmd+O import, arrow keys page turn, Cmd+\ toggle AI)
- Window management (resizable, remembers position)
- Acceptance: Full keyboard navigation, menu bar functional

**FR-01.4 Tab Customization**
- Reorderable tabs via Settings > Home Navigation
- Enable/disable individual tabs
- Changes apply immediately
- Acceptance: Drag reorder works, disabled tabs hidden

---

### FR-02: PaperTok (Academic Papers)

**FR-02.1 Paper Feed**
- Vertical swipeable card feed
- Each card: image carousel with dots, title, summary, publication date
- Gradient overlay for text readability
- Auto-loads more papers when 3 cards from end
- Acceptance: Smooth scrolling, images load, pagination works

**FR-02.2 Paper Actions**
- Like/favorite toggle per paper
- Liked-only filter
- Date filter (Latest, All days, Pick a date)
- Search by title/summary
- Refresh button
- Acceptance: All filters work independently and combined

**FR-02.3 Paper Detail**
- Full paper details (abstract, authors, links, images)
- Download PDF/EPUB with progress indicator
- Cancellable download
- Import to bookshelf after download
- External links to arxiv/venues
- Acceptance: Download completes, book appears in bookshelf

**FR-02.4 PaperTok API Integration**
- REST client for `https://papertok.ai`
- Random paper fetch with language selection (zh/en)
- Paper detail fetch by ID
- Date-based paper browsing
- Acceptance: API calls succeed, data displays correctly

---

### FR-03: Bookshelf

**FR-03.1 Book Grid/List View**
- Grid view with book covers (aspect ratio 1:2.1)
- Responsive columns based on screen width
- Sort options: title, author, date added, custom order (asc/desc)
- Acceptance: Grid renders, sort changes order correctly

**FR-03.2 Reading Status Filter**
- Filter chips: Finished, Reading, Not Started
- Multiple filters selectable simultaneously
- Acceptance: Filters combine correctly

**FR-03.3 Tag System**
- Tag filter button opens tag selection sheet
- Create/edit/delete tags with color
- Assign tags to books
- "No Tag" virtual filter option
- Long press tag to edit/delete
- Acceptance: Tag CRUD works, filter applies correctly

**FR-03.4 Hierarchical Groups (Folders)**
- Nested folder structure
- Create/rename/delete groups
- Drag-and-drop books between groups
- Dissolve group (move all books out)
- Acceptance: Folder hierarchy works, drag-drop reorders

**FR-03.5 Book Import**
- Import from Files app / iCloud
- Import via Share Extension
- Import via drag-and-drop (iPad/Mac)
- Cover image extraction from EPUB
- Duplicate detection via MD5
- Acceptance: All import methods work, covers display

**FR-03.6 AI-Assisted Organization**
- Bookshelf organize tool (propose grouping plan)
- User confirmation required before applying
- Acceptance: AI plan displays, apply creates correct groups

**FR-03.7 Book Context Menu**
- Long press/right-click opens options
- Options: Open, Edit, Delete, Move to group, Tags
- Soft delete with undo option
- Acceptance: All context actions work

---

### FR-04: EPUB Reader (Readium SDK)

**FR-04.1 EPUB Rendering**
- Readium EPUBNavigatorViewController via UIViewControllerRepresentable
- Chapter-by-chapter rendering with proper formatting
- Images, tables, formatted text display correctly
- CFI-based position tracking
- Acceptance: EPUB opens, renders correctly, position saves

**FR-04.2 Navigation**
- Page turning: swipe, edge-tap, button (configurable)
- Chapter navigation via TOC
- Progress bar with percentage
- Full-text search within book
- Acceptance: All navigation methods work

**FR-04.3 Text Selection & Annotation**
- Long press to select text
- Color-coded highlights (5 colors: yellow, red, blue, green, purple)
- Bookmarks
- Notes with markdown support
- Acceptance: Selection works, annotations persist across sessions

**FR-04.4 Reading Settings (Per-Book)**
- Font: size, family (system + Source Han Serif + downloaded)
- Spacing: line height, letter spacing, word spacing
- Margins: paragraph, side, top, bottom
- Theme: light/dark/custom background images
- Page turn mode selection
- Text alignment
- Acceptance: All settings adjust rendering in real-time

**FR-04.5 Reading Progress**
- Percentage display
- Last read position auto-restored on reopen
- Reading time tracking per session
- Acceptance: Progress accurate, position restores

**FR-04.6 In-Reader Image Viewer**
- Tap image to open full-screen viewer
- Pinch to zoom, drag to pan, double-tap to fit
- AI analysis button (uses image analysis provider)
- Save/share image
- Acceptance: Viewer opens, zoom works, AI analysis returns result

---

### FR-05: PDF Reader (Readium SDK)

**FR-05.1 PDF Rendering**
- Readium PDFNavigatorViewController via UIViewControllerRepresentable
- Page-by-page navigation
- Text extraction for AI analysis
- Acceptance: PDF opens, pages render, text extractable

---

### FR-06: AI Chat System

**FR-06.1 Chat Interface**
- Message history with scroll
- User/assistant message bubbles
- Streaming response display with real-time text
- Minimize button (keeps generating while reading)
- Smart auto-scroll on new content
- Empty state shows quick prompt suggestions (up to 3)
- Acceptance: Messages send/receive, streaming renders smoothly

**FR-06.2 Provider Center**
- Built-in providers: OpenAI, Anthropic Claude, Gemini, Volcengine Ark
- Custom OpenAI-compatible endpoints
- Per-provider: API endpoint, API keys (multiple with rotation), model selection
- Fetch available models from provider
- Test connection
- Provider reorder and enable/disable
- Acceptance: All providers configurable, connections test successfully

**FR-06.3 In-Chat Provider Switching**
- Switch provider/model without leaving chat
- Provider selector in chat header
- Acceptance: Switch works mid-conversation

**FR-06.4 Thinking Mode**
- Thinking level selector (档位)
- Collapsible thinking/answer/tools sections
- Maps `reasoning_content`/`reasoning` to `<think>` display
- Only display what providers return (no fallback summaries)
- Acceptance: Thinking content displays correctly per provider

**FR-06.5 Conversation Tree v2**
- Per-turn assistant variants (switch between regenerations)
- Rollback to old variant without losing subsequent turns
- Edit any user turn and branch from there
- Persistent across app restart (JSON-serialized)
- Acceptance: Branching works, history navigable, persists

**FR-06.6 Multimodal Attachments**
- Up to 4 images + 3 text files (configurable limits)
- Image MIME normalization
- SVG → JPEG rasterization for compatibility
- Base64 image support for Volcengine Ark
- Acceptance: Attachments send, images display in provider

**FR-06.7 Chat History**
- Conversation list with auto-generated titles
- Load/restore previous conversations
- Delete conversations
- Acceptance: History persists, loads correctly

**FR-06.8 Token/Cost Tracking**
- Display tokens used and estimated cost after stream completion
- Built-in pricing tables for 5 model families
- Usage history
- Acceptance: Accurate counts display after responses

---

### FR-07: AI Tools (46 Tools)

**FR-07.1 Tool Calling Protocol**
- Unified AITool protocol with name, description, parameters schema
- Tool orchestrator with concurrent execution (safe partitioning)
- Approval delegate for write/destructive tools
- Annotation ledger (prevent duplicate highlights)
- Scene-aware filtering (reading scene ~50% fewer tools)
- Acceptance: Tools execute correctly, approval dialogs show

**FR-07.2 Utility Tools (5)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `calculator` | Evaluates arithmetic, returns result |
| `current_time` | Returns ISO-8601 local/UTC time |
| `fetch_url` | Fetches HTTP content, truncates to maxBytes |
| `web_search` | Returns search results (Serper or DuckDuckGo) |
| `spawn_sub_agent` | Delegates task, returns result text |

**FR-07.3 Reading Tools (11)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `current_reading_metadata` | Returns book/progress/chapter when reading |
| `current_book_toc` | Returns hierarchical TOC with percentages |
| `current_chapter_content` | Returns plain text of current chapter |
| `chapter_content_by_href` | Returns chapter text by TOC href |
| `current_book_fulltext` | Returns full text if <50K chars, refuses otherwise |
| `resolve_cfi` | Converts CFI to chapter metadata |
| `book_content_search` | Keyword search with snippets per chapter |
| `semantic_search_current_book` | Vector search with jump links |
| `create_highlight` | Creates highlight at CFI with color |
| `create_note` | Creates markdown note at CFI |
| `mindmap_draw` | Generates mind map JSON from bullet list |

**FR-07.4 Library Tools (8)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `bookshelf_lookup` | Finds books by title/author/group |
| `bookshelf_organize` | Drafts reorganization plan (requires confirmation) |
| `notes_search` | Searches notes by keyword/book/date |
| `reading_history` | Returns reading sessions with filters |
| `semantic_search_library` | Hybrid vector+FTS search across library |
| `tags_list` | Lists all tags with colors |
| `books_tags_list` | Lists books with their tags |
| `apply_book_tags` | Plans tag changes (requires confirmation) |

**FR-07.5 Calendar Tools (6)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `calendar_list_calendars` | Lists device calendars |
| `calendar_list_events` | Lists events in date range |
| `calendar_get_event` | Gets single event details |
| `calendar_create_event` | Creates event (requires approval) |
| `calendar_update_event` | Updates event with span support |
| `calendar_delete_event` | Deletes event (destructive, requires approval) |

**FR-07.6 Reminders Tools (12)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `reminders_list_lists` | Lists all reminder lists |
| `reminders_list` | Lists reminders with filters |
| `reminders_get` | Gets single reminder |
| `reminders_create` | Creates reminder with notes/alarm/priority |
| `reminders_update` | Updates reminder fields |
| `reminders_complete` | Marks complete |
| `reminders_uncomplete` | Marks incomplete |
| `reminders_delete` | Deletes reminder (destructive) |
| `reminders_list_create` | Creates reminder list |
| `reminders_list_rename` | Renames list |
| `reminders_list_delete` | Deletes list (destructive) |
| `shortcuts_run` | Runs iOS Shortcut via x-callback-url |

**FR-07.7 Memory Tools (4)**
| Tool | Acceptance Criteria |
|------|-------------------|
| `memory_read` | Reads daily.md or MEMORY.md |
| `memory_search` | Hybrid text+vector search in memory |
| `memory_append` | Appends text to memory file (requires approval) |
| `memory_replace` | Replaces memory file content (requires approval) |

---

### FR-08: AI Panel (In-Reader)

**FR-08.1 iPad Dock Mode**
- Resizable side panel (drag handle)
- Width persisted per-book
- Left/right side toggle
- Minimize button (keeps generating in background)
- Smart auto-scroll on new content
- Acceptance: Panel resizes, persists, minimize works

**FR-08.2 iPhone Bottom Sheet**
- Draggable sheet with snap points
- Minimize bar for background generation
- No accidental dismissal on text input
- Acceptance: Sheet opens, minimizes, keyboard doesn't dismiss

---

### FR-09: Translation Engine

**FR-09.1 Translation Providers**
- AI translation (via configured LLM)
- DeepL API
- Google Translate API
- Microsoft Translator API
- WebView-based (Bing, Google) for no-API-key fallback
- Acceptance: Each provider translates correctly

**FR-09.2 Inline Full-Text Translation**
- Immersive mode (translation below original text)
- Per-book segment cache
- Clear/retry cache options
- Progress HUD (top-right, closable)
- Chunking to reduce timeouts
- Acceptance: Translation renders inline, cache works

**FR-09.3 Selection-Based Translation**
- Select text → translate + explain/vocab/notes
- Acceptance: Selection triggers translation popup

---

### FR-10: RAG (Retrieval-Augmented Generation)

**FR-10.1 Embedding Service**
- OpenAI-compatible embedding endpoints
- Local embedding support (Ollama + FTS5 fallback)
- Multi-key rotation
- Acceptance: Embeddings generate correctly

**FR-10.2 Text Chunking**
- Fixed-size with overlap
- Paragraph-based
- AI-assisted semantic chunking
- Acceptance: Text splits into meaningful chunks

**FR-10.3 Book Indexing**
- Per-book semantic index building
- Library-wide indexing queue (pause/resume/cancel)
- Progress tracking with auto-retry
- Headless reader bridge for background extraction
- Restart recovery
- Acceptance: Index builds, survives app restart

**FR-10.4 Semantic Search**
- Current book vector search
- Library-wide hybrid search (FTS5 + vector + MMR)
- Results with jump links
- Acceptance: Relevant results returned with links

---

### FR-11: Memory System

**FR-11.1 Memory Storage**
- Markdown files: daily.md, MEMORY.md, review_inbox/
- Read/write/search operations
- Acceptance: Files persist, content round-trips

**FR-11.2 Memory Workflow**
- Session digest (summarize chat turns)
- Candidate ranking and selection
- Review inbox with accept/reject/delete
- Memory write coordinator (deduplication, conflict resolution)
- Acceptance: Candidates generate, review workflow works

**FR-11.3 Memory Search**
- Hybrid BM25 + vector search
- Temporal decay
- MMR deduplication
- Acceptance: Search returns relevant memories

---

### FR-12: Notes & Highlights

**FR-12.1 Unified Notes View**
- All notes across all books
- Group by book
- Statistics: total notes count, books with notes
- Search within notes
- Acceptance: Notes display, search works

**FR-12.2 Note Types**
- Highlights (with 5 colors)
- Bookmarks
- Notes (with markdown content)
- Acceptance: All types create and display

**FR-12.3 Notes Export**
- Export formats: Markdown, CSV, TXT, Clipboard
- Acceptance: Export produces correct format

---

### FR-13: Statistics & Analytics

**FR-13.1 Dashboard**
- Customizable tiles (add/remove/reorder)
- Summary: total books, dates, notes
- Acceptance: Dashboard renders, tiles customizable

**FR-13.2 Heatmap Calendar**
- Reading streak visualization
- Color intensity by reading time
- Acceptance: Calendar renders, colors match data

**FR-13.3 Reading Trends**
- Daily reading time charts (week/month/year view)
- Per-book daily reading breakdown
- Acceptance: Charts render with correct data

**FR-13.4 Reading Streak**
- Current streak and longest streak
- Acceptance: Streak calculation correct

**FR-13.5 Reading Completion**
- Books 60-93% complete (nearly finished)
- Acceptance: Correct books listed

**FR-13.6 Random Daily Highlight**
- Random highlight from any book
- Refresh button
- Acceptance: Highlight displays with book context

---

### FR-14: Sync & Backup

**FR-14.1 WebDAV Sync**
- Server URL, username, password configuration
- Test connection
- AI settings snapshot sync (newer-wins)
- Exclude api_key from sync
- Sync triggers: app background/foreground, manual
- Sync direction: upload, download, both
- Acceptance: Settings sync correctly, no API key leaks

**FR-14.2 Backup/Restore**
- Export encrypted backup (ZIP with password)
- Import backup from Files
- Plain backups exclude API keys
- Encrypted backups optionally include API keys
- Optional: include memory/ and ai_index.db
- Acceptance: Backup creates, restore works, keys handled correctly

**FR-14.3 Database Sync**
- Safe download with validation and recovery
- Temp file handling, backup rotation
- Atomic replacement
- Acceptance: Database syncs without corruption

---

### FR-15: TTS (Text-to-Speech)

**FR-15.1 System TTS**
- AVSpeechSynthesizer integration
- Voice selection by language
- Speed/rate control
- Now Playing integration (Lock Screen/Control Center)
- Acceptance: TTS plays, controls on lock screen

**FR-15.2 Online TTS Providers**
- OpenAI TTS API
- Azure Speech Services
- Aliyun TTS
- Acceptance: Each provider generates audio

**FR-15.3 TTS in Reader**
- Play/pause FAB button
- Sentence-by-sentence tracking
- Audio session management
- Acceptance: TTS reads current chapter, highlights position

---

### FR-16: Settings (47 pages total)

**FR-16.1 Appearance**
- Theme: System/Light/Dark
- Accent color picker
- OLED dark mode toggle
- Language selector (14 languages)
- Bookshelf folder style
- E-ink mode toggle
- Acceptance: All settings apply immediately

**FR-16.2 Reading Preferences**
- Page turn mode (swipe, tap, button)
- Font management (system + custom fonts)
- Chapter split rules (custom regex)
- Reading duration display
- Acceptance: Settings persist per-book

**FR-16.3 AI Settings**
- Provider Center (full CRUD)
- System prompt editor (max 20K chars)
- Quick prompts editor (reorderable)
- Image analysis provider/model override
- Library index management
- Tool approval policies
- Thinking mode configuration
- Title generation settings
- Acceptance: All AI configs save and apply

**FR-16.4 MCP Servers**
- Server list (add/edit/delete/reorder)
- Per-server: name, endpoint, transport mode, auth
- Test connection
- Tool cache and refresh
- Import/export JSON config
- Acceptance: MCP servers connect, tools discoverable

**FR-16.5 Share & Shortcuts**
- Default share routing (auto/ai_chat/bookshelf/ask)
- Prompt presets with preview
- Share inbox diagnostics
- TTL configuration
- Acceptance: Share routes correctly, diagnostics display

**FR-16.6 Memory Settings**
- Memory candidates list (pending/accepted/rejected)
- Accept/reject/delete candidates
- Search candidates
- Acceptance: Candidate workflow works

**FR-16.7 Storage**
- Database size display
- Cache management with clear button
- Storage path info
- Acceptance: Sizes display, cache clears

**FR-16.8 Developer Options**
- Vibration test page
- Log viewer (filter by level/source)
- Log export
- Acceptance: Logs display, export works

---

### FR-17: Platform Integration

**FR-17.1 EventKit (Calendar & Reminders)**
- Direct Swift EventKit (no bridge needed)
- Calendar: list, get, create, update, delete events
- Reminders: full CRUD + lists + complete/uncomplete
- Recurring events with span support
- Permission request dialogs
- Acceptance: All operations work, permissions handled

**FR-17.2 App Intents (Shortcuts)**
- `SendMessageIntent`: send text + images to AI
- Quick Ask from Shortcuts
- Headless execution (no UI required)
- Image JPEG encoding/resizing (max 2048px)
- Pending queue in UserDefaults
- Acceptance: Shortcuts trigger, AI responds, result returns

**FR-17.3 Share Extension**
- Separate target with App Group
- Supports: text, URLs, images, files
- File structure: `<AppGroup>/share_handler/inbox/<eventId>/files/`
- Type-aware routing to AI chat or bookshelf
- TTL-based cleanup
- Acceptance: Share from any app works, routes correctly

**FR-17.4 Deep Links**
- `paperreader://` URL scheme
- Routes: `reader/{bookId}`, `shortcuts/ask`
- SwiftUI `.onOpenURL()` handler
- Acceptance: URLs open correct destinations

**FR-17.5 Background Audio**
- Audio session for TTS
- Background mode: audio
- Now Playing info integration
- Acceptance: TTS continues in background

---

### FR-18: Localization

**FR-18.1 Languages (14)**
- en, zh-Hans, zh-Hant, de, es, fr, it, ja, ko, pt-BR, ro, ru, tr, ar
- Mongolian script support
- Acceptance: Each language displays correctly

**FR-18.2 Implementation**
- Xcode String Catalogs (.xcstrings)
- All UI strings localized
- Dynamic Type support
- RTL support (Arabic)
- Acceptance: All strings translated, RTL layout correct

---

### FR-19: Data Migration (Flutter → Swift)

**FR-19.1 Database Migration**
- Read existing `anx_reader.db` (GRDB reads same SQLite schema)
- Run pending migrations if schema version differs
- Acceptance: Existing data loads in Swift app

**FR-19.2 Book Files**
- Copy EPUB/PDF files from Flutter container
- Alternatively via Files/iCloud backup-restore
- Acceptance: Books accessible after migration

**FR-19.3 Memory Files**
- Copy `memory/` directory (Markdown portable)
- Acceptance: Memory search works on migrated files

**FR-19.4 Settings**
- Import via WebDAV sync or encrypted backup
- API keys require manual re-entry
- Acceptance: Settings restore (except keys)

---

### FR-20: MCP (Model Context Protocol)

**FR-20.1 MCP Client**
- Connect to MCP servers (SSE + Streamable HTTP transports)
- List tools from server
- Call tools and return results
- Acceptance: Connection establishes, tools execute

**FR-20.2 MCP Tool Registry**
- Dynamic tool registration from MCP servers
- Integration with AI tool orchestrator
- Acceptance: MCP tools appear in tool list, execute correctly

---

### FR-21: KAIROS Proactive Assistant

**FR-21.1 Dwell Time Monitoring**
- Monitor reading position and time spent
- Acceptance: Dwell time tracks accurately

**FR-21.2 Proactive Suggestions**
- Surface suggestions based on reading context
- Chapter completion detection
- Level picker in settings
- Acceptance: Suggestions appear at appropriate times

---

### FR-22: Sub-Agent System

**FR-22.1 Sub-Agent Runner**
- Spawn focused agents: research, summarize, verify
- Restricted tool sets per agent type
- Max step limits (1-15)
- Acceptance: Sub-agents complete tasks, return results

---

### FR-23: Skills System

**FR-23.1 Built-in Skills**
- 6 built-in skill templates
- Skill registry
- Acceptance: Skills execute when triggered

**FR-23.2 Skill Settings**
- Skills selector in settings
- Acceptance: Skills enable/disable correctly

---

## 3. Non-Functional Requirements

### NFR-01: Performance
- App launch < 2 seconds
- EPUB page turn < 100ms
- AI streaming first token < 500ms after API response
- Library search < 200ms for 1000 books

### NFR-02: Security
- API keys in Keychain (never UserDefaults)
- WebDAV sync excludes api_key
- Plain backups exclude secrets
- Encrypted backups use AES-256

### NFR-03: Accessibility
- VoiceOver support on all screens
- Dynamic Type support
- Minimum touch target 44pt
- Color contrast ratio ≥ 4.5:1

### NFR-04: Offline Support
- All reading features work offline
- AI chat degrades gracefully (shows error)
- FTS5 search works offline (vector search requires embeddings)

### NFR-05: Data Integrity
- Database transactions for multi-step operations
- Backup validation before restore
- Atomic file replacement for sync

---

## 4. Feature Count Summary

| Category | Count |
|----------|-------|
| Pages/Screens | 47 |
| AI Tools | 46 |
| Service Modules | 217 |
| Riverpod Providers → @Observable ViewModels | 38 |
| Data Models | 44+ |
| DAOs | 7 |
| Enums | 34+ |
| Languages | 14 |
| Supported AI Providers | 6 |
| Translation Providers | 6 |
| TTS Providers | 4 |
