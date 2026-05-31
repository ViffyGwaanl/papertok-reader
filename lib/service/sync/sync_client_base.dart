import 'package:papertok_reader/models/remote_file.dart';
import 'package:dio/dio.dart';

class SyncRemoteWritePrecondition {
  const SyncRemoteWritePrecondition._({
    this.expectedETag,
    this.requireRemoteAbsent = false,
  });

  const SyncRemoteWritePrecondition.ifMatch(String expectedETag)
      : this._(expectedETag: expectedETag);

  const SyncRemoteWritePrecondition.ifNoneMatch()
      : this._(requireRemoteAbsent: true);

  final String? expectedETag;
  final bool requireRemoteAbsent;
}

class SyncConditionalWriteNotSupportedException implements Exception {
  const SyncConditionalWriteNotSupportedException(this.protocolName);

  final String protocolName;

  @override
  String toString() {
    return '$protocolName does not support conditional remote writes.';
  }
}

class SyncPreconditionFailedException implements Exception {
  const SyncPreconditionFailedException({
    required this.remotePath,
    required this.reason,
  });

  final String remotePath;
  final String reason;

  @override
  String toString() {
    return 'Remote write precondition failed for $remotePath: $reason';
  }
}

abstract class SyncClientBase {
  /// Whether this client can atomically guard uploads with an ETag/CAS
  /// precondition such as If-Match or If-None-Match.
  bool get supportsConditionalWrite => false;

  /// Test connection to the remote server
  Future<void> ping();

  /// Test full capabilities (create, upload, download, delete)
  /// This performs a comprehensive test by:
  /// 1. Creating a test directory
  /// 2. Uploading a test file
  /// 3. Downloading and verifying content
  /// 4. Cleaning up test files
  Future<void> testFullCapabilities();

  /// Create a directory at the given path
  Future<void> mkdirAll(String path);

  /// List files and directories in the given path
  Future<List<RemoteFile>> readDir(String path);

  /// Remove a file or directory
  Future<void> remove(String path);

  /// Check if a file or directory exists at the given path
  Future<bool> isExist(String path);

  /// Upload a file from local path to remote path
  Future<void> uploadFile(
    String localPath,
    String remotePath, {
    bool replace = true,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  });

  /// Upload a file only if the remote still matches [precondition].
  Future<void> uploadFileConditionally(
    String localPath,
    String remotePath, {
    required SyncRemoteWritePrecondition precondition,
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) {
    throw SyncConditionalWriteNotSupportedException(protocolName);
  }

  /// Download a file from remote path to local path
  Future<void> downloadFile(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  });

  /// Safely read directory, create if not exists
  Future<List<RemoteFile>> safeReadDir(String path);

  /// Read file properties, return null if not exists
  Future<RemoteFile?> readProps(String path);

  /// Get the protocol name for this client
  String get protocolName;

  /// Get configuration parameters for this client
  Map<String, dynamic> get config;

  /// Update configuration
  void updateConfig(Map<String, dynamic> newConfig);

  /// Check if the client is properly configured
  bool get isConfigured;
}
