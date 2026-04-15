# Swift Native Closure Wave: Share / AI / Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the highest-leverage user-visible gaps still open on `swift-native` by making Share & Shortcuts settings complete and real, finishing the current Chinese localization misses on audited surfaces, and tightening one AI runtime truthfulness gap where stored settings do not match runtime behavior.

**Architecture:** Keep the existing Swift Native structure intact and close the gaps at the real seams already in the branch: `ShareAndShortcutsSettingsStore` remains the single source of truth for share settings, `Localizable.xcstrings` remains the only string source, and `StoredAIProviderCatalog` remains the runtime bridge from persisted provider settings into chat providers. This wave avoids speculative refactors and instead lands behavior where users already interact with the product.

**Tech Stack:** SwiftUI, XCTest/Swift Testing via Xcode test schemes, `Localizable.xcstrings`, PTFeatures/PTAIServices/PTCore shared packages.

---

### Task 1: Lock the current red localization baseline

**Files:**
- Modify: `Tests/AppTests/Platform/MigrationLocalizationCatalogTests.swift`
- Test: `PaperTokReader.xcodeproj` app test scheme

- [ ] **Step 1: Run the existing localization audit tests and capture the current red failure**

Run:

```bash
xcodebuild test -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,id=C441A2F8-4AF7-4412-815D-C1CEEF25BB75' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:PaperTokReaderTests/MigrationLocalizationCatalogTests -only-testing:PaperTokReaderTests/HardcodedEnglishAuditTests -only-testing:PaperTokReaderTests/UserFacingLocalizationMappingTests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

Expected: `MigrationLocalizationCatalogTests` fails on missing `Share & Shortcuts` catalog coverage while the hardcoded-English audit stays green.

- [ ] **Step 2: Keep the audit file list as the source of truth**

Do not weaken audit coverage. Only expand catalog entries and code until this exact suite turns green.

### Task 2: Finish Share & Shortcuts settings closure

**Files:**
- Modify: `App/ContentView.swift`
- Modify: `App/Platform/Share/SharedInbox.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Test: `Tests/AppTests/Platform/ShareAndShortcutsSettingsTests.swift`
- Test: `Tests/AppTests/Platform/ShareAndShortcutsSnapshotTests.swift`
- Test: `Tests/AppTests/Platform/SharedInboxTests.swift`

- [ ] **Step 1: Add a failing test for settings round-trip completeness if current tests do not cover TTL and cleanup**

Example assertion shape:

```swift
let store = ShareAndShortcutsSettingsStore(defaults: defaults)
store.save(.init(defaultRoute: .ask, ttlDays: 30, cleanupAfterUse: false))
let restored = store.load()
#expect(restored.ttlDays == 30)
#expect(restored.cleanupAfterUse == false)
```

- [ ] **Step 2: Run only the Share & Shortcuts tests to confirm the new assertion is red if coverage was missing**

Run:

```bash
xcodebuild test -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,id=C441A2F8-4AF7-4412-815D-C1CEEF25BB75' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:PaperTokReaderTests/ShareAndShortcutsSettingsTests -only-testing:PaperTokReaderTests/ShareAndShortcutsSnapshotTests -only-testing:PaperTokReaderTests/SharedInboxTests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

- [ ] **Step 3: Wire `ShareShortcutsSettingsView` to `ShareAndShortcutsSettingsStore`**

Implementation target:

```swift
@State private var settings = ShareAndShortcutsSettingsStore().load()
```

Then:
- persist `defaultRoute`
- expose `ttlDays`
- expose `cleanupAfterUse`
- reload diagnostics through the stored settings source

- [ ] **Step 4: Add the missing localized `Share & Shortcuts` keys to `Localizable.xcstrings`**

Required keys:

```text
settings.share_shortcuts
share.settings.default_route
share.settings.default_route.footer
share.settings.route.auto
share.settings.route.ask
share.settings.diagnostics.pending_events
share.settings.diagnostics.retention
share.settings.diagnostics.latest_event
share.settings.diagnostics.no_events
share.settings.diagnostics.event_summary_format
share.settings.cleanup_expired
share.settings.cleanup_result_format
```

- [ ] **Step 5: Re-run the Share & Shortcuts tests and the localization audit**

Expected: Share tests green, catalog audit no longer fails on the settings-share key set.

### Task 3: Finish the audited Chinese-localization misses on user-visible text

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/TranslationPopupView.swift`
- Modify: `Packages/PTFeatures/Sources/PTFeatures/Reader/ContextMenu/TranslationMenuSheet.swift`
- Modify: `Packages/PTAIServices/Sources/PTAIServices/Memory/MemoryContextBuilder.swift`
- Modify: `App/Platform/Intents/CreateNoteIntent.swift`
- Modify: `App/Resources/Localizable.xcstrings`
- Test: `Packages/PTAIServices/Tests/PTAIServicesTests/Memory/MemoryContextBuilderTests.swift`
- Test: `Tests/AppTests/Platform/MigrationLocalizationCatalogTests.swift`
- Test: `Tests/AppTests/Platform/HardcodedEnglishAuditTests.swift`

