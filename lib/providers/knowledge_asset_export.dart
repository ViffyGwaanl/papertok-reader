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
  repreviewRequired,
  concurrencyGuardUnavailable,
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
    this.lastRemoteRollbackPath,
    this.lastRemoteRollbackRestored,
    this.lastRemotePartialRemoved,
    this.lastRemoteConditionalWriteSupported,
    this.lastRemotePreconditionFailed,
    this.lastRemoteCheckAt,
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
  final String? lastRemoteRollbackPath;
  final bool? lastRemoteRollbackRestored;
  final bool? lastRemotePartialRemoved;
  final bool? lastRemoteConditionalWriteSupported;
  final bool? lastRemotePreconditionFailed;
  final int? lastRemoteCheckAt;
  final KnowledgeRemoteSyncPreview? remotePreview;
  final String? lastError;

  KnowledgeRemoteSyncStatus get remoteSyncStatus {
    if (lastRemoteConditionalWriteSupported == false) {
      return KnowledgeRemoteSyncStatus.concurrencyGuardUnavailable;
    }
    if (lastRemotePreconditionFailed == true) {
      return KnowledgeRemoteSyncStatus.repreviewRequired;
    }
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
    String? lastRemoteRollbackPath,
    bool? lastRemoteRollbackRestored,
    bool? lastRemotePartialRemoved,
    bool? lastRemoteConditionalWriteSupported,
    bool? lastRemotePreconditionFailed,
    int? lastRemoteCheckAt,
    KnowledgeRemoteSyncPreview? remotePreview,
    String? lastError,
    bool clearError = false,
    bool clearRemotePreview = false,
    bool clearRemoteUpload = false,
    bool clearRemoteCheck = false,
    bool clearReviewHandoffCounts = false,
    bool clearRemoteReviewHandoffCounts = false,
  }) {
    final clearRemoteHandoffCounts =
        clearReviewHandoffCounts || clearRemoteReviewHandoffCounts;
    return KnowledgeAssetExportState(
      snapshot: snapshot ?? this.snapshot,
      busy: busy ?? this.busy,
      lastManifestPath: lastManifestPath ?? this.lastManifestPath,
      lastMarkdownPath: lastMarkdownPath ?? this.lastMarkdownPath,
      lastHtmlReportPath: lastHtmlReportPath ?? this.lastHtmlReportPath,
      lastAnkiPath: lastAnkiPath ?? this.lastAnkiPath,
      lastSyncBundlePath: lastSyncBundlePath ?? this.lastSyncBundlePath,
      lastConflictReviewCount: clearReviewHandoffCounts
          ? null
          : lastConflictReviewCount ?? this.lastConflictReviewCount,
      lastRemoteConflictReviewCount: clearRemoteHandoffCounts
          ? lastRemoteConflictReviewCount
          : lastRemoteConflictReviewCount ?? this.lastRemoteConflictReviewCount,
      lastRemoteConflictStageCount: clearRemoteHandoffCounts
          ? lastRemoteConflictStageCount
          : lastRemoteConflictStageCount ?? this.lastRemoteConflictStageCount,
      lastRemoteConflictStageSkippedCount: clearRemoteHandoffCounts
          ? lastRemoteConflictStageSkippedCount
          : lastRemoteConflictStageSkippedCount ??
              this.lastRemoteConflictStageSkippedCount,
      lastRemoteIncomingReviewCount: clearRemoteHandoffCounts
          ? lastRemoteIncomingReviewCount
          : lastRemoteIncomingReviewCount ?? this.lastRemoteIncomingReviewCount,
      lastRemoteIncomingSkippedCount: clearRemoteHandoffCounts
          ? lastRemoteIncomingSkippedCount
          : lastRemoteIncomingSkippedCount ??
              this.lastRemoteIncomingSkippedCount,
      lastRemoteReviewHistoryReviewCount: clearRemoteHandoffCounts
          ? lastRemoteReviewHistoryReviewCount
          : lastRemoteReviewHistoryReviewCount ??
              this.lastRemoteReviewHistoryReviewCount,
      lastRemoteReviewHistorySkippedCount: clearRemoteHandoffCounts
          ? lastRemoteReviewHistorySkippedCount
          : lastRemoteReviewHistorySkippedCount ??
              this.lastRemoteReviewHistorySkippedCount,
      lastRemoteUploadPath: clearRemoteUpload
          ? null
          : lastRemoteUploadPath ?? this.lastRemoteUploadPath,
      lastRemoteUploadCount: clearRemoteUpload
          ? null
          : lastRemoteUploadCount ?? this.lastRemoteUploadCount,
      lastRemoteRollbackPath: clearRemoteUpload
          ? null
          : lastRemoteRollbackPath ?? this.lastRemoteRollbackPath,
      lastRemoteRollbackRestored: clearRemoteUpload
          ? null
          : lastRemoteRollbackRestored ?? this.lastRemoteRollbackRestored,
      lastRemotePartialRemoved: clearRemoteUpload
          ? null
          : lastRemotePartialRemoved ?? this.lastRemotePartialRemoved,
      lastRemoteConditionalWriteSupported: clearRemoteUpload
          ? null
          : lastRemoteConditionalWriteSupported ??
              this.lastRemoteConditionalWriteSupported,
      lastRemotePreconditionFailed: clearRemoteUpload
          ? null
          : lastRemotePreconditionFailed ?? this.lastRemotePreconditionFailed,
      lastRemoteCheckAt:
          clearRemoteCheck ? null : lastRemoteCheckAt ?? this.lastRemoteCheckAt,
      remotePreview:
          clearRemotePreview ? null : remotePreview ?? this.remotePreview,
      lastError: clearError ? null : lastError ?? this.lastError,
    );
  }
}

