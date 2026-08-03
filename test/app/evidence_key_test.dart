import 'dart:convert';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:flutter/services.dart';
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

    test('generates and persists a key on first run', () async {
      // Nothing stored yet. The generated key must be 32 bytes and must be
      // written back, or every app start would mint a different key and no
      // evidence would survive a restart.
      final storage = _MockSecureStorage();
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenAnswer((_) async => null);
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      final key = await loadOrCreateEvidenceKey(storage);

      expect(key, hasLength(32));
      verify(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).called(1);
    });

    test('regenerates when the stored key cannot be decrypted', () async {
      // v10 changed the at-rest cipher, so a key written by v9 may be
      // unreadable. Capture must keep working, so a fresh key is generated -
      // but the exception must not escape and crash the capture path.
      final storage = _MockSecureStorage();
      when(
        () => storage.read(key: any(named: 'key')),
      ).thenThrow(PlatformException(code: 'decrypt_failed'));
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});

      final key = await loadOrCreateEvidenceKey(storage);

      expect(key, hasLength(32));
      verify(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).called(1);
    });
  });
}
