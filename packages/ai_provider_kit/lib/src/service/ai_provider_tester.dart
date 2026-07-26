import 'dart:async';

import 'package:dio/dio.dart';

import '../models/ai_provider_meta.dart';
import 'ai_models_service.dart';

/// Why a connectivity check failed.
///
/// The point of classifying is that each case has a different fix, and "request
/// failed" tells a user nothing about which one applies.
enum AiProviderTestFailure {
  /// Key missing, wrong, or lacking permission (401/403).
  unauthorized,

  /// Endpoint reached but the path does not exist (404) — usually a base URL
  /// that points at the wrong place.
  notFound,

  /// Throttled or out of quota (429).
  rateLimited,

  /// Provider-side error (5xx).
  serverError,

  /// Host unreachable, DNS failure, TLS failure, no connectivity.
  network,

  /// Connected but the provider did not answer in time.
  timeout,

  /// Answered, but not with a model list this client understands.
  badResponse,

  unknown,
}

/// Outcome of a provider connectivity check.
class AiProviderTestResult {
  const AiProviderTestResult({
    required this.ok,
    required this.latency,
    this.modelCount = 0,
    this.statusCode,
    this.failure,
    this.message,
  });

  final bool ok;

  /// Round-trip time of the check, useful for comparing gateways.
  final Duration latency;

  /// How many models the provider advertised. Zero on a successful call means
  /// the endpoint works but exposes no catalog.
  final int modelCount;

  final int? statusCode;
  final AiProviderTestFailure? failure;

  /// Raw provider message, for diagnostics. Not user-facing copy — map
  /// [failure] to a localized string in the host app.
  final String? message;
}

/// Verifies that a provider's endpoint and key actually work.
///
/// Implemented as a model-list fetch: it is the one call every supported
/// provider offers, it needs no tokens, and it doubles as catalog discovery.
class AiProviderTester {
  const AiProviderTester._();

  static Future<AiProviderTestResult> test({
    required AiProviderMeta provider,
    required Map<String, String> config,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final models = await AiModelsService.fetchModelCapabilities(
        provider: provider,
        rawConfig: config,
      );
      stopwatch.stop();
      return AiProviderTestResult(
        ok: true,
        latency: stopwatch.elapsed,
        modelCount: models.length,
      );
    } on DioException catch (e) {
      stopwatch.stop();
      return AiProviderTestResult(
        ok: false,
        latency: stopwatch.elapsed,
        statusCode: e.response?.statusCode,
        failure: classifyDioException(e),
        message: _messageOf(e),
      );
    } catch (e) {
      stopwatch.stop();
      return AiProviderTestResult(
        ok: false,
        latency: stopwatch.elapsed,
        failure: AiProviderTestFailure.unknown,
        message: e.toString(),
      );
    }
  }

  /// Exposed for host apps that issue their own requests and want the same
  /// classification.
  static AiProviderTestFailure classifyDioException(DioException e) {
    // `default` rather than an exhaustive match on purpose: dio adds enum
    // values across 5.x releases, and a host app may pin an older version than
    // this package resolves to on its own.
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AiProviderTestFailure.timeout;
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return AiProviderTestFailure.network;
      default:
        break;
    }

    final status = e.response?.statusCode;
    if (status != null) return classifyStatusCode(status);
    return e.error is FormatException
        ? AiProviderTestFailure.badResponse
        : AiProviderTestFailure.unknown;
  }

  static AiProviderTestFailure classifyStatusCode(int status) {
    if (status == 401 || status == 403) return AiProviderTestFailure.unauthorized;
    if (status == 404) return AiProviderTestFailure.notFound;
    if (status == 429) return AiProviderTestFailure.rateLimited;
    if (status >= 500) return AiProviderTestFailure.serverError;
    if (status >= 400) return AiProviderTestFailure.badResponse;
    return AiProviderTestFailure.unknown;
  }

  static String _messageOf(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] != null) {
        return error['message'].toString();
      }
      if (data['message'] != null) return data['message'].toString();
    }
    if (data is String && data.trim().isNotEmpty) return data.trim();
    return e.message ?? e.toString();
  }
}
