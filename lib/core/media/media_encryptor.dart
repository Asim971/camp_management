import 'package:cryptography/cryptography.dart';

/// Encrypts captured evidence at rest on the device before it is queued for
/// upload (Architecture §9.1, §12). The symmetric key is held in secure storage
/// (Keystore/Keychain-backed); it never appears in the record, a URL or a log.
abstract interface class MediaEncryptor {
  /// Returns nonce‖ciphertext‖MAC so the payload is self-describing for the
  /// server-side decrypt step.
  Future<List<int>> encrypt(List<int> plaintext);
}

class AesGcmEncryptor implements MediaEncryptor {
  AesGcmEncryptor(this._key256);

  /// Supplies the 32-byte key (from secure storage). Injected so the encryptor
  /// stays testable and key management is isolated.
  final Future<List<int>> Function() _key256;

  final AesGcm _algo = AesGcm.with256bits();

  @override
  Future<List<int>> encrypt(List<int> plaintext) async {
    final key = await _algo.newSecretKeyFromBytes(await _key256());
    final box = await _algo.encrypt(plaintext, secretKey: key);
    return box.concatenation(); // nonce + ciphertext + mac
  }
}
