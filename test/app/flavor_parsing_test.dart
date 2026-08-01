import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseFlavor', () {
    test('resolves each known flavor name', () {
      expect(parseFlavor('dev'), Flavor.dev);
      expect(parseFlavor('stg'), Flavor.stg);
      expect(parseFlavor('prod'), Flavor.prod);
    });

    test('falls back to dev for an unknown name', () {
      // A typo must never silently resolve to prod. Failing closed to dev
      // points the app at the dev API, which is the safe direction.
      expect(parseFlavor('production'), Flavor.dev);
      expect(parseFlavor(''), Flavor.dev);
      expect(parseFlavor('PROD'), Flavor.dev);
    });
  });

  group('AppConfig.fromEnvironment', () {
    test('with no dart-defines yields the dev defaults', () {
      final config = AppConfig.fromEnvironment();
      expect(config.flavor, Flavor.dev);
      expect(config.isProd, isFalse);
      expect(config.apiBaseUrl, 'https://dev.api.example/campaign');
      expect(config.e2e, isFalse);
      expect(config.e2eRole, 'field_user');
    });
  });
}
