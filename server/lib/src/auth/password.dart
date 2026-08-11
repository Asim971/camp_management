import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Argon2id cost parameters. Stored inside every encoded hash so raising cost
/// later does not invalidate existing passwords.
class Argon2Params {
  const Argon2Params({
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });

  /// Minimum number of 1 kB blocks.
  final int memory;
  final int iterations;
  final int parallelism;

  /// OWASP-recommended baseline: 19 MiB, t=2, p=1. Measured at ~155ms per hash
  /// with DartArgon2id on a dev machine — an acceptable login cost.
  static const production = Argon2Params(
    memory: 19456,
    iterations: 2,
    parallelism: 1,
  );

  /// For tests only. Fast enough to hash dozens of times per suite.
  static const fastForTests = Argon2Params(
    memory: 256,
    iterations: 1,
    parallelism: 1,
  );
}

/// Argon2id password hashing, pure Dart (no FFI): [DartArgon2id] is
/// package:cryptography's own implementation, so the server needs no native
/// build step.
class PasswordHasher {
  const PasswordHasher({this.params = Argon2Params.production});

  final Argon2Params params;

  static const int _saltLength = 16;
  static const int _hashLength = 32;

  Future<String> hash(String password) async {
    final salt = _randomBytes(_saltLength);
    final digest = await _derive(password, salt, params);
    // Escaped dollars, NOT raw strings: r'…' does not interpolate, so a raw
    // version of this line would emit the literal text ${params.memory}.
    return '\$argon2id\$v=19'
        '\$m=${params.memory},t=${params.iterations},p=${params.parallelism}'
        '\$${base64.encode(salt)}\$${base64.encode(digest)}';
  }

  /// Verifies against the parameters recorded in [encoded], NOT [params].
  /// Returns false on any malformed input rather than throwing: a corrupt row
  /// must fail authentication, not crash the login route.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 6 || parts[1] != 'argon2id' || parts[2] != 'v=19') {
      return false;
    }
    final parsed = _parseParams(parts[3]);
    if (parsed == null) return false;
    final Uint8List salt;
    final Uint8List expected;
    try {
      salt = base64.decode(parts[4]);
      expected = base64.decode(parts[5]);
    } on FormatException {
      return false;
    }
    final actual = await _derive(
      password,
      salt,
      parsed,
      hashLength: expected.length,
    );
    return _constantTimeEquals(actual, expected);
  }

  Future<Uint8List> _derive(
    String password,
    List<int> salt,
    Argon2Params p, {
    int hashLength = _hashLength,
  }) async {
    final algorithm = DartArgon2id(
      memory: p.memory,
      iterations: p.iterations,
      parallelism: p.parallelism,
      hashLength: hashLength,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Argon2Params? _parseParams(String segment) {
    final values = <String, int>{};
    for (final pair in segment.split(',')) {
      final kv = pair.split('=');
      if (kv.length != 2) return null;
      final n = int.tryParse(kv[1]);
      if (n == null || n <= 0) return null;
      values[kv[0]] = n;
    }
    final m = values['m'], t = values['t'], p = values['p'];
    if (m == null || t == null || p == null) return null;
    return Argon2Params(memory: m, iterations: t, parallelism: p);
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList([for (var i = 0; i < n; i++) rng.nextInt(256)]);
  }

  /// Length-independent comparison, so a mismatch's position is not timeable.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    for (var i = 0; i < a.length && i < b.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
