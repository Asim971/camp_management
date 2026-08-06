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

/// A store whose reads always fail - models the platform case where a value is
/// present but undecryptable (v10 cipher change, keystore reset, restore onto a
/// different device). Writes still succeed so recovery paths are testable.
class ThrowingSecureStore implements SecureStore {
  ThrowingSecureStore(this.error);

  final Object error;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => throw error;

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}
