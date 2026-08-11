import 'dart:convert';

import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/infra/request_log.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  Handler build(StringBuffer sink, Handler inner) => const Pipeline()
      .addMiddleware(correlation())
      .addMiddleware(requestLog(sink: sink))
      .addMiddleware(errorEnvelope())
      .addHandler(inner);

  test(
    'logs one JSON line whose traceId matches the response header',
    () async {
      final sink = StringBuffer();
      final handler = build(sink, (req) async => Response.ok('ok'));

      final res = await handler(
        Request('GET', Uri.parse('http://localhost/campaigns?page=2')),
      );

      final lines = sink.toString().trim().split('\n');
      expect(lines, hasLength(1));
      final line = jsonDecode(lines.single) as Map<String, Object?>;
      expect(line['method'], 'GET');
      expect(
        line['path'],
        '/campaigns',
        reason:
            'path only — query params can carry user data and do not '
            'belong in every log line',
      );
      expect(line['status'], 200);
      expect(line['durationMs'], isA<int>());
      expect(
        line['traceId'],
        res.headers['x-correlation-id'],
        reason:
            'the log line is only useful if the id in it is the id the '
            'client saw',
      );
    },
  );

  test(
    'a thrown error is logged with the enveloped status, not skipped',
    () async {
      final sink = StringBuffer();
      final handler = build(sink, (req) async => throw StateError('boom'));

      await handler(Request('GET', Uri.parse('http://localhost/x')));

      final line = jsonDecode(sink.toString().trim()) as Map<String, Object?>;
      expect(
        line['status'],
        500,
        reason:
            'requestLog sits OUTSIDE errorEnvelope, so it sees the '
            'envelope-produced 500, and a throwing handler still logs',
      );
    },
  );
}
