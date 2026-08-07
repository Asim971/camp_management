import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../audit/audit.dart';
import '../trace/trace_id.dart';
import 'secure_store.dart';

/// Owns the 32-byte AES key used to encrypt attendance evidence.
///
/// Extracted from the composition root so its failure paths are testable: what
/// happens here decides whether queued evidence stays decryptable.
class EvidenceKeyStore {
  EvidenceKeyStore({required this._store, required this._audit});

  final SecureStore _store;
  final AuditSink _audit;

  /// Loads the evidence key, generating and persisting one on first run.
  ///
  /// Never throws: a failure here must not crash the capture path.
  Future<List<int>> loadOrCreate() async {
    String? existing;
    var rotated = false;

    try {
      existing = await _store.read(SecureStoreKeys.evidenceAesKeyV1);
    } catch (error) {
      // A key exists but cannot be decrypted - after the v10 cipher change, an
      // OS keystore reset, or a restore onto a different device. Regenerating
      // keeps capture working, but every piece of evidence encrypted under the
      // previous key becomes undecryptable, so this must never look like a
      // normal first run.
      rotated = true;
      debugPrint(
        'Evidence key could not be read ($error). Generating a new one; '
        'evidence encrypted under the previous key can no longer be decrypted.',
      );
    }

    if (existing != null) return base64Decode(existing);

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    try {
      await _store.write(SecureStoreKeys.evidenceAesKeyV1, base64Encode(bytes));
    } catch (error) {
      // Capture can proceed with an in-memory key, but nothing encrypted under
      // it will survive a restart.
      debugPrint('Evidence key could not be persisted ($error).');
    }

    if (rotated) {
      // Durable trace, not just a debugPrint: this is the event an
      // investigation into undecryptable evidence would look for.
      await _audit.emit(
        AuditEvent(
          action: AuditAction.evidenceKeyRotated,
          entity: 'evidenceKey',
          entityId: SecureStoreKeys.evidenceAesKeyV1,
          correlationId: TraceId.generate(),
          // No session is guaranteed at capture-setup time, and the rotation is
          // a device event rather than a user action.
          actorId: 'system',
        ),
      );
    }

    return bytes;
  }
}
