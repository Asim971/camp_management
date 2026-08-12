import 'dart:convert';

import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:campaign_service/src/participant/participant_repo.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late ParticipantRepo repo;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1/terr-1/user-1
    // A second org whose rows must never leak into org-1's results.
    await seedOrganizationWithUser(
      db,
      orgId: 'org-2',
      territoryId: 'terr-2',
      userId: 'user-9',
      username: 'other',
    );
    repo = ParticipantRepo(db);
  });
  tearDown(() async => db.close());

  group('search', () {
    setUp(() async {
      await seedCarpenter(db, id: 'c-1'); // Md. Karim, ...4821
      await seedCarpenter(
        db,
        id: 'c-2',
        name: 'Karim Uddin',
        phone: '+8801700007734',
        displayCode: 'CARP-00007734',
      );
      await seedCarpenter(
        db,
        id: 'c-foreign',
        name: 'Md. Karim',
        organizationId: 'org-2',
        territoryId: 'terr-2',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
    });

    test('matches name case-insensitively, org-scoped', () async {
      final hits = await repo.search(organizationId: 'org-1', q: 'karim');
      expect(
        hits.map((c) => c.id).toSet(),
        {'c-1', 'c-2'},
        reason: 'c-foreign has the same name and must not appear',
      );
    });

    test('matches a phone suffix', () async {
      final hits = await repo.search(organizationId: 'org-1', q: '4821');
      expect(hits.map((c) => c.id), ['c-1']);
    });

    test('matches a display code fragment', () async {
      final hits = await repo.search(organizationId: 'org-1', q: '7734');
      expect(hits.map((c) => c.id), contains('c-2'));
    });

    test("q='%%' is a literal two-character probe, not a wildcard-only "
        'pattern: it must match nothing, not every row', () async {
      final hits = await repo.search(organizationId: 'org-1', q: '%%');
      expect(
        hits,
        isEmpty,
        reason:
            'unescaped, %% would ILIKE-match every row and defeat the '
            "route's 2-character minimum-length enumeration guard",
      );
    });

    test(
      'a literal underscore in q matches only names containing it, not '
      'every single character (ILIKE `_` is a single-char wildcard)',
      () async {
        await seedCarpenter(
          db,
          id: 'c-underscore',
          name: 'Under_score Person',
          phone: '+8801700005555',
          displayCode: 'CARP-00005555',
        );
        final hits = await repo.search(organizationId: 'org-1', q: '_');
        expect(hits.map((c) => c.id), ['c-underscore']);
      },
    );

    test('the wire shape masks and never carries the raw phone', () async {
      final hits = await repo.search(organizationId: 'org-1', q: 'karim');
      for (final c in hits) {
        final json = c.toWireJson();
        expect(json['displayId'], matches(RegExp(r'^CARP-••\d{4}$')));
        expect(json['phoneSuffix'], matches(RegExp(r'^\d{4}$')));
        expect(json['territory'], 'Territory');
        expect(json['syncStatus'], 'LOCAL_ONLY');
        expect(
          json.containsKey('attendanceState'),
          isFalse,
          reason: 'sub-project 4 owns that vocabulary (spec 2a.D4)',
        );
        expect(
          jsonEncode(json),
          isNot(contains('+880')),
          reason: 'raw phone must never appear anywhere in the wire JSON',
        );
      }
    });
  });

  group('register', () {
    setUp(() async {
      await seedCampaign(db, id: 'camp-1', territoryIds: const ['terr-1']);
      await seedCarpenter(db, id: 'c-1');
      await seedCarpenter(
        db,
        id: 'c-prov',
        name: 'Provisional Person',
        phone: '+8801700001111',
        displayCode: 'CARP-00001111',
        source: 'PROFILE_REQUEST',
        syncStatus: 'PENDING_PROFILE_SYNC',
      );
    });

    test('registers, counts already-registered on repeat, and derives '
        'PENDING_PROFILE_SYNC from the carpenter', () async {
      final first = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1', 'c-prov'],
        registeredBy: 'user-1',
      );
      expect((registered: 2, alreadyRegistered: 0), first);

      final again = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1', 'c-prov'],
        registeredBy: 'user-1',
      );
      expect((registered: 0, alreadyRegistered: 2), again);

      final statuses = await db.execute(
        'SELECT carpenter_id, status FROM registrations ORDER BY carpenter_id',
      );
      final byId = {
        for (final r in statuses.map(row))
          r['carpenter_id']! as String: r['status']! as String,
      };
      expect(byId['c-1'], 'REGISTERED');
      expect(byId['c-prov'], 'PENDING_PROFILE_SYNC');
    });

    test('a cross-org carpenter id is UNKNOWN_CARPENTER, and its details '
        'name the offending ids without any PII', () async {
      await seedCarpenter(
        db,
        id: 'c-foreign',
        organizationId: 'org-2',
        territoryId: 'terr-2',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
      await expectLater(
        repo.register(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          carpenterIds: ['c-1', 'c-foreign'],
          registeredBy: 'user-1',
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code.wireValue, 'code', 'UNKNOWN_CARPENTER')
              .having((e) => e.details?['carpenterIds'], 'offending ids', [
                'c-foreign',
              ]),
        ),
      );
      final rows = await db.execute('SELECT 1 FROM registrations');
      expect(
        rows,
        isEmpty,
        reason: 'a partially-valid batch must register NOTHING',
      );
    });

    test('a cross-org campaign is null (route answers 404, D7)', () async {
      await seedCampaign(
        db,
        id: 'camp-foreign',
        organizationId: 'org-2',
        ownerId: 'user-9',
      );
      final result = await repo.register(
        campaignId: 'camp-foreign',
        organizationId: 'org-1',
        carpenterIds: ['c-1'],
        registeredBy: 'user-1',
      );
      expect(result, isNull);
    });

    test('writes an audit row with the correlation id', () async {
      await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: ['c-1'],
        registeredBy: 'user-1',
        correlationId: 'trace-123',
      );
      final audit = await db.execute(
        "SELECT correlation_id, payload FROM audit_events "
        "WHERE action = 'registration.create'",
      );
      expect(row(audit.single)['correlation_id'], 'trace-123');
    });

    test(
      'duplicate ids in one call are deduplicated, not double-counted',
      () async {
        final result = await repo.register(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          carpenterIds: ['c-1', 'c-1'],
          registeredBy: 'user-1',
        );
        // Before the fix: the INSERT ... SELECT produced one row per matching
        // carpenter ROW (one row for 'c-1', since the FROM clause has no
        // duplicate rows to match a duplicate id against), so `inserted` was 1
        // but `carpenterIds.length` was 2 — reporting c-1 as simultaneously
        // freshly-registered AND already-registered.
        expect(result, (registered: 1, alreadyRegistered: 0));

        final audit = await db.execute(
          "SELECT payload FROM audit_events WHERE action = 'registration.create'",
        );
        expect(
          row(audit.single)['payload'],
          {'carpenterCount': 1, 'registered': 1},
          reason:
              'the audit payload must record the deduped count, not the '
              "caller's raw (possibly repeated) list length",
        );
      },
    );
  });

  group('createProfileRequest', () {
    setUp(() async {
      await seedCampaign(db, id: 'camp-1');
    });

    test(
      'creates a provisional carpenter and the request in one shot',
      () async {
        final result = await repo.createProfileRequest(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          name: 'New Person',
          phone: '+8801711112222',
          requestedBy: 'user-1',
          correlationId: 'trace-9',
        );
        expect(result, isNotNull);
        final carpenter = result!.carpenter;
        expect(carpenter.syncStatus, 'PENDING_PROFILE_SYNC');
        expect(
          carpenter.toWireJson()['displayId'],
          matches(RegExp(r'^CARP-••\d{4}$')),
        );

        final stored = await db.execute(
          'SELECT source, sync_status FROM carpenters WHERE id = @id',
          params: {'id': carpenter.id},
        );
        expect(row(stored.single)['source'], 'PROFILE_REQUEST');

        final request = await db.execute(
          'SELECT status FROM profile_requests WHERE id = @id',
          params: {'id': result.requestId},
        );
        expect(row(request.single)['status'], 'PENDING');
      },
    );

    test('the provisional carpenter is immediately searchable and '
        'registrable', () async {
      final created = await repo.createProfileRequest(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        name: 'Same Visit',
        phone: '+8801733334444',
        requestedBy: 'user-1',
      );
      final hits = await repo.search(organizationId: 'org-1', q: 'Same Vi');
      expect(hits.map((c) => c.id), contains(created!.carpenter.id));

      final reg = await repo.register(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        carpenterIds: [created.carpenter.id],
        registeredBy: 'user-1',
      );
      expect(reg, (registered: 1, alreadyRegistered: 0));
    });

    test('a cross-org campaign is null', () async {
      final result = await repo.createProfileRequest(
        campaignId: 'nope',
        organizationId: 'org-1',
        name: 'X Y',
        phone: '+8801700000000',
        requestedBy: 'user-1',
      );
      expect(result, isNull);
    });
  });

  group('rosterForSession', () {
    test('returns the campaign roster for an in-org session, null for an '
        'unknown one', () async {
      await seedCampaign(db, id: 'camp-1');
      await seedCampaignSession(db, id: 'sess-1', campaignId: 'camp-1');
      await seedCarpenter(db, id: 'c-1');
      await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-1');

      final roster = await repo.rosterForSession(
        'sess-1',
        organizationId: 'org-1',
      );
      expect(roster, isNotNull);
      expect(roster!.map((c) => c.id), ['c-1']);

      expect(
        await repo.rosterForSession('sess-1', organizationId: 'org-2'),
        isNull,
        reason: 'out-of-scope session must be indistinguishable from absent',
      );
      expect(
        await repo.rosterForSession('missing', organizationId: 'org-1'),
        isNull,
      );
    });
  });
}
