import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

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

    await expectLater(migrator.applyPending(), throwsA(isA<Exception>()));

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
          throw Exception('simulated crash between DDL and version insert');
        }
      },
    );

    await expectLater(migrator.applyPending(), throwsA(isA<Exception>()));

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
}
