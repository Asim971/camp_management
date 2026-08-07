import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/audit/audit_transport.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditEventPayload', () {
    const event = AuditEvent(
      action: AuditAction.campaignApproved,
      entity: 'campaign',
      entityId: 'CMP-1',
      correlationId: TraceId.of('trace-1'),
      actorId: 'user-1',
    );

    test('toJson includes id and occurredAt', () {
      // IMPORTANT #1/#2: the audit table persists both fields specifically so
      // the server can dedupe a replayed batch (id) and pair a client
      // timestamp with its own receipt time (occurredAt). A wire payload that
      // drops either defeats the reason the column exists.
      final payload = AuditEventPayload.fromEvent(
        event,
        id: 'evt-1',
        occurredAt: DateTime.utc(2026, 8, 6, 12, 30),
      );

      final json = payload.toJson();

      expect(json['id'], 'evt-1');
      expect(json['occurredAt'], '2026-08-06T12:30:00.000Z');
    });

    test('serializes occurredAt as ISO-8601 UTC regardless of local input', () {
      // Drift round-trips DateTimeColumn as local-zoned under NativeDatabase,
      // so `.toUtc()` before serializing is load-bearing, not decoration: a
      // device in a non-UTC timezone must still produce an unambiguous wire
      // value.
      final local = DateTime(2026, 8, 6, 12, 30).toLocal();
      final payload = AuditEventPayload.fromEvent(
        event,
        id: 'evt-1',
        occurredAt: local,
      );

      expect(payload.toJson()['occurredAt'], local.toUtc().toIso8601String());
      expect(payload.toJson()['occurredAt'], endsWith('Z'));
    });

    test(
      'fromEvent preserves the caller-supplied id and occurredAt instant',
      () {
        final occurredAt = DateTime.utc(2026, 8, 6, 9);
        final payload = AuditEventPayload.fromEvent(
          event,
          id: 'row-id-42',
          occurredAt: occurredAt,
        );

        expect(payload.id, 'row-id-42');
        expect(payload.occurredAt, occurredAt);
      },
    );
  });
}
