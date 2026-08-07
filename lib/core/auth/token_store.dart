import 'package:flutter/foundation.dart';

import '../storage/secure_store.dart';

/// Persistence for the refresh token.
///
/// Only the *refresh* token is ever stored. The access token is short-lived and
/// re-derivable from it, so persisting it would widen the attack surface for no
/// gain.
abstract interface class TokenStore {
  Future<void> persist(String refreshToken);
  Future<String?> read();
  Future<void> clear();
}

/// Keystore/Keychain-backed store for mobile.
///
/// Field devices persist deliberately: a field user reopening the app mid
/// session may be offline and unable to re-authenticate at all, so losing the
/// session on restart would lose their working state.
class MobileTokenStore implements TokenStore {
  MobileTokenStore(this._store);

  final SecureStore _store;

  @override
  Future<void> persist(String refreshToken) async {
    try {
      await _store.write(SecureStoreKeys.refreshTokenV1, refreshToken);
    } catch (error) {
      // A keystore fault here must fail in the direction of "sign-in still
      // works, the session just won't survive a restart" - not propagate up
      // through SessionManager._adopt and main()'s awaited restore(), which
      // would take down startup before runApp ever runs, or through
      // LoginScreen._submit, which would leave the Sign in button spinning
      // forever with _busy stuck true.
      debugPrint(
        'Refresh token could not be persisted ($error). '
        'The session will not survive a restart.',
      );
    }
  }

  @override
  Future<String?> read() async {
    try {
      return await _store.read(SecureStoreKeys.refreshTokenV1);
    } catch (error) {
      // A keystore fault (cipher change, OS reset, restore onto another
      // device) must not crash startup. The user simply signs in again.
      debugPrint('Refresh token could not be read ($error). Signing out.');
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _store.delete(SecureStoreKeys.refreshTokenV1);
    } catch (error) {
      // Same direction as persist(): signOut() must complete locally even if
      // the underlying keystore write fails, or a wedged store leaves
      // AuthInterceptor.onError parked forever inside QueuedInterceptor's
      // exclusive error queue.
      debugPrint('Refresh token could not be cleared ($error).');
    }
  }
}

/// Deliberate no-op store for web.
///
/// `flutter_secure_storage_web` is `localStorage` with a wrapped key, NOT
/// hardware-backed, so anything written there is readable by any script
/// injected into the page. A refresh token is the single credential least
/// worth exposing that way, so web holds tokens in memory only and a reload
/// signs the user out.
///
/// Changing this needs a server-side httpOnly refresh cookie, not a different
/// client store.
class WebTokenStore implements TokenStore {
  const WebTokenStore();

  @override
  Future<void> persist(String refreshToken) async {}

  @override
  Future<String?> read() async => null;

  @override
  Future<void> clear() async {}
}

/// Selects the store for the current platform.
TokenStore createTokenStore(SecureStore store) =>
    kIsWeb ? const WebTokenStore() : MobileTokenStore(store);
