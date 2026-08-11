import 'package:campaign_service/src/app.dart';
import 'package:campaign_service/src/config.dart';
import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support/test_db.dart';

/// Pins both sides of `_authenticateOnlyUnderCampaigns` (app.dart) through
/// the SAME [buildApp] tree the seed-gate and parity tests exercise —
/// nothing here builds a hand-assembled pipeline the way
/// `test/campaign/campaign_read_test.dart` does, because that shape is
/// exactly what let the routing bug this predicate fixes go untested.
///
/// Review finding (F2, Task 11 fix round): the bug's ABSENCE half (an
/// unmatched path with no header falls through to a real 404, not
/// `authenticate`'s 401) already had a dedicated test
/// (`seed_gate_test.dart`'s "seed routes are absent when seeding is
/// disabled"), but its PRESENCE half — a genuine `/campaigns` request is
/// still gated by `authenticate`, not accidentally let through — had none.
/// A regression that widened the path check (e.g. back to matching every
/// path) or narrowed it (matching nothing) would have passed every existing
/// test unnoticed.
ServerConfig _config() => ServerConfig.fromEnvironment({
  'DATABASE_URL': testDatabaseUrl,
  'JWT_SECRET': 'a-secret-at-least-32-characters-long!!',
});

void main() {
  late Db db;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
  });
  tearDown(() async => db.close());

  test(
    'an unauthenticated GET /campaigns is 401 through the real handler tree',
    () async {
      final handler = buildApp(db: db, config: _config());
      final res = await handler(
        Request('GET', Uri.parse('http://localhost/campaigns')),
      );
      expect(
        res.statusCode,
        401,
        reason:
            '/campaigns must still be gated by authenticate() -- the fix for '
            'the unmatched-path-401 bug must not have widened into letting '
            'campaign requests through unauthenticated',
      );
    },
  );

  test(
    'an unmatched path with no Authorization header is a real 404, not 401',
    () async {
      final handler = buildApp(db: db, config: _config());
      final res = await handler(
        Request('GET', Uri.parse('http://localhost/nonexistent')),
      );
      expect(
        res.statusCode,
        404,
        reason:
            'authenticate() must not run for a path campaignRouter does not '
            'own -- otherwise a probe with no token gets 401 instead of the '
            'genuine 404 that lets Cascade relinquish to a later candidate '
            '(seed_gate_test.dart depends on exactly this)',
      );
    },
  );
}
