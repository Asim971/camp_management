import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

import 'correlation.dart';

/// One structured JSON line per request: method, path, status, duration and
/// the correlation id — the operator's bridge from a client-reported trace id
/// to the server log (closes slice 1's D-B partial).
///
/// Compose INSIDE [correlation] (so [correlationOf] resolves) and OUTSIDE
/// [errorEnvelope] (so the logged status is the one the client actually
/// received, including envelope-produced 500s for thrown errors).
///
/// Deliberately logs the path WITHOUT its query string: query parameters can
/// carry user-entered search text, which does not belong in every log line.
Middleware requestLog({StringSink? sink}) {
  final out = sink ?? stdout;
  return (Handler inner) {
    return (Request request) async {
      final watch = Stopwatch()..start();
      final response = await inner(request);
      out.writeln(
        jsonEncode({
          'method': request.method,
          'path': '/${request.url.path}',
          'status': response.statusCode,
          'durationMs': watch.elapsedMilliseconds,
          'traceId': correlationOf(request),
        }),
      );
      return response;
    };
  };
}
