import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:papertok_reader/models/knowledge_sync.dart';
import 'package:papertok_reader/service/sync/knowledge_asset_export_service.dart';

final knowledgeAssetExportServiceProvider =
    Provider<KnowledgeAssetExportService>((ref) {
  return KnowledgeAssetExportService();
});

final knowledgeAssetExportProvider = StateNotifierProvider<
    KnowledgeAssetExportNotifier, KnowledgeAssetExportState>(
  (ref) => KnowledgeAssetExportNotifier(
    ref.watch(knowledgeAssetExportServiceProvider),
  ),
);

class KnowledgeAssetExportState {
  const KnowledgeAssetExportState({
    required this.snapshot,
    this.busy = false,
    this.lastManifestPath,
    this.lastMarkdownPath,
    this.lastAnkiPath,
    this.lastError,
  });

  factory KnowledgeAssetExportState.initial() {
    return const KnowledgeAssetExportState(
      snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
        KnowledgeAssetExportSnapshot(
          manifest: KnowledgeExportManifest(
            id: '',
            createdAt: 0,
            formats: <KnowledgeExportFormat>[],
          ),
          included: <KnowledgeSyncEnvelope>[],
          excluded: <KnowledgeSyncEnvelope>[],
          excludedReasons: <String, String>{},
        ),
      ),
    );
  }

  final AsyncValue<KnowledgeAssetExportSnapshot> snapshot;
  final bool busy;
  final String? lastManifestPath;
  final String? lastMarkdownPath;
  final String? lastAnkiPath;
  final String? lastError;

  KnowledgeAssetExportState copyWith({
    AsyncValue<KnowledgeAssetExportSnapshot>? snapshot,
    bool? busy,
    String? lastManifestPath,
    String? lastMarkdownPath,
    String? lastAnkiPath,
    String? lastError,
    bool clearError = false,
  }) {
    return KnowledgeAssetExportState(
      snapshot: snapshot ?? this.snapshot,
      busy: busy ?? this.busy,
      lastManifestPath: lastManifestPath ?? this.lastManifestPath,
      lastMarkdownPath: lastMarkdownPath ?? this.lastMarkdownPath,
      lastAnkiPath: lastAnkiPath ?? this.lastAnkiPath,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class KnowledgeAssetExportNotifier
    extends StateNotifier<KnowledgeAssetExportState> {
  KnowledgeAssetExportNotifier(this._service)
      : super(KnowledgeAssetExportState.initial());

  final KnowledgeAssetExportService _service;

  Future<void> refresh() async {
    state = state.copyWith(
      snapshot: const AsyncValue<KnowledgeAssetExportSnapshot>.loading(),
      clearError: true,
    );
    try {
      final snapshot = await _service.buildSnapshot();
      state = state.copyWith(
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(snapshot),
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.error(
          error,
          stackTrace,
        ),
        lastError: error.toString(),
      );
    }
  }

  Future<void> createManifest() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _service.writeManifest();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        lastManifestPath: result.file.path,
        lastMarkdownPath: result.markdownFile?.path,
        lastAnkiPath: result.ankiFile?.path,
        clearError: true,
      );
    } catch (error, stackTrace) {
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.error(
          error,
          stackTrace,
        ),
        lastError: error.toString(),
      );
    }
  }
}
