import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

// `Sha256`'s hash implementation, narrowed with `show` so this file's
// `SecretKey` (below, from dart_jsonwebtoken) never collides with
// cryptography's own class of the same name — see password.dart for the
// other half of that split.
import 'package:cryptography/dart.dart' show DartSha256;
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:postgres/postgres.dart' show Result, Sql, TxSession;
import 'package:uuid/uuid.dart';

import '../config.dart';
import '../db/pool.dart';

/// An already-issued, unexpired, unrevoked refresh token was presented a
/// second time. The whole rotation family has just been revoked in response.
class RefreshReuseException implements Exception {
  const RefreshReuseException();

  @override
  String toString() =>
      'RefreshReuseException: refresh token reuse detected; '
      'family revoked';
}

/// The presented refresh token is unknown, expired, or revoked — including a
/// descendant of a family that was revoked because an ancestor was reused.
class InvalidRefreshTokenException implements Exception {
  const InvalidRefreshTokenException();

  @override
  String toString() =>
      'InvalidRefreshTokenException: refresh token is '
      'unknown, expired, or revoked';
}

/// Server-side authority for role → permission expansion. The client only
/// renders what it is told; it never decides what a role can do.
const Map<String, List<String>> permissionsByRole = {
  'campaign_creator': ['campaign_create', 'bulk_import', 'export'],
  'marketing_approver': ['campaign_approve', 'campaign_cancel', 'export'],
  'crm_verifier': ['verification_decide', 'sensitive_media_view'],
  'crm_supervisor': [
    'verification_decide',
    'verification_override',
    'sensitive_media_view',
    'nid_reveal',
    'export',
  ],
  'field_user': ['attendance_capture'],
  'admin': [
    'campaign_create',
    'campaign_approve',
    'campaign_cancel',
    'bulk_import',
    'config_manage',
    'export',
  ],
  'reporting_viewer': ['export'],
};

/// An access/refresh token pair plus the claims embedded in the access token,
/// in exactly the shape the Flutter client parses
/// (`lib/core/auth/auth_service.dart:70-94`): the client never decodes the
/// JWT itself, so these claims are the only place it learns who the user is.
class IssuedTokens {
  const IssuedTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresInSeconds,
    required this.claims,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresInSeconds;
  final Map<String, Object?> claims;
}

