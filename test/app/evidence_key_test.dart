import 'dart:convert';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  group('loadOrCreateEvidenceKey', () {
    test('reuses an existing key instead of replacing it', () async {
      // A key already in secure storage must come back byte-identical. If this
      // ever regresses, every piece of evidence encrypted under the stored key
      // becomes undecryptable.
      final stored = List<int>.generate(32, (i) => i);
      final storage = _MockSecureStorage();
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => base64Encode(stored));

      final key = await loadOrCreateEvidenceKey(storage);

      expect(key, stored);
      verifyNever(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      );
    });
  });
}
