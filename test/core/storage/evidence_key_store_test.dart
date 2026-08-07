import 'dart:convert';

import 'package:acsl_campaign/core/audit/audit.dart';
import 'package:acsl_campaign/core/storage/evidence_key_store.dart';
import 'package:acsl_campaign/core/storage/secure_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_secure_store.dart';
import '../../support/recording_audit_sink.dart';

void main() {
  group('EvidenceKeyStore', () {
    test('reuses an existing key instead of replacing it', () async {
      // A key already in secure storage must come back byte-identical. If this
      // ever regresses, every piece of evidence encrypted under the stored key
      // becomes undecryptable.
      final stored = List<int>.generate(32, (i) => i);
      final store = InMemorySecureStore({
        SecureStoreKeys.evidenceAesKeyV1: base64Encode(stored),
      });
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(
        store: store,
        audit: audit,
      ).loadOrCreate();

      expect(key, stored);
      expect(store.writeCount, 0);
      expect(audit.events, isEmpty);
    });

    test('generates and persists a key on first run', () async {
      // Nothing stored yet. The generated key must be 32 bytes and must be
      // written back, or every app start would mint a different key and no
      // evidence would survive a restart.
      final store = InMemorySecureStore();
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(
        store: store,
        audit: audit,
      ).loadOrCreate();

      expect(key, hasLength(32));
      expect(
        base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
        key,
      );
      // A first run is not a rotation - nothing was lost, so nothing to audit.
      expect(audit.events, isEmpty);
    });

    test('regenerates and audits when the stored key cannot be read', () async {
      // v10 changed the at-rest cipher, so a key written by v9 may be
      // unreadable. Capture must keep working, so a fresh key is generated -
      // but every piece of evidence under the old key is now undecryptable, so
      // this must leave a durable trace rather than only a debugPrint.
      final store = ThrowingSecureStore(
        PlatformException(code: 'decrypt_failed'),
      );
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(
        store: store,
        audit: audit,
      ).loadOrCreate();

      expect(key, hasLength(32));
      expect(
        base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
        key,
      );
      expect(audit.events, hasLength(1));
      expect(audit.events.single.action, AuditAction.evidenceKeyRotated);
      expect(audit.events.single.entity, 'evidenceKey');
    });

    test(
      'regenerates and audits when the stored value is not valid base64',
      () async {
        // A corrupt stored value must not let `FormatException` escape
        // `loadOrCreate` and take the capture path down with it - the doc
        // comment promises this method never throws.
        final store = InMemorySecureStore({
          SecureStoreKeys.evidenceAesKeyV1: 'not-valid-base64!!!',
        });
        final audit = RecordingAuditSink();

        final key = await EvidenceKeyStore(
          store: store,
          audit: audit,
        ).loadOrCreate();

        expect(key, hasLength(32));
        expect(
          base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
          key,
        );
        expect(audit.events, hasLength(1));
        expect(audit.events.single.action, AuditAction.evidenceKeyRotated);
      },
    );

    test('regenerates and audits when the stored key decodes to the wrong '
        'length', () async {
      // Valid base64 but not 32 bytes (e.g. a truncated write). Without a
      // length check this silently yields a wrong-size key that only fails
      // much later, deep inside AesGcm, with a far less diagnosable error.
      final truncated = List<int>.generate(16, (i) => i);
      final store = InMemorySecureStore({
        SecureStoreKeys.evidenceAesKeyV1: base64Encode(truncated),
      });
      final audit = RecordingAuditSink();

      final key = await EvidenceKeyStore(
        store: store,
        audit: audit,
      ).loadOrCreate();

      expect(key, hasLength(32));
      expect(
        base64Decode(store.values[SecureStoreKeys.evidenceAesKeyV1]!),
        key,
      );
      expect(audit.events, hasLength(1));
      expect(audit.events.single.action, AuditAction.evidenceKeyRotated);
    });

    test('does not let a storage failure escape and crash capture', () async {
      final store = ThrowingSecureStore(
        PlatformException(code: 'keystore_unavailable'),
      );

      await expectLater(
        EvidenceKeyStore(
          store: store,
          audit: RecordingAuditSink(),
        ).loadOrCreate(),
        completes,
      );
    });
  });
}
