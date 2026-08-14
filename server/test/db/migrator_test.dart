import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

/// Distinguishable from any [Exception] Postgres itself might throw (a
/// protocol error, a constraint violation, ...), so a test asserting on this
/// specific type cannot be satisfied by the wrong failure landing at the
/// wrong place for the wrong reason.
class _SeamProbeFailure implements Exception {
  const _SeamProbeFailure();

  @override
  String toString() =>
      '_SeamProbeFailure: simulated crash between DDL and version insert';
}

void main() {
  late Db db;

  setUp(() async => db = await freshDb());
  tearDown(() async => db.close());

  test('applies pending migrations in id order and records them', () async {
    final applied = await Migrator(db).applyPending();

    expect(applied, contains('001_foundation'));
    expect(
      applied,
      equals(List<String>.of(applied)..sort()),
      reason: 'ids must be applied in lexical order',
    );

    final res = await db.execute(
      'SELECT id FROM schema_migrations ORDER BY id',
    );
    expect(res.map((r) => row(r)['id']), applied);
  });

  test('is idempotent: a second run applies nothing', () async {
    await Migrator(db).applyPending();
    expect(await Migrator(db).applyPending(), isEmpty);
  });

  // Covers only "a migration whose own DDL text is broken records no version
  // row." It does NOT exercise the DDL/version-row transaction boundary: the
  // bad statement is bundled into the same multi-statement string as the good
  // one, and Postgres's simple query protocol already makes one combined
  // multi-statement Query message atomic on its own, regardless of how
  // applyPending arranges its own transaction around it. See the next test
  // for the probe that actually distinguishes the two arrangements.
  test('a migration with broken DDL text leaves no partial schema and no '
      'version row', () async {
    final migrator = Migrator(
      db,
      extra: const {
        '999_broken':
            'CREATE TABLE half_applied (id TEXT PRIMARY KEY); '
            'SELECT this_function_does_not_exist();',
      },
    );

    // Asserts on the specific server-side error (undefined_function,
    // SQLSTATE 42883) so this test cannot be satisfied by some unrelated
    // Exception — e.g. a protocol-level error thrown before the broken
    // statement was even reached, which would prove nothing about rollback.
    await expectLater(
      migrator.applyPending(),
      throwsA(
        isA<ServerException>().having((e) => e.code, 'SQLSTATE code', '42883'),
      ),
    );

    final tables = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(
      tables.map((r) => row(r)['tablename']).toSet(),
      isNot(contains('half_applied')),
      reason: 'the CREATE TABLE must roll back with the failure',
    );

    final versions = await db.execute('SELECT id FROM schema_migrations');
    expect(versions.map((r) => row(r)['id']), isNot(contains('999_broken')));
  });

  // The actual P0.R5 window: the DDL has already succeeded and the version
  // row has not yet been written. On the client, drift ran each step bare and
  // bumped user_version only after onUpgrade returned, so a kill in exactly
  // this gap left a device durably on the old version with the step's work
  // already committed — and the retry threw out of beforeOpen on EVERY later
  // launch, because re-running the same DDL hit "already exists". This test
  // reaches that gap via the onBeforeVersionInsert seam (test-only; unlike the
  // fixture above, a failure injected here happens BETWEEN the DDL and the
  // insert, not inside the DDL text, so it cannot be swallowed by Postgres's
  // own multi-statement atomicity). If the DDL and the version row do not
  // share one transaction, half_applied survives; if they do, it rolls back
  // with the failure.
  test('a failure between the DDL and the version insert leaves no partial '
      'schema and no version row', () async {
    final migrator = Migrator(
      db,
      extra: const {
        '999_seam': 'CREATE TABLE half_applied (id TEXT PRIMARY KEY)',
      },
      onBeforeVersionInsert: (id) async {
        if (id == '999_seam') {
          throw const _SeamProbeFailure();
        }
      },
    );

    // Asserts on the specific, test-only exception type rather than
    // isA<Exception>() — otherwise this test would also be satisfied by an
    // unrelated Postgres error (a protocol error, a constraint violation)
    // striking at the wrong point for the wrong reason, which proves nothing
    // about whether the DDL and the version insert share a transaction.
    await expectLater(
      migrator.applyPending(),
      throwsA(isA<_SeamProbeFailure>()),
    );

    final tables = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(
      tables.map((r) => row(r)['tablename']).toSet(),
      isNot(contains('half_applied')),
      reason:
          'the DDL must roll back with a failure at the version-insert '
          'seam, proving the two share one transaction',
    );

    final versions = await db.execute('SELECT id FROM schema_migrations');
    expect(versions.map((r) => row(r)['id']), isNot(contains('999_seam')));
  });

  test('the foundation schema creates every table the slice needs', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    final names = res.map((r) => row(r)['tablename']! as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'organizations',
        'territories',
        'staff_users',
        'staff_user_roles',
        'staff_user_territories',
        'refresh_tokens',
        'campaigns',
        'campaign_territories',
        'campaign_sessions',
        'campaign_submissions',
        'campaign_decisions',
        'idempotency_keys',
        'audit_events',
        'app_config',
        'schema_migrations',
        'carpenters',
        'registrations',
        'profile_requests',
        'import_jobs',
        'import_job_rows',
      ]),
    );
  });

  test('SoD defaults to enforced', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT value FROM app_config WHERE key = 'sod.enforced'",
    );
    expect(row(res.single)['value'], 'true');
  });

  test('003_role_check rejects a role outside the client vocabulary', () async {
    await Migrator(db).applyPending();
    await db.execute(
      "INSERT INTO organizations (id, name) VALUES ('o1', 'Org')",
    );
    await db.execute(
      'INSERT INTO staff_users '
      '(id, username, display_name, password_hash, organization_id) '
      "VALUES ('u1', 'u1', 'U', 'x', 'o1')",
    );
    await expectLater(
      db.execute(
        "INSERT INTO staff_user_roles (user_id, role) VALUES ('u1', 'not_a_role')",
      ),
      // 23514 = check_violation. Assert the cause, not just "some exception"
      // (slice-1 Task 3 lesson: a loose matcher accepted the wrong error).
      throwsA(
        isA<ServerException>().having((e) => e.code, 'sqlstate', '23514'),
      ),
    );
    // The whole valid vocabulary still inserts.
    await db.execute(
      "INSERT INTO staff_user_roles (user_id, role) VALUES ('u1', 'admin')",
    );
  });

  test('006 reconciles the session status vocabulary to UPCOMING', () async {
    await Migrator(db).applyPending();

    // The column default is now UPCOMING, so a wizard insert (which sets no
    // status) starts a session in the 3a vocabulary, not the retired PLANNED.
    final def = await db.execute(
      "SELECT column_default FROM information_schema.columns "
      "WHERE table_name = 'campaign_sessions' AND column_name = 'status'",
    );
    expect(
      row(def.single)['column_default'],
      contains('UPCOMING'),
      reason: 'the default must be UPCOMING after 006',
    );

    // No legacy PLANNED rows survive (there are none in a fresh db, but the
    // UPDATE must be present and correct for existing deployments).
    final planned = await db.execute(
      "SELECT count(*) AS n FROM campaign_sessions WHERE status = 'PLANNED'",
    );
    expect(row(planned.single)['n'], 0);
  });

  test('007 creates the attendance and evidence tables', () async {
    await Migrator(db).applyPending();
    final res = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    final names = res.map((r) => row(r)['tablename']! as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'consent_notices',
        'media_objects',
        'attendance',
        'consent_records',
      ]),
    );
  });

  test('008 adds the verification columns and decisions table', () async {
    await Migrator(db).applyPending();
    final cols = await db.execute(
      "SELECT column_name FROM information_schema.columns WHERE table_name = 'attendance'",
    );
    final names = cols.map((r) => row(r)['column_name']! as String).toSet();
    expect(
      names,
      containsAll(<String>[
        'version',
        'assignee_id',
        'machine_band',
        'machine_reference_src',
        'machine_reasons',
      ]),
    );
    final tables = await db.execute(
      "SELECT tablename FROM pg_tables WHERE schemaname = 'public'",
    );
    expect(
      tables.map((r) => row(r)['tablename']),
      contains('verification_decisions'),
    );
  });
}
