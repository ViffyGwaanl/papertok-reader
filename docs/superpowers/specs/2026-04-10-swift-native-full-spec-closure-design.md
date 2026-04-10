# Swift-Native Full-Spec Closure Design

**Date:** 2026-04-10  
**Status:** Draft for review  
**Scope:** Complete the `swift-native` branch to full product parity against the approved Swift-native migration contract, with native-grade delivery on iPhone, iPad, and macOS.

---

## 1. Mission

This design defines how to finish the `swift-native` branch without reducing scope to an MVP and without treating release packaging as a substitute for product completion.

The target state is:

- full closure of the approved 2026-04-03 migration requirements and design;
- behavioral parity with the `main` Flutter product where the approved docs are silent or underspecified;
- native-grade delivery for iPhone, iPad, and macOS;
- fresh verification evidence for every parity-critical subsystem;
- release readiness only after feature readiness is honest.

This document is intentionally stricter than the existing branch-local execution notes. If a requirement exists in the approved migration contract but is not fully closed in the branch today, it remains in scope.

---

## 2. Source Of Truth

This effort uses three layers of truth, in priority order.

### 2.1 Final Product Contract

These documents define what "done" means:

- `docs/superpowers/specs/2026-04-03-swift-migration-requirements.md`
- `docs/superpowers/specs/2026-04-03-swift-native-migration-design.md`

These remain the final acceptance contract for functional and non-functional scope.

### 2.2 Current Execution Baseline

These documents define what the branch has already done, what remains open, and what has fresh evidence:

- `docs/superpowers/plans/2026-04-07-swift-native-closure-master-plan.md`
- `docs/superpowers/plans/2026-04-07-swift-native-verification-report.md`
- `docs/superpowers/plans/2026-04-06-progress-tracker.md`

These documents do not reduce scope. They are the realism layer for sequencing and truthful progress tracking.

### 2.3 Behavioral Reference

The `main` branch Flutter product is the behavioral reference for:

- user-visible flows not fully captured in the 2026-04-03 docs;
- interaction details, settings depth, and product surfaces that exist in Flutter but are only loosely described in the migration contract;
- parity checks where a feature can exist in name but still differ materially in behavior.

Rule:

- if the 2026-04-03 contract is explicit, follow it;
- if the contract is silent or ambiguous, use `main` behavior as the parity reference;
- if `main` conflicts with the approved contract, follow the contract and document the difference explicitly.

---

## 3. Completion Contract

The branch may be called "Swift-native complete" only when all conditions below are true.

### 3.1 Platform Completion

- iPhone reaches native-grade completion for all in-scope FRs.
- iPad reaches native-grade completion, including split-view and large-screen behaviors where required.
- macOS reaches native-grade completion through a real standalone macOS target, not only "Designed for iPad/iPhone on Mac" compatibility.

### 3.2 Functional Completion

- FR-01 through FR-23 are either fully implemented or explicitly removed by a newer approved contract document.
- No parity-critical gap remains in Papers, Bookshelf, Reader, AI, Platform Integration, Migration, Settings, Sync/Backup, TTS, KAIROS, MCP, Sub-Agent, or Skills.

### 3.3 Non-Functional Completion

- NFR-01 Performance has credible evidence on parity-critical surfaces.
- NFR-02 Security is satisfied for secrets, app groups, migrations, and sync-sensitive paths.
- NFR-03 Accessibility is verified on major user paths.
- NFR-04 Offline support is verified for the expected local-reading and local-data surfaces.
- NFR-05 Data integrity is verified for migrations, imports, note persistence, reading progress, and sync-sensitive flows.

### 3.4 Evidence Completion

- Fresh automated verification exists for implemented parity-critical surfaces.
- Fresh walkthrough verification exists for end-user paths that cannot be defended by tests alone.
- Release/TestFlight/archive success exists, or the only remaining blockers are clearly documented external Apple-side issues.

### 3.5 Documentation Completion

- Progress docs no longer rely on stale optimistic claims.
- Remaining open risks, if any, are release-level or external, not hidden product-level gaps.

---

## 4. Current Reality And Design Implications

