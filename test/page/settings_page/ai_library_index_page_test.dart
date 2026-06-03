import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertok_reader/config/shared_preference_provider.dart';
import 'package:papertok_reader/l10n/generated/L10n.dart';
import 'package:papertok_reader/models/book.dart';
import 'package:papertok_reader/page/settings_page/ai_library_index_page.dart';
import 'package:papertok_reader/service/ai/tools/repository/books_repository.dart';
import 'package:papertok_reader/service/rag/ai_book_index_readiness.dart';
import 'package:papertok_reader/service/rag/ai_book_indexer.dart';
import 'package:papertok_reader/service/rag/ai_index_database.dart';
import 'package:papertok_reader/service/rag/ai_native_vector_index.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_job.dart';
import 'package:papertok_reader/service/rag/library/ai_library_index_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('book rows show per-book index layer readiness', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(7, 'Thinking with Evidence')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 7,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Thinking with Evidence'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thinking with Evidence'), findsOneWidget);
    expect(find.text('Index layers'), findsOneWidget);
    expect(find.text('Base Missing'), findsOneWidget);
    expect(find.text('ANN Missing'), findsOneWidget);
    expect(find.text('Global Missing'), findsOneWidget);
    expect(find.text('Graph Missing'), findsOneWidget);
  });

  testWidgets('book rows explain available capabilities and next unlock',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(8, 'Actionable Index Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 8,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Actionable Index Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Available now: current-book Q&A, source jumps, semantic search.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Next unlock: build ANN for faster large-book search; build global layer for book map and reading path.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('book readiness is only loaded for visible book rows',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final loadedBookIds = <int>[];
    final books = [
      for (var i = 0; i < 80; i++) BookSearchResult(_book(i + 1, 'Book $i')),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => books,
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async {
              loadedBookIds.add(bookId);
              return AiBookIndexReadiness(
                bookId: bookId,
                baseIndex: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                nativeVector: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                annVector: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                globalLayer: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                graphLayer: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Book 0'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(loadedBookIds, isNotEmpty);
    expect(loadedBookIds.length, lessThan(80));
  });

  testWidgets('book rows distinguish unavailable ANN from failed ANN',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(9, 'Vector Extension Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 9,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.unavailable,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Vector Extension Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('ANN Unavailable'), findsOneWidget);
    expect(find.text('ANN Failed'), findsNothing);
    expect(find.text('Graph Empty'), findsOneWidget);
  });

  testWidgets('expired book row prompts base rebuild before layer upgrades',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(10, 'Expired Provider Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {
              10: AiBookIndexInfo(
                bookId: 10,
                chunkCount: 2,
                providerId: 'old-provider',
                embeddingModel: 'old-embedding-model',
                bookMd5: 'book-md5-10',
                indexVersion: AiBookIndexer.indexAlgorithmVersion,
              ),
            },
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 10,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 2,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
                total: 2,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Expired', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expired', skipOffstage: false));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Expired Provider Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Expired Provider Book'), findsOneWidget);
    expect(
      find.text(
        'Index is out of date for current settings. Rebuild the base index before layer upgrades.',
      ),
      findsOneWidget,
    );
    expect(find.text('Build ANN sidecar'), findsNothing);
    expect(find.text('Build global layer'), findsNothing);
  });

  testWidgets(
      'book row surfaces failed base queue job and blocks layer upgrades',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    const failedJob = AiLibraryIndexJob(
      id: 1,
      bookId: 52,
      status: AiLibraryIndexJobStatus.failed,
      retryCount: 2,
      maxRetries: 2,
      progress: 0.42,
      phase: 'embed',
      doneChapters: 1,
      totalChapters: 3,
      doneChunks: 4,
      totalChunks: 9,
      lastError: 'provider disconnected',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(52, 'Failed Base Queue Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            queueStateForTesting: const AiLibraryIndexQueueState(
              jobs: [failedJob],
            ),
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 52,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 9,
                total: 9,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
                total: 9,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Failed Base Queue Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pump();

    expect(find.text('Failed Base Queue Book'), findsOneWidget);
    expect(
      find.text(
        'Base index job: failed · 42% · embedding · chapters 1/3 · embedded chunks 4/9 · error: provider disconnected',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Base index job failed. Continue the base index before layer upgrades.',
      ),
      findsOneWidget,
    );
    expect(find.text('Build ANN sidecar'), findsNothing);
    expect(find.text('Build global layer'), findsNothing);
    expect(find.byTooltip('Continue indexing'), findsAtLeastNWidgets(1));
  });

  testWidgets('saving index settings refreshes book readiness cache',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var readinessReads = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(11, 'Refreshable Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async {
              readinessReads += 1;
              final state = readinessReads == 1
                  ? AiBookIndexLayerState.missing
                  : AiBookIndexLayerState.ready;
              return AiBookIndexReadiness(
                bookId: 11,
                baseIndex: AiBookIndexLayerReadiness(state: state),
                nativeVector: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                annVector: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                globalLayer: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
                graphLayer: const AiBookIndexLayerReadiness(
                  state: AiBookIndexLayerState.missing,
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Refreshable Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Base Missing'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Indexing settings'),
      -500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Indexing settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Refreshable Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(readinessReads, 2);
    expect(find.text('Base Ready'), findsOneWidget);
  });

  testWidgets('book row builds a missing global layer inline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var builtBookId = 0;
    var globalReady = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(17, 'Global Repair Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => AiBookIndexReadiness(
              bookId: 17,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: globalReady
                    ? AiBookIndexLayerState.ready
                    : AiBookIndexLayerState.missing,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
            ),
            bookGlobalLayerBuilder: (bookId) async {
              builtBookId = bookId;
              globalReady = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Global Repair Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Global Missing'), findsOneWidget);
    expect(find.text('Build global layer'), findsOneWidget);

    await tester.tap(find.text('Build global layer'));
    await tester.pumpAndSettle();

    expect(builtBookId, 17);
    expect(find.text('Global Ready'), findsOneWidget);
    expect(find.text('Build global layer'), findsNothing);
  });

  testWidgets('book row upgrades a missing vector layer inline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var upgradedBookId = 0;
    var vectorReady = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(23, 'Vector Repair Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => AiBookIndexReadiness(
              bookId: 23,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: vectorReady
                    ? AiBookIndexLayerState.ready
                    : AiBookIndexLayerState.missing,
                count: vectorReady ? 2 : 0,
                total: 2,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
            bookNativeVectorBuilder: (bookId) async {
              upgradedBookId = bookId;
              vectorReady = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Vector Repair Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vector Missing'), findsOneWidget);
    expect(find.text('Upgrade vector layer'), findsOneWidget);

    await tester.tap(find.text('Upgrade vector layer'));
    await tester.pumpAndSettle();

    expect(upgradedBookId, 23);
    expect(find.text('Vector Ready'), findsOneWidget);
    expect(find.text('Upgrade vector layer'), findsNothing);
  });

  testWidgets('book row repairs missing base embeddings before vector layers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var repairedBookId = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(27, 'Partial Embedding Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => const AiBookIndexReadiness(
              bookId: 27,
              baseIndex: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 2,
              ),
              nativeVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.failed,
                count: 1,
                total: 2,
                reason:
                    '1/2 chunk embeddings are available. Repair missing embeddings before vector upgrades.',
                requiresBaseEmbeddingRepair: true,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
                reason:
                    'Native vector rows are required before ANN can be built.',
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              graphLayer: AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
            bookBaseEmbeddingRepairer: (bookId) async {
              repairedBookId = bookId;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Partial Embedding Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vector Failed'), findsOneWidget);
    expect(
      find.text(
        '1/2 chunk embeddings are available. Repair missing embeddings before vector upgrades.',
      ),
      findsOneWidget,
    );
    expect(find.text('Repair base embeddings'), findsOneWidget);
    expect(find.text('Upgrade vector layer'), findsNothing);
    expect(find.text('Build ANN sidecar'), findsNothing);

    await tester.tap(find.text('Repair base embeddings'));
    await tester.pumpAndSettle();

    expect(repairedBookId, 27);
  });

  testWidgets('book row builds a missing ANN sidecar inline', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var builtBookId = 0;
    var annReady = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(31, 'ANN Repair Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => AiBookIndexReadiness(
              bookId: 31,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 2,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: annReady
                    ? AiBookIndexLayerState.ready
                    : AiBookIndexLayerState.missing,
                count: annReady ? 2 : 0,
                total: 2,
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
            bookAnnVectorBuilder: (bookId, {onProgress}) async {
              builtBookId = bookId;
              annReady = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ANN Repair Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    expect(find.text('ANN Missing'), findsOneWidget);
    expect(find.text('Build ANN sidecar'), findsOneWidget);

    await tester.tap(find.text('Build ANN sidecar'));
    await tester.pumpAndSettle();

    expect(builtBookId, 31);
    expect(find.text('ANN Ready'), findsOneWidget);
    expect(find.text('Build ANN sidecar'), findsNothing);
  });

  testWidgets('book row shows ANN sidecar progress while building',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    final buildCompleter = Completer<void>();
    var annReady = false;
    var builtBookId = 0;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(32, 'ANN Progress Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => AiBookIndexReadiness(
              bookId: 32,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
                count: 2,
                total: 2,
              ),
              annVector: AiBookIndexLayerReadiness(
                state: annReady
                    ? AiBookIndexLayerState.ready
                    : AiBookIndexLayerState.missing,
                count: annReady ? 2 : 0,
                total: 2,
              ),
              globalLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.empty,
              ),
            ),
            bookAnnVectorBuilder: (
              bookId, {
              void Function(AiVec1VectorIndexBuildProgress progress)?
                  onProgress,
            }) async {
              builtBookId = bookId;
              onProgress?.call(
                const AiVec1VectorIndexBuildProgress(
                  done: 0,
                  total: 2,
                  rowsWritten: 1,
                ),
              );
              await buildCompleter.future;
              annReady = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('ANN Progress Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build ANN sidecar'));
    await tester.pump();

    expect(builtBookId, 32);
    expect(
      find.text('ANN sidecar progress: 0/2 group(s), 1 row(s) written.'),
      findsOneWidget,
    );

    buildCompleter.complete();
    await tester.pumpAndSettle();

    expect(find.text('ANN Ready'), findsOneWidget);
    expect(
      find.text('ANN sidecar progress: 0/2 group(s), 1 row(s) written.'),
      findsNothing,
    );
  });

  testWidgets('book row keeps failed layer action visible for retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await Prefs().initPrefs();

    var attempts = 0;
    var globalReady = false;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: AiLibraryIndexPage(
            bookSearchLoader: ({required int limit}) async => [
              BookSearchResult(_book(41, 'Retryable Global Book')),
            ],
            bookIndexInfoLoader: (bookIds) async => const {},
            bookReadinessLoader: (bookId) async => AiBookIndexReadiness(
              bookId: 41,
              baseIndex: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.ready,
              ),
              nativeVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              annVector: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
              globalLayer: AiBookIndexLayerReadiness(
                state: globalReady
                    ? AiBookIndexLayerState.ready
                    : AiBookIndexLayerState.missing,
              ),
              graphLayer: const AiBookIndexLayerReadiness(
                state: AiBookIndexLayerState.missing,
              ),
            ),
            bookGlobalLayerBuilder: (bookId) async {
              attempts += 1;
              if (attempts == 1) {
                throw StateError('provider disconnected');
              }
              globalReady = true;
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Retryable Global Book'),
      500,
      scrollable: find.byType(Scrollable),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Build global layer'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Global layer build failed'),
        findsAtLeastNWidgets(1));
    expect(
        find.textContaining('provider disconnected'), findsAtLeastNWidgets(1));
    expect(find.text('Retry global layer'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.ensureVisible(find.text('Retry global layer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry global layer'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('Global Ready'), findsOneWidget);
    expect(find.textContaining('Global layer build failed'), findsNothing);
    expect(find.text('Retry global layer'), findsNothing);
  });
}

Book _book(int id, String title) {
  final now = DateTime(2026, 6, 2);
  return Book(
    id: id,
    title: title,
    coverPath: '',
    filePath: '',
    lastReadPosition: '',
    readingPercentage: 0,
    author: 'PaperTok',
    isDeleted: false,
    rating: 0,
    md5: 'book-md5-$id',
    createTime: now,
    updateTime: now,
  );
}
