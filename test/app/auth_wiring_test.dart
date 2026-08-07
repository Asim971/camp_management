import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

void main() {
  test('authStateProvider reflects the SessionManager', () async {
    final service = ScriptedAuthService();
    final tokens = FakeTokenStore();
    final manager = SessionManager(service: service, tokens: tokens);
    addTearDown(manager.dispose);

    final container = ProviderContainer(
      overrides: [sessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);

    expect(container.read(authStateProvider), isA<AuthSignedOut>());

    await manager.signIn('bob', 'pw');
    // Let the broadcast stream deliver to the provider's listener.
    await pumpEventQueue();

    expect(container.read(authStateProvider), isA<AuthSignedIn>());
  });

  test('signing out returns authStateProvider to signed out', () async {
    final manager = SessionManager(
      service: ScriptedAuthService(),
      tokens: FakeTokenStore(),
    );
    addTearDown(manager.dispose);

    final container = ProviderContainer(
      overrides: [sessionManagerProvider.overrideWithValue(manager)],
    );
    addTearDown(container.dispose);

    await manager.signIn('bob', 'pw');
    await pumpEventQueue();
    await manager.signOut();
    await pumpEventQueue();

    expect(container.read(authStateProvider), isA<AuthSignedOut>());
  });
}
