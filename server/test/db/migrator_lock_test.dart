import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:test/test.dart';

import '../support/test_db.dart';

void main() {
  test('two migrators on separate connections apply every migration exactly '
      'once between them', () async {
    final a = await freshDb();
    // A second REAL connection: pg_advisory_xact_lock serialises across
    // connections, so both migrators sharing one Db would test nothing.
    final b = await Db.open(testDatabaseUrl);

    try {
      final results = await Future.wait([
        Migrator(a).applyPending(),
        Migrator(b).applyPending(),
      ]);

      final total = results[0].length + results[1].length;
      final rows = await a.execute('SELECT id FROM schema_migrations');
      expect(
        total,
        rows.length,
        reason:
            'every applied id was applied by exactly one migrator: the loser '
            'must skip (in-tx recheck), not fail on a duplicate insert and '
            'not double-apply',
      );
      expect(
        {...results[0], ...results[1]}.length,
        total,
        reason: 'no id may appear in both applied lists',
      );
    } finally {
      await a.close();
      await b.close();
    }
  });
}
