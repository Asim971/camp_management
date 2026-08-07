import 'package:acsl_campaign/core/storage/secure_store.dart';

/// In-memory [SecureStore] for tests. Replaces mocking FlutterSecureStorage,
/// which required a `mocktail` stub per call and could not express "a value
/// exists but cannot be decrypted".
class InMemorySecureStore implements SecureStore {
  InMemorySecureStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;
  int writeCount = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    writeCount++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A store whose reads fail by default - models the platform case where a
/// value is present but undecryptable (v10 cipher change, keystore reset,
/// restore onto a different device). Writes still succeed by default so
/// recovery paths (regenerate-and-persist) are testable.
///
/// [throwOnWrite] and [throwOnDelete] model the OTHER platform fault: a
/// keystore that cannot be written to at all (full, permission-revoked,
/// hardware fault) rather than merely unreadable.
class ThrowingSecureStore implements SecureStore {
  ThrowingSecureStore(
    this.error, {
    this.throwOnRead = true,
    this.throwOnWrite = false,
    this.throwOnDelete = false,
  });

  final Object error;
  final bool throwOnRead;
  final bool throwOnWrite;
  final bool throwOnDelete;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async {
    if (throwOnRead) throw error;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (throwOnWrite) throw error;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (throwOnDelete) throw error;
    values.remove(key);
  }
}
