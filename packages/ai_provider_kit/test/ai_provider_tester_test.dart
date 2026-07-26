import 'package:ai_provider_kit/ai_provider_kit.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

DioException withStatus(int status) {
  final options = RequestOptions(path: '/models');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status),
  );
}

DioException ofType(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/models'),
      type: type,
    );

void main() {
  group('classifyStatusCode', () {
    test('separates the cases that need different fixes', () {
      // A bad key and a bad base URL both "fail"; only one is fixed by pasting
      // a new key.
      expect(
        AiProviderTester.classifyStatusCode(401),
        AiProviderTestFailure.unauthorized,
      );
      expect(
        AiProviderTester.classifyStatusCode(403),
        AiProviderTestFailure.unauthorized,
      );
      expect(
        AiProviderTester.classifyStatusCode(404),
        AiProviderTestFailure.notFound,
      );
      expect(
        AiProviderTester.classifyStatusCode(429),
        AiProviderTestFailure.rateLimited,
      );
      expect(
        AiProviderTester.classifyStatusCode(502),
        AiProviderTestFailure.serverError,
      );
      expect(
        AiProviderTester.classifyStatusCode(422),
        AiProviderTestFailure.badResponse,
      );
    });
  });

  group('classifyDioException', () {
    test('maps transport failures', () {
      expect(
        AiProviderTester.classifyDioException(
          ofType(DioExceptionType.connectionTimeout),
        ),
        AiProviderTestFailure.timeout,
      );
      expect(
        AiProviderTester.classifyDioException(
          ofType(DioExceptionType.receiveTimeout),
        ),
        AiProviderTestFailure.timeout,
      );
      expect(
        AiProviderTester.classifyDioException(
          ofType(DioExceptionType.connectionError),
        ),
        AiProviderTestFailure.network,
      );
      expect(
        AiProviderTester.classifyDioException(
          ofType(DioExceptionType.badCertificate),
        ),
        AiProviderTestFailure.network,
      );
    });

    test('prefers the status code when there is a response', () {
      expect(
        AiProviderTester.classifyDioException(withStatus(401)),
        AiProviderTestFailure.unauthorized,
      );
      expect(
        AiProviderTester.classifyDioException(withStatus(404)),
        AiProviderTestFailure.notFound,
      );
    });

    test('falls back to unknown rather than guessing', () {
      expect(
        AiProviderTester.classifyDioException(ofType(DioExceptionType.unknown)),
        AiProviderTestFailure.unknown,
      );
    });
  });

  test('a failed check still reports latency', () async {
    final result = await AiProviderTester.test(
      provider: AiProviderMeta(
        id: 'x',
        name: 'x',
        type: AiProviderType.openaiCompatible,
        enabled: true,
        isBuiltIn: false,
        createdAt: 0,
        updatedAt: 0,
      ),
      // Reserved TEST-NET-1 address: guaranteed not to answer.
      config: const {'url': 'http://192.0.2.1:9/v1/chat/completions'},
    );

    expect(result.ok, isFalse);
    expect(result.failure, isNotNull);
    expect(result.latency, greaterThanOrEqualTo(Duration.zero));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
