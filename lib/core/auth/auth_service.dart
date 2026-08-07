import 'package:dio/dio.dart';

import '../network/dio_client.dart';
import '../result/result.dart';

/// A token pair plus the raw scope claims the server issued alongside it.
///
/// [claims] is deliberately untyped here: mapping it to [AppRole]/[Permission]
/// is a trust decision that belongs in `scope_claims.dart`, not in transport.
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.claims,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Map<String, Object?> claims;
}

/// Transport seam for the auth service.
///
/// 🔒 The auth contract (endpoints, payload shapes, claim names, rotation
/// semantics) is an unresolved external dependency. Keeping it behind one
/// interface means `SessionManager`, the router, the guard and every permission
/// check are transport-agnostic when it lands.
///
/// Returns [Result] rather than throwing so `session_manager.dart` needs no
/// network import: error mapping belongs here.
abstract interface class AuthService {
  Future<Result<AuthTokens>> login(String username, String password);
  Future<Result<AuthTokens>> refresh(String refreshToken);

  /// Best-effort server-side revocation. A failure must not prevent local
  /// sign-out, so the caller treats an [Err] as non-fatal.
  Future<Result<void>> logout(String refreshToken);
}

/// Dio-backed auth transport. Endpoints and payload shapes are placeholders
/// pending the 🔒 auth contract, exactly as the campaign endpoints are.
class DioAuthService implements AuthService {
  DioAuthService(this._dio);

  final Dio _dio;

  @override
  Future<Result<AuthTokens>> login(String username, String password) =>
      _tokenCall('/auth/login', {'username': username, 'password': password});

  @override
  Future<Result<AuthTokens>> refresh(String refreshToken) =>
      _tokenCall('/auth/refresh', {'refreshToken': refreshToken});

  @override
  Future<Result<void>> logout(String refreshToken) async {
    try {
      await _dio.post<void>(
        '/auth/logout',
        data: {'refreshToken': refreshToken},
      );
      return const Ok(null);
    } catch (e) {
      return Err(mapDioError(e));
    }
  }

  Future<Result<AuthTokens>> _tokenCall(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(path, data: body);
      final data = res.data!;
      final seconds = data['expiresInSeconds'];
      return Ok(
        AuthTokens(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
          // Relative lifetime, not an absolute server timestamp: the client
          // cannot trust its own clock to agree with the server's, but it can
          // trust "valid for N more seconds from when this arrived".
          expiresAt: DateTime.now().toUtc().add(
            Duration(seconds: seconds is num ? seconds.toInt() : 0),
          ),
          claims: (data['claims'] as Map?)?.cast<String, Object?>() ?? const {},
        ),
      );
    } catch (e) {
      return Err(mapDioError(e));
    }
  }
}
