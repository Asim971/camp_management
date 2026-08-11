import 'dart:convert';

import 'package:campaign_service/src/auth/middleware.dart';
import 'package:campaign_service/src/auth/tokens.dart';
import 'package:campaign_service/src/campaign/campaign_repo.dart';
import 'package:campaign_service/src/campaign/campaign_routes.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/infra/correlation.dart';
import 'package:campaign_service/src/infra/error_envelope.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

void main() {
  late Db db;
  late TokenService tokens;
  late Handler handler;
  late String token;
  late String approverToken;
  var seq = 0;

  final config = ServerConfig.fromEnvironment({
    'DATABASE_URL': testDatabaseUrl,
    'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
  });

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    // user-1: the creator/owner, campaign_create only.
    await seedOrganizationWithUser(
      db,
      userId: 'user-1',
      username: 'creator',
      roles: const ['campaign_creator'],
    );
    // user-2: the reviewer, campaign_approve only — never the owner of any
    // campaign in this file, so SoD never blocks these tests (sod_test.dart
    // covers that separately).
    await seedOrganizationWithUser(
      db,
      userId: 'user-2',
      username: 'approver',
      roles: const ['marketing_approver'],
    );
    tokens = TokenService(db: db, config: config);
    token = (await tokens.issueFor('user-1')).accessToken;
    approverToken = (await tokens.issueFor('user-2')).accessToken;
    handler = const Pipeline()
        .addMiddleware(correlation())
        .addMiddleware(errorEnvelope())
        .addMiddleware(authenticate(db: db, tokens: tokens))
        .addHandler(campaignRouter(db: db, repo: CampaignRepo(db)).call);
  });
  tearDown(() async => db.close());

  String nextKey(String label) => '$label-${seq++}';

  Future<Response> post(
    Handler handler,
    String pathAndQuery,
    Map<String, Object?> body,
    String bearer, {
    String? key,
    String? correlationId,
  }) async => handler(
    Request(
      'POST',
      Uri.parse('http://localhost$pathAndQuery'),
      body: jsonEncode(body),
      headers: {
        'authorization': 'Bearer $bearer',
        'content-type': 'application/json',
        if (key != null) 'Idempotency-Key': key,
        if (correlationId != null) 'X-Correlation-Id': correlationId,
      },
    ),
  );

  Future<Response> put(
    Handler handler,
    String pathAndQuery,
    Map<String, Object?> body,
    String bearer, {
    String? correlationId,
  }) async => handler(
    Request(
      'PUT',
      Uri.parse('http://localhost$pathAndQuery'),
      body: jsonEncode(body),
      headers: {
        'authorization': 'Bearer $bearer',
        'content-type': 'application/json',
        if (correlationId != null) 'X-Correlation-Id': correlationId,
      },
    ),
  );

  Future<Response> get(
    Handler handler,
    String pathAndQuery,
    String bearer,
  ) async => handler(
    Request(
      'GET',
      Uri.parse('http://localhost$pathAndQuery'),
      headers: {'authorization': 'Bearer $bearer'},
    ),
  );

  // `jsonDecode` returns `dynamic`; every caller below casts immediately so
  // indexing the decoded body is never itself a dynamic call
  // (avoid_dynamic_calls, enabled in analysis_options.yaml).
  Future<Map<String, Object?>> decodeBody(Response res) async =>
      jsonDecode(await res.readAsString()) as Map<String, Object?>;

  Future<Object?> errorCodeOf(Response res) async =>
      ((await decodeBody(res))['error'] as Map<String, Object?>)['code'];

  // Every field validateForSubmit checks is present and legal, so a test can
  // submit right after create without first fixing the draft up. A single
  // session, well inside its own capacity, so no critical warning is raised
  // by accident — pendingCampaignWithWarnings below overrides target/
  // sessions specifically to raise one.
  Map<String, Object?> draftBody({
    String name = 'Test Campaign',
    String type = 'ATTENDANCE',
    String? objective = 'Reach carpenters',
    List<String> territoryIds = const ['terr-1'],
    int target = 50,
    String? budgetReference = 'BUD-1',
    String? approverId = 'user-2',
    bool geofenceEnabled = false,
    List<Map<String, Object?>>? sessions,
  }) => {
    'name': name,
    'type': type,
    'objective': objective,
    'territoryIds': territoryIds,
    'target': target,
    'budgetReference': budgetReference,
    'approverId': approverId,
    'geofenceEnabled': geofenceEnabled,
    'sessions':
        sessions ??
        [
          {
            'venue': 'Hall A',
            'capacity': 100,
            'startAt': '2026-09-01T09:00:00.000Z',
            'endAt': '2026-09-01T12:00:00.000Z',
          },
        ],
  };

  Future<String> createDraft(
    Handler handler,
    String bearer, {
    String name = 'Test Campaign',
  }) async {
    final res = await post(
      handler,
      '/campaigns',
      draftBody(name: name),
      bearer,
      key: nextKey('create'),
    );
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    return body['id']! as String;
  }

  // Drives the real create -> submit flow through the handler (not a direct
  // INSERT) so the resulting row carries exactly the version (2) and audit
  // trail a genuine submission produces — the same reason approvedCampaign
  // below builds on this instead of seeding PENDING_APPROVAL by hand.
  Future<String> pendingCampaign(
    Db db,
    Handler handler, {
    String ownerId = 'user-1',
  }) async {
    final ownerToken = (await tokens.issueFor(ownerId)).accessToken;
    final id = await createDraft(handler, ownerToken);
    await post(
      handler,
      '/campaigns/$id/submit',
      {'version': 1},
      ownerToken,
      key: nextKey('submit'),
    );
    return id;
  }

  Future<String> approvedCampaign(
    Db db,
    Handler handler, {
    String ownerId = 'user-1',
    String reviewerId = 'user-2',
  }) async {
    final id = await pendingCampaign(db, handler, ownerId: ownerId);
    final reviewerToken = (await tokens.issueFor(reviewerId)).accessToken;
    await post(
      handler,
      '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2, 'acknowledgedWarnings': <String>[]},
      reviewerToken,
      key: nextKey('approve'),
    );
    return id;
  }

  // Target (1000) deliberately exceeds the one session's capacity (50):
  // deriveCriticalWarnings' one rule (campaign_repo.dart) fires on exactly
  // this shape.
  Future<String> pendingCampaignWithWarnings(
    Db db,
    Handler handler, {
    String ownerId = 'user-1',
  }) async {
    final ownerToken = (await tokens.issueFor(ownerId)).accessToken;
    final body = draftBody(
      target: 1000,
      sessions: [
        {
          'venue': 'Small Hall',
          'capacity': 50,
          'startAt': '2026-09-01T09:00:00.000Z',
          'endAt': '2026-09-01T12:00:00.000Z',
        },
      ],
    );
    final createRes = await post(
      handler,
      '/campaigns',
      body,
      ownerToken,
      key: nextKey('warn-create'),
    );
    final id =
        (jsonDecode(await createRes.readAsString())
                as Map<String, Object?>)['id']!
            as String;
    await post(
      handler,
      '/campaigns/$id/submit',
      {'version': 1},
      ownerToken,
      key: nextKey('warn-submit'),
    );
    return id;
  }

  test('create returns a DRAFT with version 1', () async {
    final res = await post(
      handler,
      '/campaigns',
      draftBody(),
      token,
      key: 'k1',
    );
    expect(res.statusCode, 200);
    final body = jsonDecode(await res.readAsString()) as Map<String, Object?>;
    expect(body['status'], 'DRAFT');
    expect(body['version'], 1);
  });

  // "when submit is double-tapped or retried, then ONE Pending approval
  // transition and audit event result"
  test(
    'a double-tapped submit produces one transition and one audit event',
    () async {
      final id = await createDraft(handler, token);
      final first = await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: 'submit-1',
      );
      final second = await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: 'submit-1',
      );

      expect(first.statusCode, 200);
      expect(
        await second.readAsString(),
        await first.readAsString(),
        reason: 'the replay must be byte-identical, not a fresh 409',
      );

      final audits = await db.execute(
        "SELECT id FROM audit_events WHERE action = 'campaign.submitted' "
        'AND resource_id = @id',
        params: {'id': id},
      );
      expect(audits.length, 1);
    },
  );

  // Isolates the version clause from the status machine on purpose: a
  // concurrent PUT bumps the version but leaves the campaign DRAFT (still
  // legally submittable), so the only thing wrong with the stale submit
  // below is its version — not its status. See Step 4's probe in
  // task-9-report.md for why the brief's literal "submit twice in a row"
  // shape cannot exercise the UPDATE's version clause in isolation: the
  // first submit always transitions DRAFT -> PENDING_APPROVAL regardless of
  // whether the clause is present, so a second submit attempt is rejected
  // by the status machine (CAMPAIGN_INVALID_TRANSITION) before the version
  // clause is ever consulted, in both the correct and the broken build.
  test(
    'submitting with a stale version is 409 CONFLICT_STALE_VERSION',
    () async {
      final id = await createDraft(handler, token);
      final putRes = await put(handler, '/campaigns/$id', {
        ...draftBody(),
        'version': 1,
      }, token);
      expect(
        putRes.statusCode,
        200,
        reason: 'the setup edit must itself succeed',
      );

      final res = await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: nextKey('stale-submit'),
      );

      expect(res.statusCode, 409);
      expect(await errorCodeOf(res), 'CONFLICT_STALE_VERSION');
    },
  );

  test(
    'submitting an already-approved campaign is 409 INVALID_TRANSITION',
    () async {
      final id = await approvedCampaign(db, handler);
      // The owner re-submitting their own already-approved campaign — submit
      // is gated by campaign_create (the owner's permission), not
      // campaign_approve, so this uses `token`, not `approverToken`.
      final res = await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: 'k-c',
      );
      expect(await errorCodeOf(res), 'CAMPAIGN_INVALID_TRANSITION');
    },
  );

  // "when submitted without reason, then no transition occurs and a
  // specific error is shown"
  test('return without a reason leaves the status untouched', () async {
    final id = await pendingCampaign(db, handler);
    final res = await post(
      handler,
      '/campaigns/$id/decision',
      {'decision': 'RETURN_FOR_CORRECTION', 'version': 2},
      approverToken,
      key: 'k-d',
    );

    expect(res.statusCode, 422);
    expect(await errorCodeOf(res), 'DECISION_REASON_REQUIRED');

    final after = await get(handler, '/campaigns/$id', approverToken);
    expect(
      (await decodeBody(after))['status'],
      'PENDING_APPROVAL',
      reason: 'a rejected decision must not half-apply',
    );
  });

  test('approve with unacknowledged critical warnings is 422', () async {
    final id = await pendingCampaignWithWarnings(db, handler);
    final res = await post(
      handler,
      '/campaigns/$id/decision',
      {'decision': 'APPROVE', 'version': 2, 'acknowledgedWarnings': <String>[]},
      approverToken,
      key: 'k-e',
    );

    expect(await errorCodeOf(res), 'WARNINGS_UNACKNOWLEDGED');
  });

  test(
    'a decision records reviewer, reason, acknowledgements, version and trace',
    () async {
      final id = await pendingCampaign(db, handler);
      await post(
        handler,
        '/campaigns/$id/decision',
        {
          'decision': 'APPROVE',
          'version': 2,
          'acknowledgedWarnings': ['w1'],
        },
        approverToken,
        key: 'k-f',
        correlationId: 'trace-abc',
      );

      final res = await db.execute(
        'SELECT * FROM campaign_decisions WHERE campaign_id = @id',
        params: {'id': id},
      );
      final d = row(res.single);
      expect(d['reviewer_id'], 'user-2');
      expect(d['decision'], 'APPROVE');
      expect(d['version_at_decision'], 2);
      expect(d['correlation_id'], 'trace-abc');
      // jsonb comes back from `postgres` 3.x ALREADY DECODED (the codec runs
      // jsonDecode for you — verified in binary_codec.dart). Casting to
      // String and re-decoding throws.
      expect(d['acknowledged_warnings'], ['w1']);
    },
  );

  test(
    'submit stores an immutable snapshot for the changed-field diff',
    () async {
      final id = await createDraft(handler, token, name: 'Original');
      await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: 'k-g',
      );

      final res = await db.execute(
        'SELECT snapshot, version FROM campaign_submissions '
        'WHERE campaign_id = @id',
        params: {'id': id},
      );
      // jsonb is already decoded by the driver — see the note in the decision
      // test above. Cast the object, do not jsonDecode a String.
      final snap = (row(res.single)['snapshot']! as Map)
          .cast<String, Object?>();
      expect(snap['name'], 'Original');
    },
  );

  test(
    'submit revalidates server-side and returns field-keyed errors',
    () async {
      // A draft created directly in the database, bypassing the wizard, with
      // overlapping sessions — exactly what a malicious or stale client sends.
      final id = await seedInvalidDraft(db);
      final res = await post(
        handler,
        '/campaigns/$id/submit',
        {'version': 1},
        token,
        key: 'k-h',
      );

      expect(res.statusCode, 422);
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      expect(error['code'], 'CAMPAIGN_VALIDATION_FAILED');
      final fields = (error['details']! as Map)['fields']! as List;
      expect(fields, isNotEmpty);
      expect((fields.first as Map)['field'], isA<String>());
    },
  );

  // --- I1: malformed field types are 400, never a 500 --------------------
  //
  // `_draftInputFromBody`'s typed `_*Field` helpers (campaign_routes.dart)
  // are what turn each of these into a clean, field-named 400 instead of an
  // unhandled TypeError/FormatException reaching the envelope's catch-all.

  test('a wrong-typed target is 400 BAD_REQUEST, not a 500', () async {
    final res = await post(
      handler,
      '/campaigns',
      {...draftBody(), 'target': '50'},
      token,
      key: nextKey('bad-target'),
    );
    expect(res.statusCode, 400);
    expect(await errorCodeOf(res), 'BAD_REQUEST');
  });

  test('a non-array sessions is 400 BAD_REQUEST, not a 500', () async {
    final res = await post(
      handler,
      '/campaigns',
      {...draftBody(), 'sessions': <String, Object?>{}},
      token,
      key: nextKey('bad-sessions'),
    );
    expect(res.statusCode, 400);
    expect(await errorCodeOf(res), 'BAD_REQUEST');
  });

  test(
    'an unparseable session startAt is 400 BAD_REQUEST, not a 500',
    () async {
      final res = await post(
        handler,
        '/campaigns',
        {
          ...draftBody(),
          'sessions': [
            {
              'venue': 'Hall A',
              'capacity': 100,
              'startAt': 'nope',
              'endAt': '2026-09-01T12:00:00.000Z',
            },
          ],
        },
        token,
        key: nextKey('bad-startAt'),
      );
      expect(res.statusCode, 400);
      expect(await errorCodeOf(res), 'BAD_REQUEST');
    },
  );

  test(
    'a non-string element in territoryIds is 400 BAD_REQUEST, not a 500',
    () async {
      final res = await post(
        handler,
        '/campaigns',
        {
          ...draftBody(),
          'territoryIds': [1],
        },
        token,
        key: nextKey('bad-territoryIds'),
      );
      expect(res.statusCode, 400);
      expect(await errorCodeOf(res), 'BAD_REQUEST');
    },
  );

  // --- I2: territoryIds/approverId are org-scoped, not just FK-checked ---

  group('cross-org and nonexistent references on write', () {
    setUp(() async {
      // A second organization with its own territory and a staff user who
      // never appears in this file's default org — exactly what a
      // campaign_create holder in org-1 should not be able to name.
      await seedOrganizationWithUser(
        db,
        orgId: 'org-2',
        territoryId: 'terr-2',
        userId: 'user-foreign',
        username: 'foreign',
        roles: const [],
      );
    });

    test('a foreign-organization territory is 422, not a 500', () async {
      final res = await post(
        handler,
        '/campaigns',
        {
          ...draftBody(),
          'territoryIds': ['terr-2'],
        },
        token,
        key: nextKey('foreign-territory'),
      );
      expect(res.statusCode, 422);
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      expect(error['code'], 'CAMPAIGN_VALIDATION_FAILED');
      final fields = (error['details']! as Map)['fields']! as List;
      expect(
        fields.map((f) => (f as Map<String, Object?>)['field']),
        contains('territoryIds'),
      );
    });

    test('a foreign-organization approver is 422, not a 500', () async {
      final res = await post(
        handler,
        '/campaigns',
        {...draftBody(), 'approverId': 'user-foreign'},
        token,
        key: nextKey('foreign-approver'),
      );
      expect(res.statusCode, 422);
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      expect(error['code'], 'CAMPAIGN_VALIDATION_FAILED');
      final fields = (error['details']! as Map)['fields']! as List;
      expect(
        fields.map((f) => (f as Map<String, Object?>)['field']),
        contains('approverId'),
      );
    });

    test('a nonexistent territory id is 422, not a raw FK 500', () async {
      final res = await post(
        handler,
        '/campaigns',
        {
          ...draftBody(),
          'territoryIds': ['no-such-territory'],
        },
        token,
        key: nextKey('nonexistent-territory'),
      );
      expect(res.statusCode, 422);
      expect(await errorCodeOf(res), 'CAMPAIGN_VALIDATION_FAILED');
    });

    test('a nonexistent approver id is 422, not a raw FK 500', () async {
      final res = await post(
        handler,
        '/campaigns',
        {...draftBody(), 'approverId': 'no-such-user'},
        token,
        key: nextKey('nonexistent-approver'),
      );
      expect(res.statusCode, 422);
      expect(await errorCodeOf(res), 'CAMPAIGN_VALIDATION_FAILED');
    });
  });

  // --- I3: the positive warning-acknowledgement path, and the wire string
  // it depends on, are both pinned -----------------------------------------

  test('approve with the exact acknowledged warning succeeds', () async {
    final id = await pendingCampaignWithWarnings(db, handler);
    final res = await post(
      handler,
      '/campaigns/$id/decision',
      {
        'decision': 'APPROVE',
        'version': 2,
        'acknowledgedWarnings': ['TARGET_EXCEEDS_SESSION_CAPACITY'],
      },
      approverToken,
      key: nextKey('ack-warning'),
    );
    expect(res.statusCode, 200);
    expect((await decodeBody(res))['status'], 'APPROVED');
  });

  test(
    'the unacknowledged-warnings error pins the exact wire identifier',
    () async {
      final id = await pendingCampaignWithWarnings(db, handler);
      final res = await post(
        handler,
        '/campaigns/$id/decision',
        {
          'decision': 'APPROVE',
          'version': 2,
          'acknowledgedWarnings': <String>[],
        },
        approverToken,
        key: nextKey('unpinned-warning'),
      );
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      final warnings = (error['details']! as Map)['warnings']! as List;
      expect(
        warnings,
        ['TARGET_EXCEEDS_SESSION_CAPACITY'],
        reason:
            'a rename of this identifier must fail this test, not pass '
            'silently while making every warned campaign unapprovable',
      );
    },
  );

  // --- I4: updateDraft's own governance rules, previously only exercised
  // via the happy-path setup edit in the stale-version test --------------

  test(
    'PUT on a non-editable (PENDING_APPROVAL) campaign is 409 INVALID_TRANSITION',
    () async {
      final id = await pendingCampaign(db, handler);
      final res = await put(handler, '/campaigns/$id', {
        ...draftBody(),
        'version': 2,
      }, token);
      expect(res.statusCode, 409);
      final error = (await decodeBody(res))['error']! as Map<String, Object?>;
      expect(error['code'], 'CAMPAIGN_INVALID_TRANSITION');
      expect((error['details']! as Map)['currentStatus'], 'PENDING_APPROVAL');
    },
  );

  test('PUT with a stale version is 409 CONFLICT_STALE_VERSION', () async {
    final id = await createDraft(handler, token);
    final firstEdit = await put(handler, '/campaigns/$id', {
      ...draftBody(name: 'First edit'),
      'version': 1,
    }, token);
    expect(firstEdit.statusCode, 200, reason: 'the first edit must succeed');

    // Still using the now-stale version 1.
    final res = await put(handler, '/campaigns/$id', {
      ...draftBody(name: 'Second, stale edit'),
      'version': 1,
    }, token);
    expect(res.statusCode, 409);
    expect(await errorCodeOf(res), 'CONFLICT_STALE_VERSION');
  });

  // --- I5: correlation is stamped on every write's audit row, not just
  // decide's -----------------------------------------------------------

  Future<String?> auditCorrelationFor(String action, String resourceId) async {
    final res = await db.execute(
      'SELECT correlation_id FROM audit_events '
      'WHERE action = @action AND resource_id = @id',
      params: {'action': action, 'id': resourceId},
    );
    return row(res.single)['correlation_id'] as String?;
  }

  test('create stamps its audit row with the request correlation id', () async {
    final res = await post(
      handler,
      '/campaigns',
      draftBody(),
      token,
      key: nextKey('corr-create'),
      correlationId: 'trace-create',
    );
    final id = (await decodeBody(res))['id']! as String;
    expect(await auditCorrelationFor('campaign.created', id), 'trace-create');
  });

  test('update stamps its audit row with the request correlation id', () async {
    final id = await createDraft(handler, token);
    await put(
      handler,
      '/campaigns/$id',
      {...draftBody(), 'version': 1},
      token,
      correlationId: 'trace-update',
    );
    expect(await auditCorrelationFor('campaign.updated', id), 'trace-update');
  });

  test('submit stamps its audit row with the request correlation id', () async {
    final id = await createDraft(handler, token);
    await post(
      handler,
      '/campaigns/$id/submit',
      {'version': 1},
      token,
      key: nextKey('corr-submit'),
      correlationId: 'trace-submit',
    );
    expect(await auditCorrelationFor('campaign.submitted', id), 'trace-submit');
  });

  test('every write audit row gets a non-null correlation id even when the '
      'caller supplies none — correlation() always mints one', () async {
    final id = await createDraft(handler, token);
    expect(await auditCorrelationFor('campaign.created', id), isNotNull);
  });

  // --- M11-part rider: an unknown decision wire value is a client error --

  test('an unknown decision value is 400 BAD_REQUEST', () async {
    final id = await pendingCampaign(db, handler);
    final res = await post(
      handler,
      '/campaigns/$id/decision',
      {'decision': 'MAYBE_APPROVE', 'version': 2},
      approverToken,
      key: nextKey('bad-decision'),
    );
    expect(res.statusCode, 400);
    expect(await errorCodeOf(res), 'BAD_REQUEST');
  });
}
