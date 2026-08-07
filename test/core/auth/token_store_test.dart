import 'package:acsl_campaign/core/auth/token_store.dart';
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
