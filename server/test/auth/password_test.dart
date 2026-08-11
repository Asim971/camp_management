import 'package:campaign_service/src/auth/password.dart';
import 'package:test/test.dart';

void main() {
  // Production params (19 MiB, t=2) cost ~155ms per hash, measured on this
  // repo's dev machine. Tests use cheap params so a suite that hashes dozens of
  // times stays fast; the encoded format carries the params either way.
  const hasher = PasswordHasher(params: Argon2Params.fastForTests);

  test('a hash verifies against its own password', () async {
    final encoded = await hasher.hash('correct horse battery staple');
    expect(
      await hasher.verify('correct horse battery staple', encoded),
      isTrue,
    );
  });

  test('a wrong password does not verify', () async {
    final encoded = await hasher.hash('correct horse battery staple');
    expect(
      await hasher.verify('Correct horse battery staple', encoded),
      isFalse,
    );
    expect(await hasher.verify('', encoded), isFalse);
  });

  test('two hashes of the same password differ (per-hash salt)', () async {
    final a = await hasher.hash('same');
    final b = await hasher.hash('same');
    expect(a, isNot(b));
    expect(await hasher.verify('same', a), isTrue);
    expect(await hasher.verify('same', b), isTrue);
  });

  test('the encoded form records the algorithm and its parameters', () async {
    final encoded = await hasher.hash('pw');
    expect(encoded, startsWith(r'$argon2id$v=19$'));
    expect(encoded.split(r'$').length, 6, reason: 'alg, v, params, salt, hash');
  });

  // The reason parameters live in the string: raising cost must not lock out
  // every existing user. A hash made with cheap params must still verify after
  // the hasher's own defaults change.
  test(
    'verification uses the parameters stored in the hash, not its own',
    () async {
      final cheap = await const PasswordHasher(
        params: Argon2Params.fastForTests,
      ).hash('shared');
      const expensive = PasswordHasher(params: Argon2Params.production);
      expect(await expensive.verify('shared', cheap), isTrue);
    },
  );

  test('a malformed encoded hash returns false rather than throwing', () async {
    expect(await hasher.verify('pw', 'not-a-hash'), isFalse);
    expect(
      await hasher.verify('pw', r'$argon2id$v=19$m=x,t=y,p=z$aaaa$bbbb'),
      isFalse,
    );
  });
}