- [ ] **Step 1: Add or extend a failing memory-context test for localized truncation**

Example assertion shape:

```swift
#expect(context.contains("…（已截断）"))
```

for `zh-Hans`, or the matching localized fallback chosen by the implementation.

- [ ] **Step 2: Run the focused memory test to confirm red**

Run:

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter MemoryContextBuilderTests
```

- [ ] **Step 3: Replace remaining hardcoded English fallbacks with locale-aware output**

Implementation targets:
- translation language option display names should prefer `Locale` localized names and only fall back to English identifiers when unavoidable
- the memory truncation suffix must be localized
- Create Note intent parameter titles must exist in the catalog

- [ ] **Step 4: Add the missing Create Note parameter keys to `Localizable.xcstrings`**

Required keys:

```text
intent.create_note.parameter.book_title
intent.create_note.parameter.note_text
intent.create_note.parameter.color
```

- [ ] **Step 5: Re-run localization + memory tests**

Expected: the localization audit remains green and the memory test reflects the new localized truncation behavior.

### Task 4: Make Gemini persisted thinking settings truthful at runtime

**Files:**
- Modify: `Packages/PTFeatures/Sources/PTFeatures/AIChat/StoredAIProviderCatalog.swift`
- Modify: `Packages/PTAIServices/Tests/PTAIServicesTests/GeminiProviderTests.swift`
- Modify: `Packages/PTFeatures/Tests/PTFeaturesTests/AIChat/StoredAIProviderCatalogTests.swift`

- [ ] **Step 1: Add a failing test proving unset Gemini include-thoughts does not silently default to enabled**

Example direction:

```swift
#expect(config.includeThoughts == false)
```

or an equivalent assertion through the resolved provider/runtime seam.

- [ ] **Step 2: Run the targeted Gemini/provider-catalog tests and confirm red**

Run:

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter GeminiProviderTests
xcodebuild test -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,id=C441A2F8-4AF7-4412-815D-C1CEEF25BB75' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:PTFeaturesTests/StoredAIProviderCatalogTests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

- [ ] **Step 3: Change the catalog default so runtime behavior matches the unset UI state**

Implementation target:

```swift
guard defaults.object(forKey: key) != nil else { return false }
```

for Gemini `includeThoughts`.

- [ ] **Step 4: Re-run the targeted AI tests**

Expected: Gemini/provider catalog tests green with no regression to capability-scoping behavior.

### Task 5: Run the full verification slice for this wave

**Files:**
- No code changes
- Test: app + package schemes listed below

- [ ] **Step 1: Run the focused package and app verification matrix**

Run:

```bash
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter MemoryContextBuilderTests
swift test --package-path /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/Packages/PTAIServices --filter GeminiProviderTests
xcodebuild test -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj -scheme PTFeaturesPackageTests -destination 'platform=iOS Simulator,id=C441A2F8-4AF7-4412-815D-C1CEEF25BB75' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:PTFeaturesTests/StoredAIProviderCatalogTests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
xcodebuild test -project /Users/gwaanl/GitHub/papertok-reader/.worktrees/swift-native/PaperTokReader.xcodeproj -scheme PaperTokReaderAppTests -destination 'platform=iOS Simulator,id=C441A2F8-4AF7-4412-815D-C1CEEF25BB75' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -only-testing:PaperTokReaderTests/ShareAndShortcutsSettingsTests -only-testing:PaperTokReaderTests/ShareAndShortcutsSnapshotTests -only-testing:PaperTokReaderTests/SharedInboxTests -only-testing:PaperTokReaderTests/SharedInboxImportProcessorTests -only-testing:PaperTokReaderTests/MigrationLocalizationCatalogTests -only-testing:PaperTokReaderTests/HardcodedEnglishAuditTests -only-testing:PaperTokReaderTests/UserFacingLocalizationMappingTests CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES
```

- [ ] **Step 2: Record any still-open gaps instead of papering over them**

If any verification still fails, report the exact remaining failure and keep the wave scoped to honest green evidence only.
