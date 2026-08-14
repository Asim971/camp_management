import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:campaign_service/src/campaign/session_machine.dart';
import 'package:campaign_service/src/campaign/session_repo.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late SessionRepo repo;
  const org = 'org-1';

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1, user-1 campaign_creator
    await seedCampaign(db, id: 'camp-1', status: CampaignStatus.approved);
    repo = SessionRepo(db);
  });
  tearDown(() async => db.close());

  test('listForCampaign returns sessions with zero activity counts', () async {
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-1',
      venue: 'BMD Training Center, Hall A',
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
    );
    final list = await repo.listForCampaign('camp-1', organizationId: org);
    expect(list, isNotNull);
    final v = list!.single;
    expect(v.status, SessionStatus.upcoming);
    expect(v.readinessOk, isTrue); // approved campaign + venue + start time
    final wire = v.toWireJson();
    expect(wire['registeredCount'], 0);
    expect(wire['approvedCount'], 0);
    expect(wire['status'], 'UPCOMING');
  });

  test(
    'listForCampaign is null for a campaign outside the org (=> 404)',
    () async {
      final list = await repo.listForCampaign(
        'camp-1',
        organizationId: 'someone-else',
      );
      expect(list, isNull);
    },
  );

  test('start flips UPCOMING -> ACTIVE and writes an audit row', () async {
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-1',
      venue: 'BMD Training Center, Hall A',
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
    );
    final r = await repo.apply(
      SessionAction.start,
      sessionId: 's-1',
      organizationId: org,
      actorId: 'user-1',
    );
    expect(r.outcome, SessionOutcome.applied);
    expect(r.view!.status, SessionStatus.active);

    final audit = await db.execute(
      "SELECT action FROM audit_events WHERE resource_id = 's-1'",
    );
    expect(audit.map((x) => row(x)['action']), contains('session.started'));
  });

  test(
    'start again on an ACTIVE session is an idempotent no-op (200)',
    () async {
      await seedCampaignSession(
        db,
        campaignId: 'camp-1',
        id: 's-1',
        venue: 'BMD Training Center, Hall A',
        startAt: DateTime.utc(2026, 9, 1, 9),
        capacity: 60,
        status: 'ACTIVE',
      );
      final r = await repo.apply(
        SessionAction.start,
        sessionId: 's-1',
        organizationId: org,
        actorId: 'user-1',
      );
      expect(r.outcome, SessionOutcome.idempotentNoop);
      expect(r.view!.status, SessionStatus.active);
    },
  );

  test('start on a CAPTURE_CLOSED session is an invalid transition', () async {
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-1',
      venue: 'BMD Training Center, Hall A',
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
      status: 'CAPTURE_CLOSED',
    );
    final r = await repo.apply(
      SessionAction.start,
      sessionId: 's-1',
      organizationId: org,
      actorId: 'user-1',
    );
    expect(r.outcome, SessionOutcome.invalidTransition);
    expect(r.currentStatus, SessionStatus.captureClosed);
  });

  test('start on a startable session that is not ready => notReady', () async {
    // No venue => not ready, even though UPCOMING is a legal start state.
    await seedCampaignSession(
      db,
      campaignId: 'camp-1',
      id: 's-1',
      venue: null,
      startAt: DateTime.utc(2026, 9, 1, 9),
      capacity: 60,
    );
    final r = await repo.apply(
      SessionAction.start,
      sessionId: 's-1',
      organizationId: org,
      actorId: 'user-1',
    );
    expect(r.outcome, SessionOutcome.notReady);
  });

  test('apply on an unknown / cross-org session => notFound', () async {
    final missing = await repo.apply(
      SessionAction.start,
      sessionId: 'nope',
      organizationId: org,
      actorId: 'user-1',
    );
    expect(missing.outcome, SessionOutcome.notFound);
  });

  test(
    'two concurrent starts: exactly one applies, the other is a no-op',
    () async {
      await seedCampaignSession(
        db,
        campaignId: 'camp-1',
        id: 's-1',
        venue: 'BMD Training Center, Hall A',
        startAt: DateTime.utc(2026, 9, 1, 9),
        capacity: 60,
      );
      final results = await Future.wait([
        repo.apply(
          SessionAction.start,
          sessionId: 's-1',
          organizationId: org,
          actorId: 'user-1',
        ),
        repo.apply(
          SessionAction.start,
          sessionId: 's-1',
          organizationId: org,
          actorId: 'user-1',
        ),
      ]);
      final outcomes = results.map((r) => r.outcome).toList();
      expect(
        outcomes.where((o) => o == SessionOutcome.applied).length,
        1,
        reason: 'the status CAS must let exactly one writer win',
      );
      // The loser is never a second write; it observes ACTIVE as a no-op.
      expect(
        outcomes.where((o) => o == SessionOutcome.idempotentNoop).length,
        1,
      );
    },
  );

  test(
    'completeSessionsForCampaign flips non-terminal sessions to COMPLETED',
    () async {
      await seedCampaignSession(
        db,
        campaignId: 'camp-1',
        id: 's-active',
        venue: 'BMD Training Center, Hall A',
        startAt: DateTime.utc(2026, 9, 1, 9),
        capacity: 60,
        status: 'ACTIVE',
      );
      await seedCampaignSession(
        db,
        campaignId: 'camp-1',
        id: 's-closed',
        venue: 'BMD Training Center, Hall A',
        startAt: DateTime.utc(2026, 9, 1, 9),
        capacity: 60,
        status: 'CAPTURE_CLOSED',
      );
      await repo.completeSessionsForCampaign('camp-1');
      final rows = await db.execute(
        "SELECT id, status FROM campaign_sessions WHERE campaign_id = 'camp-1'",
      );
      final byId = {for (final r in rows) row(r)['id']: row(r)['status']};
      expect(byId['s-active'], 'COMPLETED');
      expect(
        byId['s-closed'],
        'CAPTURE_CLOSED',
        reason: 'already-terminal sessions are left untouched',
      );
    },
  );
}
