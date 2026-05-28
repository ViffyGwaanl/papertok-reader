# Design: Library RAG Optimization Roadmap

> Date: 2026-05-28
> Status: in progress
> Scope: PaperTok Reader library RAG, from current Hybrid RAG toward rerank, contextual chunks, expansion, local vector index, query fusion, RAPTOR, and GraphRAG.

## Current State

The current library RAG stack is a working Hybrid RAG pipeline:

- `ai_index.db` stores `ai_book_index`, `ai_chunks`, optional `ai_chunks_fts`, and persistent indexing jobs.
- `AiBookIndexer` extracts TOC chapters, chunks chapter text, embeds chunks, and stores text plus JSON embeddings.
- `SemanticSearchLibrary` searches across the library with FTS5/BM25 candidates, LIKE fallback, small vector fallback, cosine similarity, hybrid scoring, MMR, and `paperreader://reader/open?...` jump links.

The missing layers are reranking, query fusion, richer chunk context, parent/neighbor expansion, ANN/local vector indexing, and global retrieval over summaries or graph structures.

## Design Principles

- Keep `ai_index.db` independently rebuildable and local-only by default.
- Add retrieval improvements before heavy indexing changes, so current indexes keep working.
- Keep every new layer optional or backward compatible until its index data exists.
- Prefer deterministic local behavior in tests; use injectable model-powered services for network-dependent layers.
- Use schema versions to mark rebuild boundaries when chunk text, context text, vector storage, or global summaries change.

## Stage 1: Retrieval Layer

This stage changes `SemanticSearchLibrary` only enough to support:

- **Reranker hook:** add an injectable rerank function that receives top hybrid candidates and can adjust final relevance before MMR. The first implementation is a provider-neutral extension point; later stages can plug in Cohere, CrossEncoder, or LLM-based rerank.
- **Query fusion:** run multiple query variants through text retrieval and merge candidates by `chunk_id` with Reciprocal Rank Fusion. The default variants are conservative, deterministic variants derived from the query itself.
- **Parent/neighbor expansion:** after selecting hits, fetch adjacent chunks within the same `book_id + chapter_href` and merge them into the evidence snippet while keeping the jump link anchored to the matched chunk.

No schema migration is required for Stage 1, though the SQL selects must include `chunk_index`, `start_char`, and `end_char`.

## Stage 2: Chunk Structure Schema

Add `ai_index.db` v6 fields and indexes:

- `ai_chunks.raw_text`
- `ai_chunks.context_text`
- `ai_chunks.embedding_input_hash`
- `ai_chunks.context_model`
- `ai_chunks.context_version`
- `ai_chunks.context_created_at`
- `ai_chunks.chapter_order`
- `ai_chunks.toc_level`
- `ai_chunks.toc_path`
- index `(book_id, chapter_href, chunk_index)`

Existing `text` remains readable for old indexes and can initially hold the embedding input.

## Stage 3: Contextual Chunk

Add an optional contextualizer between chunking and embedding:

- Input: book title, chapter title, neighboring heading path, raw chunk text, short chapter/book context.
- Output: short context string prepended or combined for embedding and BM25.
- Persist context metadata and include context settings in index expiration.
- Add progress phases for contextualization.

## Stage 4: Local Vector Index

Introduce a vector-search abstraction:

- Exact backend mirrors today's behavior but reads from a vector repository interface.
- Add binary vector storage so JSON parsing is no longer the long-term hot path.
- Add ANN backend behind the same interface after platform packaging is proven. Candidates include SQLite Vec1/sqlite-vec or a native HNSW/FAISS bridge.

The production default should remain exact/local until the native extension is stable across iOS, Android, macOS, and Windows.

## Stage 5: RAPTOR Global Layer

Add hierarchical summaries:

- `ai_raptor_nodes`: book/library summary nodes with level, parent, summary text, embedding, cluster id, child count.
- `ai_raptor_node_chunks`: links between summary nodes and leaf chunks.
- Query path retrieves both leaf chunks and summary nodes, then fuses results.

Start with book-level trees, then add library-level clusters.

## Stage 6: GraphRAG Global Layer

Add graph retrieval after RAPTOR:

- `ai_graph_nodes`: entities/concepts with canonical names, types, summaries, embeddings.
- `ai_graph_edges`: typed weighted relations.
- `ai_graph_node_chunks`: evidence links back to chunks.
- `ai_graph_communities`: community summaries for global questions.

Use GraphRAG local/global search ideas, but keep graph extraction asynchronous and opt-in because it is model-costly.

## Validation

- Stage 1 tests: rerank changes order, query fusion finds candidates missed by the original query, neighbor expansion merges adjacent chunks without crossing chapter/book boundaries.
- Stage 2 tests: v5 to v6 migration and fresh schema include fields/indexes.
- Stage 3 tests: fake contextualizer changes embedding input and expiration metadata.
- Stage 4 tests: exact vector backend returns current-compatible ranking; ANN backend tests run only when available.
- Stage 5/6 tests: deterministic fake summarizer/extractor prove table writes, retrieval fusion, and evidence provenance.