The current branch has substantial implementation, but the following realities shape the closure strategy.

### 4.1 The Branch Is In Late-Stage Closure, Not Early Migration

The branch already contains:

- a native Swift/Xcode package structure;
- meaningful Papers, Bookshelf, Reader, AI, Platform, Migration, Notes, and Statistics work;
- branch-local verification for selected surfaces;
- a wave-based closure document that is more truthful than the older phase-only framing.

Implication:

- do not restart from the original phase plans;
- do not discard branch-local work that already closes real gaps;
- do reconcile all existing work against the stricter completion contract above.

### 4.2 The App Layer Is Too Centralized For Safe Parallelism

Key files are currently too large or too overloaded for aggressive parallel editing:

- `App/ContentView.swift`
- reader host files in `PTFeatures/Reader`
- app-level routing, AI context, and platform wiring

Implication:

- the first execution wave must reduce structural coupling before large-scale parallel implementation begins.

### 4.3 macOS Is Not Yet A First-Class Product Target

The branch currently has macOS-oriented deployment settings and command code, but lacks a true standalone macOS app target in the active project definition.

Implication:

- macOS target creation and platform-host architecture are not optional follow-up work;
- they must be lifted into an early foundation wave.

### 4.4 Fresh Verification Must Replace Borrowed Confidence

The branch contains useful verification history, but completion claims cannot continue to rely on evidence from earlier dates when code has moved since then.

Implication:

- every wave must produce new evidence on the current branch state.

---

## 5. Wave Architecture

The closure effort is executed in seven waves. These waves replace the older "phase equals current status" mental model while still reusing the useful work already landed in the branch.

### Wave A: Contract And Platform Foundation

Purpose:

- unify truth sources;
- establish the spec-to-main-to-swift gap matrix;
- create the standalone macOS target and platform build matrix;
- split high-conflict app host files into parallel-safe boundaries.

Primary outcomes:

- authoritative gap matrix;
- standalone macOS app target, entitlements, scheme, and verification path;
- app-shell and platform-host boundaries that support parallel execution;
- reduced hotspot pressure in `App/ContentView.swift`.

### Wave B: Navigation, Bookshelf, Papers, And Directory Scanning

Purpose:

- complete FR-01, FR-02, FR-03, and related localization/platform parity on user-visible library and discovery flows.

Primary outcomes:

- native navigation parity across iPhone, iPad, and macOS;
- Bookshelf complete for sort/filter/tag/group/context/edit/import flows;
- full dual-mode import parity, including directory scanning, bookmarks, monitoring, and recovery;
- Papers feed/detail/download/import parity.

### Wave C: Reader Full Parity

Purpose:

- complete EPUB and PDF parity across Reader, AI panel, annotations, settings, image handling, reading-time persistence, and TTS product surfaces.

Primary outcomes:

- EPUB and PDF parity for navigation, search, TOC, annotations, settings, progress, image workflows, and AI access;
- reader AI panel parity on all three platforms;
- TTS parity as a product feature, not only a service abstraction;
- verified reader behavior on iPhone, iPad, and macOS.

### Wave D: AI Product System

Purpose:

- turn the partially complete AI runtime into a fully productized system.

Primary outcomes:

- provider center parity;
- attachments, history, branching, approval, thinking, and usage UX parity;
- end-user operational RAG, memory, translation, MCP, sub-agent, and skills surfaces;
- runtime honesty preserved while productizing the UI and workflows.

### Wave E: Platform Integration, Migration, And Localization

Purpose:

- complete system-level behavior across share, deep links, intents, migration, localization, app groups, and extension boundaries.

Primary outcomes:

- end-to-end platform flow parity;
- verified Flutter-to-Swift migration completeness for database, settings, and files;
- localization coverage verification on touched flows;
- clean platform behavior on all three targets.

### Wave F: Settings, Sync/Backup, TTS Deep Settings, And KAIROS

Purpose:

- finish the deep configuration and proactive-system surfaces that remain under-productized.

Primary outcomes:

- settings depth parity;
- sync/backup restore and recovery parity;
- KAIROS or proactive-assistant parity;
- complete settings exposure for AI, Reader, Platform, and Sync systems.

