import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class BookmarkChannel {
  BookmarkChannel._internal();
  static final BookmarkChannel instance = BookmarkChannel._internal();
  static const _channel = MethodChannel('ai.papertok.paperreader/bookmark');

  Future<PickedBookmark?> pickInPlace({
    List<String> allowedExt = const ['pdf', 'epub'],
  }) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'pickInPlace', {'allowedExt': allowedExt});
    if (result == null) return null;
    return PickedBookmark.fromMap(Map<String, Object?>.from(result));
  }

  Future<ResolvedBookmark> resolveBookmark(Uint8List blob) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'resolveBookmark', {'bookmark': base64Encode(blob)});
    return ResolvedBookmark.fromMap(Map<String, Object?>.from(result!));
  }

  Future<ScopedAccess> startAccess(Uint8List blob) async {
    final result = await _channel.invokeMethod<Map<Object?, Object?>>(
      'startAccess', {'bookmark': base64Encode(blob)});
    return ScopedAccess.fromMap(Map<String, Object?>.from(result!));
  }

  Future<void> stopAccess(String token) async {
    await _channel.invokeMethod<void>('stopAccess', {'token': token});
  }
}

class PickedBookmark {
  final Uint8List bookmark;
  final String name;
  final int size;
  final double mtime;
  final String ext;
  final String displayPath;
  const PickedBookmark({
    required this.bookmark, required this.name, required this.size,
    required this.mtime, required this.ext, required this.displayPath,
  });
  factory PickedBookmark.fromMap(Map<String, Object?> m) => PickedBookmark(
    bookmark: base64Decode(m['bookmark'] as String),
    name: m['name'] as String? ?? '',
    size: (m['size'] as num?)?.toInt() ?? 0,
    mtime: (m['mtime'] as num?)?.toDouble() ?? 0,
    ext: m['ext'] as String? ?? '',
    displayPath: m['displayPath'] as String? ?? '',
  );
}

class ResolvedBookmark {
  final String? path;
  final bool isStale;
  final Uint8List? freshBookmark;
  final String? error;
  const ResolvedBookmark({required this.path, required this.isStale, this.freshBookmark, this.error});
  factory ResolvedBookmark.fromMap(Map<String, Object?> m) {
    final fresh = m['freshBookmark'] as String?;
    return ResolvedBookmark(
      path: m['path'] as String?,
      isStale: m['isStale'] as bool? ?? false,
      freshBookmark: fresh != null ? base64Decode(fresh) : null,
      error: m['error'] as String?,
    );
  }
}

class ScopedAccess {
  final String token;
  final String path;
  final bool isStale;
  final Uint8List? freshBookmark;
  const ScopedAccess({required this.token, required this.path, required this.isStale, this.freshBookmark});
  factory ScopedAccess.fromMap(Map<String, Object?> m) {
    final fresh = m['freshBookmark'] as String?;
    return ScopedAccess(
      token: m['token'] as String,
      path: m['path'] as String,
      isStale: m['isStale'] as bool? ?? false,
      freshBookmark: fresh != null ? base64Decode(fresh) : null,
    );
  }
}
