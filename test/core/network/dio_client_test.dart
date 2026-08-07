import 'package:acsl_campaign/core/network/dio_client.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapDioError', () {
    test('maps a 429 to server, not unknown', () {
      // Guideline §2.1 rules out a generic "unknown" surfacing to the user.
      // RetryInterceptor has already exhausted its budget on the transient
      // case by the time this is seen, so it must read as "the service is
      // busy, try again" - the same corrective action as a 5xx.
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 429,
          ),
        ),
      );

      expect(failure.kind, FailureKind.server);
    });

    test('maps a sendTimeout to timeout, not unknown', () {
      // RetryInterceptor already treats sendTimeout as retryable alongside
      // connectionTimeout/receiveTimeout; after retry exhaustion the mapped
      // Failure must agree, not fall through to a generic "unknown".
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.sendTimeout,
        ),
      );

      expect(failure.kind, FailureKind.timeout);
    });
  });
}
