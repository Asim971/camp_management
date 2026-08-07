import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/auth/token_store.dart';
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';
import '../../support/in_memory_secure_store.dart';

void main() {
  group('SecureStoreKeys', () {
    test('the refresh-token key is frozen', () {
      // Renaming this silently signs out every installed device, because the
      // old key is abandoned with no way to find it again.
      expect(SecureStoreKeys.refreshTokenV1, 'auth_refresh_token_v1');
    });
  });

  group('MobileTokenStore', () {
    test('persists and reads back the refresh token', () async {
      final secure = InMemorySecureStore();
      final store = MobileTokenStore(secure);

      expect(await store.read(), isNull);
      await store.persist('r-1');

      expect(await store.read(), 'r-1');
      expect(secure.values[SecureStoreKeys.refreshTokenV1], 'r-1');
    });

    test('clear removes the token', () async {
      final secure = InMemorySecureStore({
        SecureStoreKeys.refreshTokenV1: 'r-1',
      });

      await MobileTokenStore(secure).clear();

      expect(
        secure.values.containsKey(SecureStoreKeys.refreshTokenV1),
        isFalse,
      );
    });

    test('an unreadable store yields null instead of throwing', () async {
      // A keystore fault must not crash sign-in: the user can still enter
      // credentials. Throwing here would take down app startup.
      final store = MobileTokenStore(
        ThrowingSecureStore(PlatformException(code: 'decrypt_failed')),
      );

      expect(await store.read(), isNull);
    });

    test('persist swallows a write failure instead of throwing', () async {
      // I2: an unguarded write escaping persist() propagates through
      // main()'s awaited restore() -> SessionManager._adopt before runApp
      // ever runs, permanently blanking the app. The correct failure
      // direction is "sign-in works, the session just won't survive a
      // restart" - not a crash.
      final store = MobileTokenStore(
        ThrowingSecureStore(
          PlatformException(code: 'keystore_unavailable'),
          throwOnRead: false,
          throwOnWrite: true,
        ),
      );

      await expectLater(store.persist('r-1'), completes);
    });

    test('clear swallows a delete failure instead of throwing', () async {
      // Same direction as persist(): signOut() must complete locally even if
      // the keystore delete fails, or AuthInterceptor.onError parks forever
      // inside QueuedInterceptor's exclusive error queue.
      final store = MobileTokenStore(
        ThrowingSecureStore(
          PlatformException(code: 'keystore_unavailable'),
          throwOnRead: false,
          throwOnDelete: true,
        ),
      );

      await expectLater(store.clear(), completes);
    });

    test('a SessionManager sign-in still succeeds against a store whose writes '
        'fail', () async {
      final store = MobileTokenStore(
        ThrowingSecureStore(
          PlatformException(code: 'keystore_unavailable'),
          throwOnRead: false,
          throwOnWrite: true,
        ),
      );
      final manager = SessionManager(
        service: ScriptedAuthService(),
        tokens: store,
      );

      final result = await manager.signIn('bob', 'pw');

      expect(result.isOk, isTrue);
      expect(manager.state, isA<AuthSignedIn>());
      manager.dispose();
    });
  });

  group('WebTokenStore', () {
    test('persist is a no-op and read always returns null', () async {
      // Web SecureStore is localStorage with a wrapped key, not hardware
      // backed. A refresh token there is stealable by any injected script, so
      // this platform deliberately holds nothing.
      const store = WebTokenStore();

      await store.persist('r-1');

      expect(await store.read(), isNull);
    });

    test('clear is safe to call', () async {
      const store = WebTokenStore();
      await expectLater(store.clear(), completes);
    });
  });
}
