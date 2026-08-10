import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/audit.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late AuditWriter audit;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db);
    audit = AuditWriter(db);
  });
  tearDown(() async => db.close());

  Future<Map<String, Object?>> loadEvent(String action) async {
    final res = await db.execute(
      'SELECT * FROM audit_events WHERE action = @action',
      params: {'action': action},
    );
    return row(res.single);
  }

  test('a written event is readable back with its correlation id', () async {
    await audit.write(
      action: 'campaign.created',
      resourceType: 'campaign',
      resourceId: 'campaign-1',
      actorId: 'user-1',
      correlationId: 'corr-abc',
      payload: {'name': 'Diwali Push'},
    );

    final event = await loadEvent('campaign.created');
    expect(event['action'], 'campaign.created');
    expect(event['resource_type'], 'campaign');
    expect(event['resource_id'], 'campaign-1');
    expect(event['actor_id'], 'user-1');
    expect(event['correlation_id'], 'corr-abc');
    // The postgres driver decodes jsonb columns to Dart objects itself — the
    // stored payload comes back as a Map, never as a JSON-encoded String.
    expect(event['payload'], {'name': 'Diwali Push'});
  });

  // Login failures have no actor yet; the audit trail must still be able to
  // record the attempt.
  test('a null actorId is allowed', () async {
    await audit.write(
      action: 'auth.login_failed',
      resourceType: 'staff_user',
      correlationId: 'corr-xyz',
      payload: {'username': 'nobody'},
    );

    final event = await loadEvent('auth.login_failed');
    expect(event['actor_id'], isNull);
    expect(event['resource_id'], isNull);
    expect(event['correlation_id'], 'corr-xyz');
  });
}
