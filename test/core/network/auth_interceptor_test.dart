import 'package:acsl_campaign/core/network/auth_interceptor.dart';
import 'package:acsl_campaign/core/network/retry_interceptor.dart';
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

    test(
      'Finding 1: RetryInterceptor retries re-read live tokens, not cached headers',
      () async {
        // Regression: without the replay flag, onRequest would see the Authorization
        // header from the first attempt and skip re-reading the live token on retry.
        // This test verifies RetryInterceptor retries get fresh tokens.
        var readCount = 0;
        final tokenByRead = ['v1', 'v2'];

        final adapter = ScriptedAdapter([
          const ScriptedReply.status(503), // Retryable transient error
          const ScriptedReply.status(200), // Retry succeeds
        ]);
        final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
          ..httpClientAdapter = adapter;

        dio.interceptors.addAll([
          AuthInterceptor(
            readAccessToken: () {
              final token =
                  tokenByRead[readCount.clamp(0, tokenByRead.length - 1)];
              readCount++;
              return token;
            },
            refreshToken: () async => null,
            onAuthLost: () {},
            replay: (options) => dio.fetch<dynamic>(options),
          ),
          // RetryInterceptor with instant delay so test doesn't sleep
          RetryInterceptor(dio: dio, delay: (_) => Future<void>.value()),
        ]);

        final res = await dio.get<void>('/campaigns');

        expect(res.statusCode, 200);
        // First request (503): reads v1
        // Retry: reads v2 (not v1 from header cache)
        expect(
          adapter.requests.last.headers['Authorization'],
          'Bearer v2',
          reason:
              'Retry should use fresh token from readAccessToken, not cached header',
        );
      },
    );
  });
}
