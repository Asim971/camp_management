import 'package:meta/meta.dart';
import 'package:postgres/postgres.dart';

import 'migrations/embedded.dart';
import 'pool.dart';

/// Forward-only migration runner.
///
/// Each migration and its schema_migrations row commit in ONE transaction. That
/// ordering is the entire guarantee: writing the version row after the DDL
/// commits is the defect filed as P0.R5 on the client, where a kill between the
/// two left the database durably half-migrated and unopenable on every later
/// launch. Postgres has transactional DDL, so the cure here is structural
/// rather than per-statement idempotency.
///
/// No down-migrations: a failed deploy rolls forward.
class Migrator {
  Migrator(
    this._db, {
    Map<String, String> extra = const {},
    @visibleForTesting this.onBeforeVersionInsert,
  }) : _migrations = {...embeddedMigrations, ...extra};

  final Db _db;
  final Map<String, String> _migrations;

  /// Test-only seam: invoked after a migration's DDL has run and before its
  /// `schema_migrations` row is inserted, both still inside the same
  /// [Db.tx] call. A test that throws here simulates a crash landing exactly
  /// in the P0.R5 window — DDL committed, version row not yet written — and
  /// can assert that the DDL rolls back with it. There is no way to reach
  /// that window from outside the class otherwise: Postgres's simple query
  /// protocol already makes a single multi-statement DDL string atomic on
  /// its own, so a failure injected inside the DDL text can never tell one
  /// arrangement of `applyPending` from the other.
  @visibleForTesting
  final Future<void> Function(String id)? onBeforeVersionInsert;

  Future<List<String>> applyPending() async {
    await _db.execute(
      'CREATE TABLE IF NOT EXISTS schema_migrations ('
      '  id TEXT PRIMARY KEY,'
      '  applied_at TIMESTAMPTZ NOT NULL DEFAULT now()'
      ')',
    );

    final done = (await _db.execute(
      'SELECT id FROM schema_migrations',
    )).map((r) => row(r)['id']! as String).toSet();

    final pending = _migrations.keys.where((id) => !done.contains(id)).toList()
      ..sort();

    final applied = <String>[];
    for (final id in pending) {
      await _db.tx((tx) async {
        // Every statement here goes through `tx`, never `_db` — see Db.tx.
        //
        // Simple query protocol: a migration is a multi-statement DDL script,
        // and the extended (prepared-statement) protocol postgres uses by
        // default rejects a Parse containing more than one command with
        // "cannot insert multiple commands into a prepared statement".
        await tx.execute(_migrations[id]!, queryMode: QueryMode.simple);
        final seam = onBeforeVersionInsert;
        if (seam != null) {
          await seam(id);
        }
        await tx.execute(
          Sql.named('INSERT INTO schema_migrations (id) VALUES (@id)'),
          parameters: {'id': id},
        );
      });
      applied.add(id);
    }
    return applied;
  }
}