### Wave G: Full Verification And Release Closure

Purpose:

- prove honest readiness only after Waves A-F are closed.

Primary outcomes:

- full three-platform verification matrix;
- documented walkthrough coverage;
- release/archive/TestFlight readiness evidence;
- no remaining hidden product-completion claims behind release packaging.

---

## 6. Gap Matrix Model

The central operating artifact for this closure effort is the spec-to-main-to-swift gap matrix.

Each FR or parity-critical subfeature must be represented with the following columns:

- FR / sub-requirement ID
- spec requirement summary
- `main` Flutter behavior reference
- current `swift-native` implementation state
- gap classification:
  - `missing`
  - `partial`
  - `implemented but unverified`
  - `implemented but behavior-divergent`
  - `complete`
- target wave
- primary owning files/modules
- automated verification target
- walkthrough verification path
- platform notes for iPhone / iPad / macOS

Rules:

- no work is considered complete until the matrix row reaches `complete`;
- no row may be upgraded to `complete` without current evidence;
- the matrix must explicitly call out divergences from `main` when they are intentional.

---

## 7. Code Boundary Plan

The branch needs targeted structural cleanup in support of closure, not broad unrelated refactoring.

### 7.1 App Layer Boundaries

The app layer should be split into focused responsibilities:

- `AppShell`
  - app lifecycle
  - root scene composition
  - global environment assembly
- `Platform`
  - deep links
  - share
  - migration
  - EventKit
  - App Intents
  - app groups
  - macOS command wiring
- `Feature Hosting`
  - host and route `PTFeatures` views
  - maintain cross-feature navigation state
- `Platform Presentation`
  - migration-specific or permission-specific app UI
  - platform-dependent presentation wrappers

### 7.2 PTFeatures Boundaries

`PTFeatures` remains the feature composition layer, but with stricter feature isolation:

- `Navigation`
- `Bookshelf`
- `Papers`
- `Reader`
- `AIChat`
- `Settings`
- `Notes`
- `Statistics`

Reader should continue to be broken down into:

- reader host/presentation
- EPUB surfaces
- PDF surfaces
- annotations
- preferences
- AI panel
- image experience
- TTS product surfaces

### 7.3 PTReader Boundaries

`PTReader` remains the lower-level reading engine layer:

- Readium integration
- PDFKit/Vision extraction and OCR
- content bridges
- publication opening
- annotation bridges
- TTS service abstractions

Reader UI state and user flows belong in `PTFeatures`, not in `PTReader`.

### 7.4 macOS Product Boundary

A standalone macOS product target must be introduced with:

- dedicated target configuration;
- dedicated entitlements where needed;
- dedicated scheme/build path;
- platform-specific app-shell hosting;
- verified macOS-native navigation and commands;
- macOS-appropriate file import and reader presentation.

This is a required completion boundary, not an optional enhancement.

---

## 8. Verification System

Verification is a first-class design concern, not a postscript.

### 8.1 Four Verification Layers

Every parity-critical task must pass through four layers.

#### Layer 1: Contract Verification

Confirm the task closes the intended FR rows in the gap matrix.

#### Layer 2: Automated Verification

Use the best fitting automated surface:

- SwiftPM package tests
- app target tests
- package-test schemes
- platform-specific targeted test runs
- migration fixture tests
- share/deep-link/intents regression suites
- macOS build/tests once the target exists

#### Layer 3: Behavioral Verification Against `main`

Validate that user-visible behavior matches or exceeds `main` when the contract is underspecified.

#### Layer 4: Walkthrough Verification

Validate real user paths that cannot be fully defended by lower-level tests.

Examples:

- first launch and onboarding
- importing EPUB/PDF
- Bookshelf organization and undo
- reader annotation/search/preferences flows
- AI chat with provider switching and attachments
- share extension to in-app landing behavior
- Flutter migration flows
- directory scanning setup and failure recovery
- macOS menu/command/file import paths

### 8.2 Fresh Evidence Rule

Completion claims must be backed by current evidence from the present branch state.

Every verification record should capture:

