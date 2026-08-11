import 'dart:convert';
import 'dart:typed_data';

import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/flavors.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

/// Regression net for the provider cycle that broke every real-auth sign-in
/// (PR #6, e2e `locale`/`realAuth`, 2026-08-11).
///
/// `dioProvider`'s AuthInterceptor callbacks did
/// `ref.read(authStateProvider)` / `ref.read(sessionManagerProvider)`, whose
/// dependency chains lead back to `dioProvider` itself
/// (`authState -> sessionManager -> authService -> dio`). Riverpod checks for
/// cycles AT READ TIME, not just at build time, so the first request through
/// the real `DioAuthService` — the login itself — threw
/// `CircularDependencyError` inside `onRequest`. Dio wrapped it as
/// `DioExceptionType.unknown`, `mapDioError` classified it
/// `FailureKind.unknown`, and the UI showed the generic "Sign-in could not
/// be completed." — while `FakeAuthService` configs never noticed, because
/// the fake never watches `dioProvider` and the cycle edge never exists.
///
/// Every other auth test overrides `sessionManagerProvider` or
/// `authStateProvider`, which SEVERS the dependency edges and hides exactly
/// this defect. This file therefore hand-rolls a container and overrides
/// nothing on the auth path except the platform-plugin leaf
/// (`tokenStoreProvider`) — the same reasoning `composition_root_test.dart`
/// documents for the database wiring.
class _CannedLoginAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    return ResponseBody.fromString(
      jsonEncode({
        'accessToken': 'access-1',
        'refreshToken': 'refresh-1',
        'expiresInSeconds': 900,
        'claims': {
          'userId': 'seed-campaign_creator',
          'displayName': 'E2E campaign creator',
          'organizationId': 'org-e2e',
          'territoryIds': ['terr-dhaka-north'],
          'roles': ['campaign_creator'],
          'permissions': ['campaign_create', 'bulk_import', 'export'],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('real-auth sign-in through the un-overridden provider graph reaches the '
      'transport and signs in (no CircularDependencyError)', () async {
    final adapter = _CannedLoginAdapter();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          const AppConfig(
            flavor: Flavor.dev,
            apiBaseUrl: 'http://test',
            mediaHost: 'http://media',
            e2e: true,
            e2eRealAuth: true,
          ),
        ),
        // The one platform leaf flutter_test cannot build (secure storage
        // plugin). A leaf: overriding it severs no auth-path edges.
        tokenStoreProvider.overrideWithValue(FakeTokenStore()),
      ],
    );
    addTearDown(container.dispose);

    // The REAL dio instance the un-overridden graph wires; only its
    // transport is swapped so no socket is needed.
    container.read(dioProvider).httpClientAdapter = adapter;

    final result = await container
        .read(sessionManagerProvider)
        .signIn('campaign_creator', 'Test1234!');

    expect(
      result.isOk,
      isTrue,
      reason:
          'sign-in through the production wiring must succeed; a failure '
          'here with calls == 0 is the interceptor dying before the '
          'transport — the provider-cycle defect this test pins',
    );
    expect(
      adapter.calls,
      1,
      reason: 'the login request must actually reach the transport',
    );
    expect(container.read(authStateProvider), isA<AuthSignedIn>());
  });
}
