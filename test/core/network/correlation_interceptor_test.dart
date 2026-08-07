import 'package:acsl_campaign/core/network/correlation_interceptor.dart';
import 'package:acsl_campaign/core/network/dio_client.dart';
import 'package:acsl_campaign/core/network/trace_options.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  Dio buildTestDio(ScriptedAdapter adapter) {
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter
      ..interceptors.add(const CorrelationIdInterceptor());
    return dio;
  }

  group('CorrelationIdInterceptor', () {
    test('mints a trace id when the caller supplied none', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      await buildTestDio(adapter).get<void>('/campaigns');

      final sent = adapter.requests.single;
      final header = sent.headers[CorrelationIdInterceptor.headerName];
      expect(header, isA<String>());
      expect(header as String, isNotEmpty);
      // The resolved id is written back so mapDioError can recover it.
      expect(sent.extra[traceIdExtraKey], isA<TraceId>());
      expect((sent.extra[traceIdExtraKey] as TraceId).value, header);
    });

    test('preserves a caller-supplied trace id verbatim', () async {
      // A per-action id must survive untouched, or the audit row and the API
      // call it describes end up with different ids and the trace is useless.
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      const trace = TraceId.of('action-abc');

      await buildTestDio(
        adapter,
      ).post<void>('/campaigns', options: traceOptions(trace));

      expect(
        adapter.requests.single.headers[CorrelationIdInterceptor.headerName],
        'action-abc',
      );
    });

    test('forwards an idempotency key as a header when supplied', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);

      await buildTestDio(adapter).post<void>(
        '/campaigns',
        options: traceOptions(const TraceId.of('t1'), idempotencyKey: 'key-1'),
      );

      expect(adapter.requests.single.headers['Idempotency-Key'], 'key-1');
    });

    test('omits the idempotency header when none was supplied', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);

      await buildTestDio(
        adapter,
      ).post<void>('/campaigns', options: traceOptions(const TraceId.of('t1')));

      expect(
        adapter.requests.single.headers.containsKey('Idempotency-Key'),
        isFalse,
      );
    });
  });

  group('mapDioError correlation id', () {
    test('prefers the response header when the server sent one', () {
      final failure = mapDioError(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response<void>(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 500,
            headers: Headers.fromMap({
              'x-correlation-id': ['server-side-id'],
            }),
          ),
        ),
      );

      expect(failure.correlationId, 'server-side-id');
    });

    test('falls back to the request trace id on a transport error', () async {
      // A connection error has no response and therefore no header. Before the
      // fallback this produced a Failure with a null correlation id - the exact
      // case a user most needs to quote to support.
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
      ]);
      final dio = buildTestDio(adapter);

      Failure? captured;
      try {
        await dio.get<void>(
          '/campaigns',
          options: traceOptions(const TraceId.of('trace-9')),
        );
      } on DioException catch (e) {
        captured = mapDioError(e);
      }

      expect(captured, isNotNull);
      expect(captured!.kind, FailureKind.network);
      expect(captured.correlationId, 'trace-9');
    });
  });
}
