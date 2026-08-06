import 'package:acsl_campaign/core/network/auth_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/scripted_adapter.dart';

void main() {
  group('AuthInterceptor 401 refresh', () {
    test('replays the request against the configured baseUrl', () async {
      // The bug this pins: replaying through a bare Dio() drops baseUrl, and
      // every repository calls relative paths, so the replay would go nowhere.
      final adapter = ScriptedAdapter([
        const ScriptedReply.status(401),
        const ScriptedReply.status(200),
      ]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

      var refreshCalls = 0;
      var authLost = false;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'stale',
          refreshToken: () async {
            refreshCalls++;
            return 'fresh';
          },
          onAuthLost: () => authLost = true,
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      final res = await dio.get<void>('/campaigns');

      expect(res.statusCode, 200);
      expect(refreshCalls, 1);
      expect(authLost, isFalse);
      expect(adapter.callCount, 2);
      expect(
        adapter.requests.last.uri.toString(),
        'https://api.test/campaigns',
      );
      expect(adapter.requests.last.headers['Authorization'], 'Bearer fresh');
    });

    test('signals auth lost when refresh yields no token', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(401)]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;

      var authLost = false;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'stale',
          refreshToken: () async => null,
          onAuthLost: () => authLost = true,
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      await expectLater(
        dio.get<void>('/campaigns'),
        throwsA(isA<DioException>()),
      );
      expect(authLost, isTrue);
      expect(adapter.callCount, 1);
    });

    test('attaches the bearer token when one is available', () async {
      final adapter = ScriptedAdapter([const ScriptedReply.status(200)]);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
        ..httpClientAdapter = adapter;
      dio.interceptors.add(
        AuthInterceptor(
          readAccessToken: () => 'token-1',
          refreshToken: () async => null,
          onAuthLost: () {},
          replay: (options) => dio.fetch<dynamic>(options),
        ),
      );

      await dio.get<void>('/campaigns');

      expect(
        adapter.requests.single.headers['Authorization'],
        'Bearer token-1',
      );
    });
  });
}
