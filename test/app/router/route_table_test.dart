import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/app/router/route_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('routeTable integrity', () {
    test('no path is declared twice', () {
      final paths = routeTable.map((e) => e.path).toList();
      expect(paths.length, paths.toSet().length);
    });

    test('every dev-only path is present in the table', () {
      final paths = routeTable.map((e) => e.path).toSet();
      for (final p in devOnlyPaths) {
        expect(paths, contains(p), reason: '$p is registered but ungoverned');
      }
    });
  });

  group('exhaustiveness: registered routes == table', () {
    // This is the guarantee the epic exists to create. Adding a route without
    // an access decision must fail here rather than silently shipping ungated.
    test('with dev routes enabled, the sets are identical', () {
      final registered = registeredRoutePaths(devRoutesEnabled: true);

      expect(registered, routeTable.map((e) => e.path).toSet());
    });

    test('with dev routes disabled, the set is the table minus dev paths', () {
      final registered = registeredRoutePaths(devRoutesEnabled: false);
      final expected = routeTable
          .map((e) => e.path)
          .toSet()
          .difference(devOnlyPaths);

      expect(registered, expected);
      expect(registered, isNot(contains('/dev')));
      expect(registered, isNot(contains('/gallery')));
    });
  });

  group('accessFor', () {
    test('resolves a parameterised template', () {
      expect(accessFor('/campaigns/:id/approve'), isA<Requires>());
    });

    test('returns null for an unknown path', () {
      expect(accessFor('/nope'), isNull);
    });

    test('returns null for a null fullPath', () {
      expect(accessFor(null), isNull);
    });
  });
}
