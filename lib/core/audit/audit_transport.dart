import 'package:dio/dio.dart';

import '../network/dio_client.dart';
import '../result/result.dart';
import 'audit.dart';

/// One audit event in wire shape.
///
/// [action] is a plain String, not an [AuditAction], on purpose. The flusher
/// reads rows written by whatever build was installed at the time, and Android
/// permits downgrades - so a row can legitimately carry an action this build
/// has no enum value for. Mapping it back through the enum would force a
/// choice between throwing mid-flush and substituting some *other* real
/// action, and silently relabelling a compliance record is falsification, not
/// degradation. The persisted string ships verbatim instead.
class AuditEventPayload {
  const AuditEventPayload({
    required this.action,
    required this.entity,
    required this.entityId,
    required this.correlationId,
    required this.actorId,
    this.remarks,
  });

  /// From an in-memory event, where the action is known and typed.
  factory AuditEventPayload.fromEvent(AuditEvent event) => AuditEventPayload(
    action: event.action.name,
    entity: event.entity,
    entityId: event.entityId,
    correlationId: event.correlationId.value,
    actorId: event.actorId,
    remarks: event.remarks,
  );

  final String action;
  final String entity;
  final String entityId;
  final String correlationId;
  final String actorId;
  final String? remarks;

  Map<String, Object?> toJson() => {
    'action': action,
    'entity': entity,
    'entityId': entityId,
    'correlationId': correlationId,
    'actorId': actorId,
    if (remarks != null) 'remarks': remarks,
  };
}

/// Transport seam for shipping audit events to the server.
///
/// 🔒 The audit contract (endpoint, payload shape, batch semantics) is an
/// unresolved external dependency. Keeping it behind one method means the
/// table, the flusher, the poison-pill rule and the [AuditSink.revealAudited]
/// contract are all transport-agnostic when it lands.
///
/// Returns a [Result] rather than throwing so `audit_emitter.dart` needs no
/// network import: error mapping belongs here.
abstract interface class AuditTransport {
  Future<Result<void>> send(List<AuditEventPayload> events);
}

/// Dio-backed transport. The endpoint and payload shape are placeholders
/// pending the 🔒 audit contract, exactly as the campaign endpoints are.
class DioAuditTransport implements AuditTransport {
  DioAuditTransport(this._dio);

  final Dio _dio;

  @override
  Future<Result<void>> send(List<AuditEventPayload> events) async {
    try {
      await _dio.post<void>(
        '/audit/events',
        data: {
          'events': [for (final e in events) e.toJson()],
        },
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
