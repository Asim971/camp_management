import 'package:dio/dio.dart';

import '../trace/trace_id.dart';

/// Key under which a [TraceId] travels in `RequestOptions.extra`.
const String traceIdExtraKey = 'traceId';

/// Key under which a client idempotency key travels in `RequestOptions.extra`.
///
/// Presence of this key is what makes a non-idempotent request retryable
/// (see `RetryInterceptor`). Never set it for a request the server cannot
/// deduplicate.
const String idempotencyKeyExtraKey = 'idempotencyKey';

/// Builds request [Options] carrying a per-action [trace], and optionally the
/// [idempotencyKey] that permits retrying an unsafe method.
Options traceOptions(TraceId trace, {String? idempotencyKey}) => Options(
  extra: <String, Object?>{
    traceIdExtraKey: trace,
    if (idempotencyKey != null) idempotencyKeyExtraKey: idempotencyKey,
  },
);
