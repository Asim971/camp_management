import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/pool.dart';
import 'password.dart';
import 'tokens.dart';

/// `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`.
///
/// No route here accepts an `Idempotency-Key` (spec §5): every one of these
/// calls is expected to mint a fresh token pair (or, for logout, perform a
/// fresh revocation) on every invocation. Replaying a cached response would
/// hand back a stale, already-superseded token pair — a defect, not a
/// convenience.
Router authRouter({
  required Db db,
  required TokenService tokens,
  required PasswordHasher hasher,
}) {
  final router = Router();

  router.post('/auth/login', (Request request) async {
    final body = await _readJsonBody(request);
    final username = body?['username'];
    final password = body?['password'];
    if (username is! String || password is! String) {
      return _badRequest();
    }

    final res = await db.execute(
      'SELECT id, password_hash, is_active FROM staff_users '
      'WHERE username = @u',
      params: {'u': username},
    );
    // Unknown username, wrong password, and an inactive account all answer
    // identically: 401 with no distinguishing detail. A 404 for "no such
    // user" or a message naming the failed field would let a caller enumerate
    // valid usernames or confirm a guessed password was "close".
    if (res.isEmpty) return _unauthorized();
    final user = row(res.first);
    if (user['is_active']! as bool != true) return _unauthorized();
    final passwordHash = user['password_hash']! as String;
    if (!await hasher.verify(password, passwordHash)) {
      return _unauthorized();
    }

    final issued = await tokens.issueFor(user['id']! as String);
    return _tokenResponse(issued);
  });

  router.post('/auth/refresh', (Request request) async {
    final body = await _readJsonBody(request);
    final refreshToken = body?['refreshToken'];
    if (refreshToken is! String) return _badRequest();

    try {
      final issued = await tokens.rotate(refreshToken);
      return _tokenResponse(issued);
    } on RefreshReuseException {
      // Reuse already triggered family revocation inside TokenService; the
      // caller just sees the same 401 as any other invalid refresh attempt.
      return _unauthorized();
    } on InvalidRefreshTokenException {
      return _unauthorized();
    }
  });

  router.post('/auth/logout', (Request request) async {
    // Best-effort: the client treats a logout failure as non-fatal
    // (auth_service.dart:37-39), so this route always answers 204, whatever
    // the input — a missing/garbled body, an already-revoked or unknown
    // refresh token all end the same way. Returning an error here would only
    // produce client-side noise for no benefit.
    final body = await _readJsonBody(request);
    final refreshToken = body?['refreshToken'];
    if (refreshToken is String) {
      await tokens.revokeFamilyOf(refreshToken);
    }
    return Response(204);
  });

  return router;
}

Future<Map<String, Object?>?> _readJsonBody(Request request) async {
  try {
    final decoded = jsonDecode(await request.readAsString());
    return decoded is Map<String, Object?> ? decoded : null;
  } on FormatException {
    return null;
  }
}

Response _tokenResponse(IssuedTokens issued) => Response.ok(
  jsonEncode({
    'accessToken': issued.accessToken,
    'refreshToken': issued.refreshToken,
    'expiresInSeconds': issued.expiresInSeconds,
    'claims': issued.claims,
  }),
  headers: {'content-type': 'application/json'},
);

Response _badRequest() => Response(
  400,
  body: jsonEncode({
    'error': {
      'code': ApiErrorCode.badRequest.wireValue,
      'message': 'invalid request body',
    },
  }),
  headers: {'content-type': 'application/json'},
);

// Deliberately generic: never names which field was wrong, and never
// distinguishes "no such user" from "wrong credentials" — see the comment at
// the login handler's first check.
Response _unauthorized() => Response(
  401,
  body: jsonEncode({
    'error': {
      'code': ApiErrorCode.unauthorized.wireValue,
      'message': 'invalid credentials',
    },
  }),
  headers: {'content-type': 'application/json'},
);
