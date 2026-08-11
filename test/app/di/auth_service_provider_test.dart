import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/auth_service.dart';
import 'package:acsl_campaign/core/auth/e2e_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 11 step 6 (D3): `authServiceProvider`'s branch on `config.e2eRealAuth`
/// is the ONLY thing that decides whether a Maestro run logs into the real
/// identity provider or the fake one. Every other E2E behaviour (dev
/// launcher, fake camera, seeded local data) is unchanged by this flag, so
/// this file only exercises the one branch that changed.
AppConfig _config({required bool e2e, required bool e2eRealAuth}) => AppConfig(
  flavor: Flavor.dev,
  apiBaseUrl: 'https://example.invalid',
  mediaHost: 'https://example.invalid',
  e2e: e2e,
  e2eRealAuth: e2eRealAuth,
);

ProviderContainer _containerFor(AppConfig config) =>
    ProviderContainer(overrides: [appConfigProvider.overrideWithValue(config)]);

void main() {
  test('production (e2e: false) always uses the real auth transport', () {
    final container = _containerFor(_config(e2e: false, e2eRealAuth: false));
    addTearDown(container.dispose);
    expect(container.read(authServiceProvider), isA<DioAuthService>());
  });

  test('e2e without E2E_REAL_AUTH still uses the fake transport (unchanged '
      'behaviour)', () {
    final container = _containerFor(_config(e2e: true, e2eRealAuth: false));
    addTearDown(container.dispose);
    expect(container.read(authServiceProvider), isA<FakeAuthService>());
  });

  test('e2e WITH E2E_REAL_AUTH keeps the real transport, so at least one flow '
      'logs into the real identity provider', () {
    final container = _containerFor(_config(e2e: true, e2eRealAuth: true));
    addTearDown(container.dispose);
    expect(container.read(authServiceProvider), isA<DioAuthService>());
  });
}
