import 'package:acsl_campaign/core/auth/auth_service.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  Dio buildDio(ScriptedAdapter adapter) =>
      Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

  group('DioAuthService.login', () {
    test('posts to /auth/login and returns tokens on success', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.json(200, {
          'accessToken': 'a-1',
          'refreshToken': 'r-1',
          'expiresInSeconds': 900,
          'claims': {'userId': 'u-1'},
        }),
      ]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'pw');

      expect(result.isOk, isTrue);
      final tokens = result.fold((t) => t, (_) => null)!;
      expect(tokens.accessToken, 'a-1');
      expect(tokens.refreshToken, 'r-1');
      expect(tokens.claims['userId'], 'u-1');
      expect(adapter.requests.single.path, '/auth/login');
      // The password must never appear in a query string, only the body.
      expect(adapter.requests.single.uri.query, isEmpty);
    });

    test('maps a 401 to FailureKind.unauthorized', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(401)]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'no');

      expect(result.fold((_) => null, (f) => f.kind), FailureKind.unauthorized);
    });

    test('maps a connection error to FailureKind.network', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.failure(DioExceptionType.connectionError),
      ]);

      final result = await DioAuthService(buildDio(adapter)).login('bob', 'pw');

      expect(result.fold((_) => null, (f) => f.kind), FailureKind.network);
    });
  });

  group('DioAuthService.refresh', () {
    test('sends the refresh token and returns the rotated pair', () async {
      final adapter = ScriptedAdapter([
        const ScriptedReply.json(200, {
          'accessToken': 'a-2',
          'refreshToken': 'r-2',
          'expiresInSeconds': 900,
          'claims': <String, Object?>{},
        }),
      ]);

      final result = await DioAuthService(buildDio(adapter)).refresh('r-1');

      expect(result.fold((t) => t.refreshToken, (_) => null), 'r-2');
      expect(adapter.requests.single.path, '/auth/refresh');
    });
  });

  group('DioAuthService.logout', () {
    test('returns Ok on 204', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(204)]);

      final result = await DioAuthService(buildDio(adapter)).logout('r-1');

      expect(result.isOk, isTrue);
      expect(adapter.requests.single.path, '/auth/logout');
    });

    test('returns Err when the server rejects, without throwing', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(500)]);

      final result = await DioAuthService(buildDio(adapter)).logout('r-1');

      expect(result.isOk, isFalse);
      expect(result.fold((_) => null, (f) => f.kind), FailureKind.server);
    });
  });
}
