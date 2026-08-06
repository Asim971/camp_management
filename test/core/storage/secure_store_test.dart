import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_secure_store.dart';

void main() {
  group('SecureStoreKeys', () {
    test('the evidence key name is frozen', () {
      // Renaming this abandons any key already on a device, and with it the
      // ability to decrypt evidence encrypted under it. Never change it.
      expect(SecureStoreKeys.evidenceAesKeyV1, 'evidence_aes_key_v1');
    });
  });

  group('InMemorySecureStore', () {
    test('round-trips a value', () async {
      final store = InMemorySecureStore();

      expect(await store.read('k'), isNull);
      await store.write('k', 'v');
      expect(await store.read('k'), 'v');
    });

    test('delete removes the value', () async {
      final store = InMemorySecureStore({'k': 'v'});

      await store.delete('k');

      expect(await store.read('k'), isNull);
    });
  });
}
