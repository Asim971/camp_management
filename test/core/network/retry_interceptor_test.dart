import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/network/retry_interceptor.dart';
import 'package:acsl_campaign/core/network/trace_options.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  /// Records every delay the interceptor asked for instead of sleeping, so the
  /// suite stays fast and the backoff schedule itself is assertable.
  late List<Duration> waits;

  Dio buildTestDio(ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;
    dio.interceptors.addAll([
      const CorrelationIdInterceptor(),
      RetryInterceptor(dio: dio, delay: (d) async => waits.add(d)),
    ]);
    return dio;
  }

  setUp(() => waits = []);

  group('safe methods', () {
    test('retries a GET on a connection error and succeeds', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
      expect(waits, hasLength(1));
    });

    test('retries a GET on 503', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
    });

    test('gives up after maxRetries and surfaces the last error', () async {
      // Default policy allows 2 retries, so 3 attempts total.
      final adapter = ScriptedAdapter([const ScriptedReply.status(503)]);

      await expectLater(
        buildTestDio(adapter).get<void>('/campaigns'),
        throwsA(
          isA<DioException>().having(
            (e) => e.response?.statusCode,
            'status',
            503,
          ),
        ),
      );
      expect(adapter.callCount, 3);
      expect(waits, hasLength(2));
    });

    test(
      'does not retry a 500 - the write may already have committed',
      () async {
        final adapter = ScriptedAdapter([const ScriptedReply.status(500)]);

        await expectLater(
          buildTestDio(adapter).get<void>('/campaigns'),
          throwsA(isA<DioException>()),
        );
        expect(adapter.callCount, 1);
        expect(waits, isEmpty);
      },
    );

    test('does not retry a 404', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(404)]);

      await expectLater(
        buildTestDio(adapter).get<void>('/campaigns/missing'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
    });
  });

  group('unsafe methods', () {
    test('does NOT retry a bare POST', () async {
      // Retrying a POST with no idempotency key can create two campaigns, and a
      // timeout is exactly when the client cannot tell whether the first landed.
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      await expectLater(
        buildTestDio(adapter).post<void>('/campaigns'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.callCount, 1);
      expect(waits, isEmpty);
    });

    test('retries a POST that carries an idempotency key', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
        const ScriptedReply.status(200),
      ]);

      final res = await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(const TraceId.of('t1'), idempotencyKey: 'idem-1'),
      );

      expect(res.statusCode, 200);
      expect(adapter.callCount, 2);
      // The replay must still carry the key, or the server cannot dedupe it.
      expect(
        adapter.requests.last.headers[CorrelationIdInterceptor
            .idempotencyHeaderName],
        'idem-1',
      );
    });

    test(
      'does not retry a DELETE without a key despite HTTP idempotency',
      () async {
        // DELETE is nominally idempotent per spec, but this server's semantics are
        // unconfirmed, so the explicit key is the only gate we trust.
        final adapter = ScriptedAdapter([
          const ScriptedReply.status(503),
          const ScriptedReply.status(200),
        ]);

        await expectLater(
          buildTestDio(adapter).delete<void>('/campaigns/1'),
          throwsA(isA<DioException>()),
        );
        expect(adapter.callCount, 1);
      },
    );
  });

  group('delay selection', () {
    test('honours Retry-After over computed backoff', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(429, headers: {'retry-after': '7'}),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      expect(waits.single, const Duration(seconds: 7));
    });

    test('falls back to jittered backoff when Retry-After is absent', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(503),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      // base 300ms with +/-20% jitter on the first attempt.
      expect(waits.single.inMilliseconds, inInclusiveRange(240, 360));
    });

    test('ignores an unparseable Retry-After', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(
          503,
          headers: {'retry-after': 'Wed, 21 Oct'},
        ),
        const ScriptedReply.status(200),
      ]);

      await buildTestDio(adapter).get<void>('/campaigns');

      expect(waits.single.inMilliseconds, inInclusiveRange(240, 360));
    });
  });
}
