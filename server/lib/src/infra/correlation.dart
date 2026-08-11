import 'package:shelf/shelf.dart';
import 'package:uuid/uuid.dart';

const String _headerName = 'X-Correlation-Id';
const String _contextKey = 'correlationId';

const Uuid _uuid = Uuid();

/// Resolves the correlation id for one request: the client's own
/// `X-Correlation-Id` header when present, or a freshly minted one.
///
/// Echoes the resolved id back on every response — including error
/// responses, since [mapDioError] on the client prefers the server's id over
/// the one it sent (`dio_client.dart:67-70`) precisely so a transport-level
/// failure still carries a correlation id.
///
/// Deliberately runs OUTSIDE [errorEnvelope]: `errorEnvelope` reads
/// [correlationOf] to stamp `traceId` on an error body, so the id must
/// already be attached to the request by the time a handler throws.
Middleware correlation() {
  return (Handler inner) {
    return (Request request) async {
      final supplied = request.headers[_headerName];
      final id = (supplied == null || supplied.isEmpty) ? _uuid.v4() : supplied;

      final response = await inner(request.change(context: {_contextKey: id}));
      return response.change(headers: {_headerName: id});
    };
  };
}

/// The correlation id resolved by [correlation] for [request].
///
/// Throws if [correlation] did not run — the same "fail loudly rather than
/// silently invent an id" contract as `authOf`.
String correlationOf(Request request) {
  final value = request.context[_contextKey];
  if (value is! String) {
    throw StateError(
      'correlationOf() called on a request that did not pass through '
      'correlation(). Wire the route behind the correlation middleware.',
    );
  }
  return value;
}
