import 'package:acsl_campaign/app/flavors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppConfig exposes a locale from the LOCALE dart-define', () {
    // Every Maestro flow has always passed LOCALE as a launch argument and
    // AppConfig never read it — the harness was configuring something the app
    // ignored. P0.5 is the epic that makes it mean something.
    final config = AppConfig.fromEnvironment();

    // With no --dart-define=LOCALE at test time this is empty, which the
    // controller treats as "not specified".
    expect(config.locale, isA<String>());
    expect(config.locale, isEmpty);
  });
}