- date;
- command or walkthrough reference;
- target or scheme;
- platform/device where relevant;
- pass/fail outcome;
- matrix rows closed.

Old evidence may guide prioritization but cannot substitute for fresh closure evidence after meaningful code movement.

---

## 9. Execution Policy

This closure effort will be executed with subagent-driven development, but under strict controller-managed boundaries.

### 9.1 Controller Model

The controller is responsible for:

- maintaining the gap matrix and wave sequencing;
- deciding when work is parallel-safe;
- constructing task prompts with exact scope and file ownership;
- running review loops and integration;
- updating truth-bearing docs.

### 9.2 Agent Roles

- `Explorer agents`
  - read-only analysis of `main`, `swift-native`, tests, or docs
- `Worker implementers`
  - bounded implementation ownership with explicit write sets
- `Spec reviewers`
  - verify closure against contract and `main` parity expectations
- `Code-quality reviewers`
  - verify maintainability, test quality, and platform fit after spec approval

### 9.3 Mandatory Review Order

For each implementation task:

1. implementer completes task and self-reviews;
2. spec reviewer checks contract/main parity;
3. implementer fixes spec gaps if any;
4. code-quality reviewer checks build quality;
5. implementer fixes quality gaps if any;
6. task closes only after both reviews approve.

### 9.4 Parallelism Rules

Parallel work is allowed only when write sets are disjoint.

Typically parallel-safe:

- doc and matrix analysis
- different packages with no shared host files
- separate feature modules after host boundaries are reduced
- macOS target scaffolding vs isolated feature work

Not parallel-safe until boundaries are fixed:

- multiple large edits to `App/ContentView.swift`
- simultaneous edits to `project.yml`
- simultaneous app-root dependency injection rewrites
- multiple worker tasks touching the same reader host file

### 9.5 Documentation Policy

Each wave must leave behind:

- updated progress status;
- updated verification evidence;
- explicit remaining risks;
- no stale optimistic wording.

---

## 10. Risk Register

### 10.1 macOS Target Risk

Risk:

- the current project shape does not yet satisfy true macOS-native delivery.

Response:

- bring macOS target creation into Wave A, not the end of the project.

### 10.2 Hot-File Concurrency Risk

Risk:

- large shared host files make parallel implementation unstable.

Response:

- reduce host-file coupling before aggressive multi-agent execution.

### 10.3 Reader Parity Risk

Risk:

- Reader is the most likely place for "partially impressive but not truly closed" functionality.

Response:

- dedicate an entire wave to reader closure with stronger walkthrough expectations.

### 10.4 Migration Integrity Risk

Risk:

- migration can appear correct at schema level while still losing user assets or settings.

Response:

- require fixture-backed and walkthrough-backed validation of DB, files, and settings.

### 10.5 AI Productization Risk

Risk:

- strong internal runtime can mask missing user-facing AI product behavior.

Response:

- every AI capability must close runtime, UI, workflow, and settings parity together.

### 10.6 Directory Scanning Risk

Risk:

- security-scoped bookmarks and monitoring flows are easy to underbuild and costly to repair later.

Response:

- keep directory scanning as an explicit subsystem, not a casual import subtask.

### 10.7 Truth Drift Risk

Risk:

- older phase docs and newer wave docs can cause inconsistent decisions.

Response:

- this design plus the upcoming gap matrix become the active narrative for closure work.

---

## 11. Definition Of A Closed Wave

A wave is closed only when all of the following are true:

- all assigned matrix rows are marked `complete`;
- no parity-critical known gap remains in that wave;
- automated verification is fresh on the current branch state;
- walkthrough verification is documented for the wave's user paths;
- the progress and verification docs are updated truthfully.

If any of the above are missing, the wave remains open.

---

## 12. Planning Handoff

The next document after this design is an implementation master plan that will:

- instantiate the gap matrix structure;
- map all open work to Waves A-G;
- define exact file ownership and verification commands per task;
- prioritize structural tasks that unlock safe multi-agent execution;
- use subagent-driven development as the default execution mode.

That plan should assume:

- no MVP shortcuts;
- no release-first shortcuts;
- no platform downgrades;
- no unverified completion claims.