class KnowledgeAssetExportNotifier
    extends StateNotifier<KnowledgeAssetExportState> {
  KnowledgeAssetExportNotifier(
    this._service, {
    int Function()? clock,
  })  : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        super(KnowledgeAssetExportState.initial());

  final KnowledgeAssetExportService _service;
  final int Function() _clock;

  Future<void> refresh() async {
    state = state.copyWith(
      snapshot: const AsyncValue<KnowledgeAssetExportSnapshot>.loading(),
      clearError: true,
      clearRemotePreview: true,
      clearRemoteUpload: true,
      clearRemoteCheck: true,
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
      clearRemoteCheck: true,
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
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteCheck: true,
    );
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
    await _readRemotePreview(recordRemoteCheck: false);
  }

  Future<void> checkRemoteChanges() async {
    await _readRemotePreview(recordRemoteCheck: true);
  }

  Future<void> _readRemotePreview({
    required bool recordRemoteCheck,
  }) async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
      clearRemoteCheck: !recordRemoteCheck,
      clearRemoteReviewHandoffCounts: recordRemoteCheck,
    );
    try {
      final preview = await _service.previewRemoteSync();
      state = state.copyWith(
        busy: false,
        remotePreview: preview,
        lastRemoteCheckAt: recordRemoteCheck ? _clock() : null,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        busy: false,
        lastError: error.toString(),
        clearRemotePreview: true,
        clearRemoteCheck: recordRemoteCheck,
      );
    }
  }

  Future<void> submitRemoteConflictsToReview() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
      clearRemoteCheck: true,
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
      clearRemoteCheck: true,
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
      clearRemoteCheck: true,
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
      clearRemoteCheck: true,
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
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
      clearRemoteCheck: true,
    );
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
        lastRemoteRollbackPath: result.rollbackSnapshotFile?.path,
        lastRemoteRollbackRestored: result.rollbackRestored,
        lastRemotePartialRemoved: result.removedPartialRemote,
        lastRemoteConditionalWriteSupported: result.conditionalWriteSupported,
        lastRemotePreconditionFailed: result.remotePreconditionFailed,
        lastSyncBundlePath: result.file.path,
        clearError: true,
        clearReviewHandoffCounts: true,
      );
    } catch (error) {
      final writebackError =
          error is KnowledgeRemoteWritebackException ? error : null;
      state = state.copyWith(
        busy: false,
        lastRemoteRollbackPath: writebackError?.rollbackSnapshotPath,
        lastRemoteRollbackRestored: writebackError?.rollbackRestored,
        lastRemotePartialRemoved: writebackError?.removedPartialRemote,
        lastRemoteConditionalWriteSupported:
            writebackError?.conditionalWriteSupported,
        lastRemotePreconditionFailed: writebackError?.remotePreconditionFailed,
        lastError: error.toString(),
      );
    }
  }

  Future<void> runSafeRemoteSync() async {
    state = state.copyWith(
      busy: true,
      clearError: true,
      clearRemoteUpload: true,
      clearRemoteCheck: true,
    );
    try {
      final preview = await _service.previewRemoteSync();
      if (preview.incomingCount == 0 && preview.conflictCount == 0) {
        final result = await _service.uploadRemoteSyncBundle();
        state = state.copyWith(
          busy: false,
          snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(
            result.snapshot,
          ),
          remotePreview: result.preview,
          lastRemoteUploadPath: result.remotePath,
          lastRemoteUploadCount: result.uploadedCount,
          lastRemoteRollbackPath: result.rollbackSnapshotFile?.path,
          lastRemoteRollbackRestored: result.rollbackRestored,
          lastRemotePartialRemoved: result.removedPartialRemote,
          lastRemoteConditionalWriteSupported: result.conditionalWriteSupported,
          lastRemotePreconditionFailed: result.remotePreconditionFailed,
          lastSyncBundlePath: result.file.path,
          clearError: true,
          clearReviewHandoffCounts: true,
        );
        return;
      }

      var latestPreview = preview;
      KnowledgeAssetExportSnapshot? snapshot;
      int? conflictReviewCount;
      int? conflictStageCount;
      int? conflictStageSkippedCount;
      int? incomingReviewCount;
      int? incomingSkippedCount;
      int? reviewHistoryReviewCount;
      int? reviewHistorySkippedCount;

      if (preview.conflictCount > 0) {
        final stageResult =
            await _service.stageRemoteKnowledgeCardConflictsToReview();
        snapshot = stageResult.snapshot;
        latestPreview = stageResult.remotePreview;
        conflictStageCount = stageResult.stagedCount;
        conflictStageSkippedCount = stageResult.skippedCount;

        final conflictResult = await _service.submitRemoteConflictsToReview();
        snapshot = conflictResult.snapshot;
        if (conflictResult.remotePreview case final remotePreview?) {
          latestPreview = remotePreview;
        }
        conflictReviewCount = conflictResult.submittedCount;
      }

      if (preview.incomingCount > 0) {
        final incomingResult = await _service.submitRemoteIncomingToReview();
        snapshot = incomingResult.snapshot;
        latestPreview = incomingResult.remotePreview;
        incomingReviewCount = incomingResult.submittedCount;
        incomingSkippedCount = incomingResult.skippedCount;
      }

      if (preview.incoming.any(
        (envelope) =>
            envelope.entityType == KnowledgeSyncEntityType.reviewHistory,
      )) {
        final historyResult =
            await _service.submitRemoteReviewHistoryToReview();
        snapshot = historyResult.snapshot;
        latestPreview = historyResult.remotePreview;
        reviewHistoryReviewCount = historyResult.submittedCount;
        reviewHistorySkippedCount = historyResult.skippedCount;
      }

      snapshot ??= await _service.buildSnapshot();
      state = state.copyWith(
        busy: false,
        snapshot: AsyncValue<KnowledgeAssetExportSnapshot>.data(snapshot),
        remotePreview: latestPreview,
        lastRemoteConflictReviewCount: conflictReviewCount,
        lastRemoteConflictStageCount: conflictStageCount,
        lastRemoteConflictStageSkippedCount: conflictStageSkippedCount,
        lastRemoteIncomingReviewCount: incomingReviewCount,
        lastRemoteIncomingSkippedCount: incomingSkippedCount,
        lastRemoteReviewHistoryReviewCount: reviewHistoryReviewCount,
        lastRemoteReviewHistorySkippedCount: reviewHistorySkippedCount,
        clearError: true,
        clearRemoteReviewHandoffCounts: true,
      );
    } catch (error) {
      final writebackError =
          error is KnowledgeRemoteWritebackException ? error : null;
      state = state.copyWith(
        busy: false,
        lastRemoteRollbackPath: writebackError?.rollbackSnapshotPath,
        lastRemoteRollbackRestored: writebackError?.rollbackRestored,
        lastRemotePartialRemoved: writebackError?.removedPartialRemote,
        lastRemoteConditionalWriteSupported:
            writebackError?.conditionalWriteSupported,
        lastRemotePreconditionFailed: writebackError?.remotePreconditionFailed,
        lastError: error.toString(),
        clearRemotePreview: writebackError == null,
      );
    }
  }
}
