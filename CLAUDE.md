# PaperTok Reader — Project Context

## What is this

Cross-platform Flutter e-book reader (iOS/iPadOS-first) built on [Anx Reader](https://github.com/Anxcye/anx-reader) (MIT). Focus: PaperTok feed, AI chat with Provider Center, semantic search, memory system, in-reader translation.

## Tech stack

- **Flutter 3.24+**, Dart ≥3.5.2, Android compileSdk 36, macOS deployment target 11.0
- **State**: Riverpod (codegen via `riverpod_generator`) + legacy `provider` for `Prefs`
- **DB**: sqflite schema v8 (`lib/dao/database.dart`), separate AI index DB (`lib/service/rag/ai_index_database.dart`), memory index DB
- **Codegen**: freezed, json_serializable, riverpod_generator, flutter_gen
- **AI**: LangChain (`langchain_anthropic`, `langchain_google`, `langchain_openai`) with 50+ tools, skills, sub-agent system
- **RAG**: Embeddings → vector index → hybrid retrieval (FTS + vector + MMR)
- **L10n**: `flutter gen-l10n`, ARB files in `lib/l10n/`

## Architecture

```
lib/
  main.dart              — App entry, ProviderScope, routing
  config/                — SharedPreference provider
  enums/                 — 40+ enum definitions
  models/                — freezed + json_serializable data models
  dao/                   — Raw SQL on sqflite (no ORM)
  providers/             — 70 Riverpod providers (.g.dart codegen)
  service/
    ai/                  — LLM, tools, skills, sub-agents, LangChain
    rag/                 — Embeddings, chunking, vector search
    memory/              — Memory capture, storage, indexing
    mcp/                 — MCP client protocol
    papertok/            — Papertok API client
    book_player/         — EPUB reader engine (WebView + foliate-js)
    sync/                — WebDAV sync
    tts/                 — Text-to-speech
    translate/           — Translation pipeline
  page/                  — UI pages (home, book_player, memory, papers, search, settings)
  widgets/               — Reusable UI components
  theme/                 — Claude/Papertok design system (terracotta palette)
  l10n/                  — Generated localization
```

## Key patterns

- Every AI chat tab runs in its own `ProviderScope` override for full isolation
- Reading page AI panel uses `AnimatedSlide` overlay (not `showBottomSheet`) so widget tree persists across open/close
- EPUB rendering via foliate-js in WebView; CSS injected by `getCSS()` in `book.js`
- Search: text normalization (zero-width, full-width punctuation) + semantic RAG parallel search
- Build numbers are monotonically incremented in `pubspec.yaml`

## Build & release

```bash
flutter pub get
flutter gen-l10n
# codegen when providers/models change:
dart run build_runner build --delete-conflicting-outputs

# platforms
flutter build apk --release        # Android
flutter build macos --release      # macOS
flutter build ipa --release        # iOS (then xcodebuild export + altool upload)
```

- Android signing: `android/key.properties` (gitignored)
- iOS: export with `build/ios/ipa/ExportOptions.plist`, upload via `xcrun altool --apiKey 3RJ9SJ4AN5`
- TF issuer: `b675f073-cecc-4ada-8837-3085a7ce7091`
- Pub mirror needed in CN: `PUB_HOSTED_URL=https://pub.flutter-io.cn`

## Conventions

- L10n: all user-facing strings in ARB files (`lib/l10n/app_en.arb`, `app_zh.arb`), generated via `flutter gen-l10n`
- Settings sub-pages use `SettingsSubpageScaffold` for consistent back button
- Import `pointer_interceptor` for widgets above WebView
- No emojis in code unless explicitly requested
- Respond in Chinese for user-facing communication

## Documentation

- Docs index: `docs/README.md`
- AI docs hub: `docs/ai/README.md`
- Engineering docs: `docs/engineering/`
- Release SOP: `docs/SOP_RELEASE_AUTOMATION_zh.md`
