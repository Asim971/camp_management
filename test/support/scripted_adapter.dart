import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// One scripted outcome for [ScriptedAdapter].
class ScriptedReply {
  /// An HTTP response with [code] and an empty JSON body.
  const ScriptedReply.status(this.code, {this.headers = const {}})
    : failureType = null;

  /// A transport-level failure (no response), e.g. a connection error.
  const ScriptedReply.failure(DioExceptionType type)
    : code = null,
      headers = const {},
      failureType = type;

  final int? code;
  final Map<String, String> headers;
  final DioExceptionType? failureType;
}

/// A scriptable [HttpClientAdapter] so interceptor tests run without a network.
///
/// Replies are consumed in order; the last reply repeats once exhausted, which
/// keeps retry tests from needing to pad the script. Every [RequestOptions] the
/// adapter sees is recorded in [requests], so a test can assert on the *second*
/// attempt's headers and resolved URI, not just the first.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this._replies);

  final List<ScriptedReply> _replies;
  final List<RequestOptions> requests = [];

  int get callCount => requests.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final reply = _replies[(requests.length - 1).clamp(0, _replies.length - 1)];

    if (reply.failureType != null) {
      throw DioException(requestOptions: options, type: reply.failureType!);
    }

    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      reply.code!,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        for (final entry in reply.headers.entries) entry.key: [entry.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
