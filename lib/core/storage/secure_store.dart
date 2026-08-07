import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keys used with [SecureStore]. Centralised so a rename is a deliberate,
/// reviewable act rather than an inline edit.
abstract final class SecureStoreKeys {
  /// NEVER rename. Renaming abandons any key already present on a device, and
  /// with it the ability to decrypt evidence encrypted under that key.
  static const String evidenceAesKeyV1 = 'evidence_aes_key_v1';

  /// NEVER rename. Same rule as [evidenceAesKeyV1]: a rename abandons the key
  /// already on every installed device, silently signing all of them out.
  static const String refreshTokenV1 = 'auth_refresh_token_v1';
}

/// Platform-backed secret storage (Keystore on Android, Keychain on iOS).
///
/// **Web is not hardware-backed.** `flutter_secure_storage_web` is
/// `localStorage` with a wrapped key, so on web this is obfuscation, not
/// protection. Consequences: the evidence AES key stays mobile-only (capture
/// already is), and the CRM web surface must persist nothing whose compromise
/// matters beyond the session.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecureStore implements SecureStore {
  FlutterSecureStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          // v10 defaults resetOnError to true, which silently deletes a value
          // it cannot decrypt. For the evidence key that would orphan every
          // queued capture with no signal, so opt out and let the caller
          // (EvidenceKeyStore) handle the failure explicitly and audibly.
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
