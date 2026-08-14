import 'package:campaign_service/src/media/signed_url.dart';
import 'package:test/test.dart';

void main() {
  const key = 'a-signing-key-at-least-32-characters!!';
  final now = DateTime.utc(2026, 8, 14, 12);

  ({String id, int exp, String sig}) parse(String url) {
    final u = Uri.parse(url);
    return (
      id: u.pathSegments.last,
      exp: int.parse(u.queryParameters['exp']!),
      sig: u.queryParameters['sig']!,
    );
  }

  test('a freshly signed URL verifies', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://10.0.2.2:8080',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    expect(url, contains('/media/upload/att-1?'));
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isTrue,
    );
  });

  test('a tampered id fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: 'att-2',
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isFalse,
    );
  });

  test('a tampered exp fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: p.id,
        exp: p.exp + 3600,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isFalse,
    );
  });

  test('a wrong signing key fails', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: 'different-key-32-characters-long!!',
        now: now,
      ),
      isFalse,
    );
  });

  test('an expired URL fails even with a valid signature', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
      ttl: const Duration(minutes: 15),
    );
    final p = parse(url);
    // 16 minutes later: past the 15-minute TTL.
    final later = now.add(const Duration(minutes: 16));
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: later,
      ),
      isFalse,
    );
  });

  // Falsification: a garbage signature must never verify.
  test('a forged signature is rejected', () async {
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: 'att-1',
        exp: now.millisecondsSinceEpoch ~/ 1000 + 900,
        sig: 'not-a-real-signature',
        signingKey: key,
        now: now,
      ),
      isFalse,
    );
  });

  // Security: a read capability must not be replayable as an upload
  // capability, and vice versa (5a verification review finding).
  test('a read signature is rejected when verified as an upload', () async {
    final url = await signReadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'upload',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isFalse,
    );
    // Confirm the same signature is valid for its own ('read') scope, so
    // the failure above is due to op-scoping and not a broken signature.
    expect(
      await verifySignedUrl(
        op: 'read',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isTrue,
    );
  });

  test('an upload signature is rejected when verified as a read', () async {
    final url = await signUploadUrl(
      baseUrl: 'http://h',
      id: 'att-1',
      signingKey: key,
      now: now,
    );
    final p = parse(url);
    expect(
      await verifySignedUrl(
        op: 'read',
        id: p.id,
        exp: p.exp,
        sig: p.sig,
        signingKey: key,
        now: now,
      ),
      isFalse,
    );
  });
}
