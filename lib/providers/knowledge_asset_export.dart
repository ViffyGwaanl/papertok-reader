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

enum KnowledgeRemoteSyncStatus {
  notPreviewed,
  reviewRequired,
  readyToUpload,
  uploaded,
  failed,
}

class KnowledgeAssetExportState {
  const KnowledgeAssetExportState({
    required this.snapshot,
    this.busy = false,
    this.lastManifestPath,
    this.lastMarkdownPath,
    this.lastHtmlReportPath,
    this.lastAnkiPath,
    this.lastSyncBundlePath,
    this.lastConflictReviewCount,
    this.lastRemoteConflictReviewCount,
    this.lastRemoteConflictStageCount,
    this.lastRemoteConflictStageSkippedCount,
    this.lastRemoteIncomingReviewCount,
    this.lastRemoteIncomingSkippedCount,
    this.lastRemoteReviewHistoryReviewCount,
    this.lastRemoteReviewHistorySkippedCount,
    this.lastRemoteUploadPath,
    this.lastRemoteUploadCount,
    this.remotePreview,
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
  final String? lastHtmlReportPath;
  final String? lastAnkiPath;
  final String? lastSyncBundlePath;
  final int? lastConflictReviewCount;
  final int? lastRemoteConflictReviewCount;
  final int? lastRemoteConflictStageCount;
  final int? lastRemoteConflictStageSkippedCount;
  final int? lastRemoteIncomingReviewCount;
  final int? lastRemoteIncomingSkippedCount;
  final int? lastRemoteReviewHistoryReviewCount;
  final int? lastRemoteReviewHistorySkippedCount;
  final String? lastRemoteUploadPath;
  final int? lastRemoteUploadCount;
  final KnowledgeRemoteSyncPreview? remotePreview;
  final String? lastError;

  KnowledgeRemoteSyncStatus get remoteSyncStatus {
    if (lastError != null) {
      return KnowledgeRemoteSyncStatus.failed;
    }
    if (lastRemoteUploadPath != null) {
      return KnowledgeRemoteSyncStatus.uploaded;
    }
    final preview = remotePreview;
    if (preview == null) {
      return KnowledgeRemoteSyncStatus.notPreviewed;
    }
    if (preview.incomingCount > 0 || preview.conflictCount > 0) {
      return KnowledgeRemoteSyncStatus.reviewRequired;
    }
    return KnowledgeRemoteSyncStatus.readyToUpload;
  }

  KnowledgeAssetExportState copyWith({
    AsyncValue<KnowledgeAssetExportSnapshot>? snapshot,
    bool? busy,
    String? lastManifestPath,
    String? lastMarkdownPath,
    String? lastHtmlReportPath,
    String? lastAnkiPath,
    String? lastSyncBundlePath,
    int? lastConflictReviewCount,
    int? lastRemoteConflictReviewCount,
    int? lastRemoteConflictStageCount,
    int? lastRemoteConflictStageSkippedCount,
    int? lastRemoteIncomingReviewCount,
    int? lastRemoteIncomingSkippedCount,
    int? lastRemoteReviewHistoryReviewCount,
    int? lastRemoteReviewHistorySkippedCount,
    String? lastRemoteUploadPath,
    int? lastRemoteUploadCount,
    KnowledgeRemoteSyncPreview? remotePreview,
    String? lastError,
    bool clearError = false,
    bool clearRemotePreview = false,
    bool clearRemoteUpload = false,
  }) {
    return KnowledgeAssetExportState(
      snapshot: snapshot ?? this.snapshot,
      busy: busy ?? this.busy,
      lastManifestPath: lastManifestPath ?? this.lastManifestPath,
      lastMarkdownPath: lastMarkdownPath ?? this.lastMarkdownPath,
      lastHtmlReportPath: lastHtmlReportPath ?? this.lastHtmlReportPath,
      lastAnkiPath: lastAnkiPath ?? this.lastAnkiPath,
      lastSyncBundlePath: lastSyncBundlePath ?? this.lastSyncBundlePath,
      lastConflictReviewCount:
          lastConflictReviewCount ?? this.lastConflictReviewCount,
      lastRemoteConflictReviewCount:
          lastRemoteConflictReviewCount ?? this.lastRemoteConflictReviewCount,
      lastRemoteConflictStageCount:
          lastRemoteConflictStageCount ?? this.lastRemoteConflictStageCount,
      lastRemoteConflictStageSkippedCount:
          lastRemoteConflictStageSkippedCount ??
              this.lastRemoteConflictStageSkippedCount,
      lastRemoteIncomingReviewCount:
          lastRemoteIncomingReviewCount ?? this.lastRemoteIncomingReviewCount,
      lastRemoteIncomingSkippedCount:
          lastRemoteIncomingSkippedCount ?? this.lastRemoteIncomingSkippedCount,
      lastRemoteReviewHistoryReviewCount: lastRemoteReviewHistoryReviewCount ??
          this.lastRemoteReviewHistoryReviewCount,
      lastRemoteReviewHistorySkippedCount:
          lastRemoteReviewHistorySkippedCount ??
              this.lastRemoteReviewHistorySkippedCount,
      lastRemoteUploadPath: clearRemoteUpload
          ? null
          : lastRemoteUploadPath ?? this.lastRemoteUploadPath,
      lastRemoteUploadCount: clearRemoteUpload
          ? null
          : lastRemoteUploadCount ?? this.lastRemoteUploadCount,
      remotePreview:
          clearRemotePreview ? null : remotePreview ?? this.remotePreview,
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
      clearRemotePreview: true,
      clearRemoteUpload: true,
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
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemotePreview: true,
      clearRemoteUpload: true,
    );
    try {
      final result = await _service.writeManifest();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        lastManifestPath: result.file.path,
        lastMarkdownPath: result.markdownFile?.path,
        lastHtmlReportPath: result.htmlReportFile?.path,
        lastAnkiPath: result.ankiFile?.path,
        lastSyncBundlePath: result.syncBundleFile?.path,
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

  Future<void> submitConflictsToReview() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _service.submitConflictsToReview();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        lastConflictReviewCount: result.submittedCount,
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

  Future<void> previewRemoteSync() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
    );
    try {
      final preview = await _service.previewRemoteSync();
      state = state.copyWith(
        busy: false,
        remotePreview: preview,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
      );
    }
  }

  Future<void> submitRemoteConflictsToReview() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
    );
    try {
      final result = await _service.submitRemoteConflictsToReview();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        remotePreview: result.remotePreview,
        lastRemoteConflictReviewCount: result.submittedCount,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
      );
    }
  }

  Future<void> stageRemoteKnowledgeCardConflictsToReview() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
    );
    try {
      final result = await _service.stageRemoteKnowledgeCardConflictsToReview();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        remotePreview: result.remotePreview,
        lastRemoteConflictStageCount: result.stagedCount,
        lastRemoteConflictStageSkippedCount: result.skippedCount,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
      );
    }
  }

  Future<void> submitRemoteIncomingToReview() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
    );
    try {
      final result = await _service.submitRemoteIncomingToReview();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        remotePreview: result.remotePreview,
        lastRemoteIncomingReviewCount: result.submittedCount,
        lastRemoteIncomingSkippedCount: result.skippedCount,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
      );
    }
  }

  Future<void> submitRemoteReviewHistoryToReview() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
    );
    try {
      final result = await _service.submitRemoteReviewHistoryToReview();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        remotePreview: result.remotePreview,
        lastRemoteReviewHistoryReviewCount: result.submittedCount,
        lastRemoteReviewHistorySkippedCount: result.skippedCount,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
      );
    }
  }

  Future<void> uploadRemoteSyncBundle() async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await _service.uploadRemoteSyncBundle();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
          result.snapshot,
        ),
        remotePreview: result.preview,
        lastRemoteUploadPath: result.remotePath,
        lastRemoteUploadCount: result.uploadedCount,
        lastSyncBundlePath: result.file.path,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
      );
    }
  }
}