/// Issues JWT access tokens and rotating, reuse-detecting refresh tokens.
///
/// Refresh tokens are 32 random bytes, base64url-encoded, returned to the
/// caller exactly once. Only their sha256 digest is stored, so a database
/// dump yields nothing usable — the plaintext cannot be recovered from
/// `refresh_tokens.token_hash`.
class TokenService {
  TokenService({required this.db, required this.config, Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final Db db;
  final ServerConfig config;
  final Uuid _uuid;

  static const int _refreshTokenBytes = 32;

  Future<IssuedTokens> issueFor(String userId) async {
    final claims = await _loadClaims(userId);
    final accessToken = _signAccessToken(userId);
    final familyId = _uuid.v4();
    final refreshToken = await _mintRefreshToken(
      familyId: familyId,
      userId: userId,
    );
    return IssuedTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresInSeconds: config.accessTokenTtl.inSeconds,
      claims: claims,
    );
  }

  /// Rotates a refresh token inside one transaction: look the presented
  /// token up by its hash, reject it outright if it is unknown, expired, or
  /// already revoked, and — the reuse-detection branch — if it was already
  /// used once before, revoke every row sharing its `family_id` and throw
  /// [RefreshReuseException] rather than issuing new tokens.
  ///
  /// The reuse branch's `UPDATE` MUST commit even though the caller ends up
  /// seeing an exception: throwing from inside [Db.tx]'s callback rolls the
  /// whole transaction — including that very `UPDATE` — back, which would
  /// silently undo the family revocation this method exists to guarantee.
  /// So the callback returns a marker instead of throwing, and [rotate]
  /// throws only after the transaction (and its revocation) has committed.
  Future<IssuedTokens> rotate(String presentedRefreshToken) async {
    final presentedHash = _hash(presentedRefreshToken);
    final outcome = await db.tx((tx) async {
      final res = await tx.execute(
        Sql.named(
          'SELECT id, user_id, family_id, expires_at, used_at, revoked_at '
          'FROM refresh_tokens WHERE token_hash = @hash',
        ),
        parameters: {'hash': presentedHash},
      );
      if (res.isEmpty) {
        throw const InvalidRefreshTokenException();
      }
      final found = row(res.first);
      final expiresAt = found['expires_at']! as DateTime;
      final usedAt = found['used_at'] as DateTime?;
      final revokedAt = found['revoked_at'] as DateTime?;
      final familyId = found['family_id']! as String;
      final userId = found['user_id']! as String;

      if (revokedAt != null || expiresAt.isBefore(DateTime.now().toUtc())) {
        throw const InvalidRefreshTokenException();
      }

      if (usedAt != null) {
        // Reuse: a copy of this token leaked. Revoking only the presented
        // row would leave any newer, legitimately-rotated descendant valid
        // in an attacker's hands, so the whole family is killed. This
        // UPDATE must survive the transaction — see the doc comment above.
        await tx.execute(
          Sql.named(
            'UPDATE refresh_tokens SET revoked_at = now() '
            'WHERE family_id = @family AND revoked_at IS NULL',
          ),
          parameters: {'family': familyId},
        );
        return (reused: true, tokens: null as IssuedTokens?);
      }

      await tx.execute(
        Sql.named('UPDATE refresh_tokens SET used_at = now() WHERE id = @id'),
        parameters: {'id': found['id']! as String},
      );

      final claims = await _loadClaimsTx(tx, userId);
      final accessToken = _signAccessToken(userId);
      final newRefreshToken = await _mintRefreshTokenTx(
        tx,
        familyId: familyId,
        userId: userId,
      );
      return (
        reused: false,
        tokens: IssuedTokens(
          accessToken: accessToken,
          refreshToken: newRefreshToken,
          expiresInSeconds: config.accessTokenTtl.inSeconds,
          claims: claims,
        ),
      );
    });
    if (outcome.reused) {
      throw const RefreshReuseException();
    }
    return outcome.tokens!;
  }

  /// Revokes every token in the family the presented token belongs to.
  /// Used by `/auth/logout`; never throws on an already-unknown or
  /// already-revoked token — logout is best-effort by contract
  /// (`auth_service.dart:37-39`).
  Future<void> revokeFamilyOf(String presentedRefreshToken) async {
    final presentedHash = _hash(presentedRefreshToken);
    final res = await db.execute(
      'SELECT family_id FROM refresh_tokens WHERE token_hash = @hash',
      params: {'hash': presentedHash},
    );
    if (res.isEmpty) return;
    final familyId = row(res.first)['family_id']! as String;
    await db.execute(
      'UPDATE refresh_tokens SET revoked_at = now() '
      'WHERE family_id = @family AND revoked_at IS NULL',
      params: {'family': familyId},
    );
  }

  /// Verifies [jwt] and returns the subject (user id), or `null` on any
  /// [JWTException] — unknown signature, expiry, malformed token, whatever
  /// the cause. Task 5's authenticate middleware relies on this single
  /// code path for "not authenticated": it never needs to discriminate why.
  String? userIdFromAccessToken(String jwt) {
    try {
      final verified = JWT.verify(jwt, SecretKey(config.jwtSecret));
      return verified.subject;
    } on JWTException {
      return null;
    }
  }

  String _signAccessToken(String userId) {
    final jwt = JWT(<String, dynamic>{}, subject: userId);
    return jwt.sign(
      SecretKey(config.jwtSecret),
      algorithm: JWTAlgorithm.HS256,
      expiresIn: config.accessTokenTtl,
    );
  }

  Future<String> _mintRefreshToken({
    required String familyId,
    required String userId,
  }) async {
    final plaintext = _randomRefreshToken();
    await db.execute(
      'INSERT INTO refresh_tokens '
      '(id, user_id, family_id, token_hash, expires_at) '
      'VALUES (@id, @user, @family, @hash, @expires)',
      params: {
        'id': _uuid.v4(),
        'user': userId,
        'family': familyId,
        'hash': _hash(plaintext),
        'expires': DateTime.now().toUtc().add(config.refreshTokenTtl),
      },
    );
    return plaintext;
  }

  Future<String> _mintRefreshTokenTx(
    TxSession tx, {
    required String familyId,
    required String userId,
  }) async {
    final plaintext = _randomRefreshToken();
    await tx.execute(
      Sql.named(
        'INSERT INTO refresh_tokens '
        '(id, user_id, family_id, token_hash, expires_at) '
        'VALUES (@id, @user, @family, @hash, @expires)',
      ),
      parameters: {
        'id': _uuid.v4(),
        'user': userId,
        'family': familyId,
        'hash': _hash(plaintext),
        'expires': DateTime.now().toUtc().add(config.refreshTokenTtl),
      },
    );
    return plaintext;
  }

  Future<Map<String, Object?>> _loadClaims(String userId) =>
      _claimsQuery((sql, params) => db.execute(sql, params: params), userId);

  Future<Map<String, Object?>> _loadClaimsTx(TxSession tx, String userId) =>
      _claimsQuery(
        (sql, params) => tx.execute(Sql.named(sql), parameters: params),
        userId,
      );

  /// One query joining staff_users, staff_user_roles and
  /// staff_user_territories, then mapping roles to permissions with
  /// [permissionsByRole]. Emits exactly the names the client's
  /// scope_claims.dart recognises — nothing invented, nothing renamed.
  Future<Map<String, Object?>> _claimsQuery(
    Future<Result> Function(String sql, Map<String, Object?> params) run,
    String userId,
  ) async {
    final userRes = await run(
      'SELECT id, display_name, organization_id FROM staff_users '
      'WHERE id = @id',
      {'id': userId},
    );
    if (userRes.isEmpty) {
      throw StateError('No staff_users row for id "$userId".');
    }
    final user = row(userRes.first);

    final roleRes = await run(
      'SELECT role FROM staff_user_roles WHERE user_id = @id',
      {'id': userId},
    );
    final roles = [for (final r in roleRes) row(r)['role']! as String];

    final territoryRes = await run(
      'SELECT territory_id FROM staff_user_territories WHERE user_id = @id',
      {'id': userId},
    );
    final territoryIds = [
      for (final r in territoryRes) row(r)['territory_id']! as String,
    ];

    final permissions = <String>{
      for (final r in roles) ...(permissionsByRole[r] ?? const []),
    };

    return {
      'userId': user['id'],
      'displayName': user['display_name'],
      'organizationId': user['organization_id'],
      'territoryIds': territoryIds,
      'roles': roles,
      'permissions': permissions.toList(),
    };
  }

  static String _randomRefreshToken() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList([
      for (var i = 0; i < _refreshTokenBytes; i++) rng.nextInt(256),
    ]);
    return base64Url.encode(bytes);
  }

  static String _hash(String plaintext) =>
      base64.encode(const DartSha256().hashSync(utf8.encode(plaintext)).bytes);
}
