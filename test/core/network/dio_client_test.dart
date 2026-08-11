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

    // Task 10 fix-round (F3): the server's error envelope
    // (`{"error": {"code","message",...}}`) carries a specific explanation
    // — "why was this rejected" — that a generic Dio message never does.
    // Without this, the approval screen's validation branch would have
    // nothing meaningful to show.
    test('a 422 envelope message is surfaced verbatim, not Dio\'s generic '
        'status message', () {
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response<Map<String, dynamic>>(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 422,
            data: {
              'error': {
                'code': 'DECISION_REASON_REQUIRED',
                'message':
                    'A reason is required to return or reject a '
                    'campaign.',
                'traceId': 'trace-1',
              },
            },
          ),
        ),
      );

      expect(failure.kind, FailureKind.validation);
      expect(
        failure.message,
        'A reason is required to return or reject a campaign.',
      );
    });

    test('a non-envelope-shaped body falls back to the transport message, not '
        'a crash', () {
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response<String>(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            data: 'plain text failure',
          ),
          message: 'Http status error [500]',
        ),
      );

      expect(failure.kind, FailureKind.server);
      expect(failure.message, 'Http status error [500]');
    });
  });
}
