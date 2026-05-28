# Library RAG Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the existing library Hybrid RAG pipeline with reranking, query fusion, parent/neighbor expansion, contextual chunks, local vector indexing, and RAPTOR/GraphRAG global retrieval layers.

**Architecture:** Deliver the work in backward-compatible stages. Stage 1 improves retrieval without changing existing indexes. Later stages add schema and indexing capabilities behind versioned migrations and injectable services so mobile resource use and provider costs stay controlled.

**Tech Stack:** Flutter, Dart, Riverpod, sqflite/SQLite FTS5, local `ai_index.db`, injectable embedding/rerank/context generation functions, `flutter_test`.

---

## Task 1: Retrieval Layer Enhancements

**Files:**
- Modify: `lib/service/rag/semantic_search_library.dart`
- Test: `test/service/rag/semantic_search_library_search_test.dart`

- [x] Write failing tests for reranker override, query fusion recall, and neighbor expansion.
- [x] Add candidate metadata (`chunk_id`, `chunk_index`, `start_char`, `end_char`) to all candidate SQL paths.
- [x] Add an injectable rerank callback and apply it before MMR.
- [x] Add deterministic query variants and merge text-retrieved rows with Reciprocal Rank Fusion by `chunk_id`.
- [x] Expand selected evidence with adjacent chunks in the same book/chapter.
- [x] Run `flutter test --no-pub test/service/rag/semantic_search_library_search_test.dart test/service/ai/tools/semantic_search_library_tool_test.dart -r compact`.

Additional completed integration:
- [x] Add provider-configured HTTP/LLM reranker factory and settings-sync support.
- [x] Verify SiliconFlow-compatible `/rerank` payload shape with tests.

## Task 2: Chunk Structure Schema v6

**Files:**
- Modify: `lib/service/rag/ai_index_schema.dart`
- Modify: `lib/service/rag/ai_index_database.dart`
- Test: `test/service/rag/ai_index_schema_v2_test.dart`

- [x] Write failing migration tests for v5 to v6 and fresh schema.
- [x] Add contextual/TOC metadata columns and `(book_id, chapter_href, chunk_index)` index.
- [x] Keep old `text` readable and avoid forcing immediate rebuild unless index-version metadata requires it.

## Task 3: TOC Preservation And Neighbor Metadata

**Files:**
- Modify: `lib/service/rag/ai_book_indexer.dart`
- Test: `test/service/rag/ai_book_indexer_toc_test.dart`

- [x] Write tests for nested TOC flattening preserving order, level, and path.
- [x] Store chapter order/path metadata when inserting chunks.
- [x] Preserve old behavior when TOC metadata is unavailable.

## Task 4: Contextual Chunking

**Files:**
- Modify: `lib/service/rag/ai_book_indexer.dart`
- Create: `lib/service/rag/ai_contextual_chunker.dart`
- Test: `test/service/rag/ai_contextual_chunker_test.dart`

- [x] Write tests proving embedding input includes context while evidence can still expose readable raw text.
- [x] Add contextualization phase and progress reporting.
- [x] Persist context metadata and include context settings through `indexAlgorithmVersion`.

## Task 5: Vector Search Abstraction

**Files:**
- Create: `lib/service/rag/ai_vector_index.dart`
- Modify: `lib/service/rag/semantic_search_library.dart`
- Test: `test/service/rag/ai_vector_index_test.dart`

- [x] Write tests proving the exact backend matches current cosine ranking.
- [x] Route vector fallback through the abstraction.
- [x] Add binary-vector storage behind a compatibility fallback to JSON vectors.

## Task 6: RAPTOR Global Layer

**Files:**
- Create: `lib/service/rag/ai_raptor_indexer.dart`
- Modify: `lib/service/rag/ai_index_schema.dart`
- Modify: `lib/service/rag/semantic_search_library.dart`
- Test: `test/service/rag/ai_raptor_indexer_test.dart`

- [x] Add schema for summary nodes and chunk links.
- [x] Build deterministic fake-summary tests before model integration.
- [x] Fuse summary-node retrieval with chunk retrieval while preserving evidence provenance.

## Task 7: GraphRAG Layer

**Files:**
- Create: `lib/service/rag/ai_graph_indexer.dart`
- Modify: `lib/service/rag/ai_index_schema.dart`
- Modify: `lib/service/rag/semantic_search_library.dart`
- Test: `test/service/rag/ai_graph_indexer_test.dart`

- [x] Add graph node/edge/community schema.
- [x] Add deterministic extractor tests for entity/edge persistence and chunk provenance.
- [x] Add local/global graph search fusion through the global layer.

## Verification

- Run focused tests after every task.
- Run `flutter test --no-pub test/service/rag test/service/ai/tools/semantic_search_library_tool_test.dart -r compact` before claiming the RAG service layer is green.
- Run `git diff --check`.
- Run targeted `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings lib/service/rag test/service/rag lib/service/ai/tools/semantic_search_library_tool.dart`.
