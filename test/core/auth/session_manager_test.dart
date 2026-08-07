import 'dart:async';

import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/auth/token_store.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth.dart';

/// [TokenStore] whose `persist` and `read` can each be held open via a
/// [Completer], to reproduce an await wide enough to straddle a signOut() -
/// e.g. a real Keystore write/read on mobile, not just a microtask sliver.
/// [FakeTokenStore] in the support file has no such gate, so this stays
/// local to the tests that specifically need one.
class _GatedTokenStore implements TokenStore {
  _GatedTokenStore([this.value]);

  String? value;
  Completer<void>? persistGate;
  Completer<void>? readGate;

  @override
  Future<void> persist(String refreshToken) async {
    // Only the call that actually captures the gate waits on it - later
    // calls must not coincidentally queue up behind the same completer, or a
    // test could look ordered for reasons that have nothing to do with
    // SessionManager's own write-ordering guarantee.
    final gate = persistGate;
    persistGate = null;
    if (gate != null) await gate.future;
    value = refreshToken;
  }

  @override
  Future<String?> read() async {
    // Snapshot before the gate, not after: a real Keystore read already
    // fetched this value the moment it was called - a concurrent clear()
    // that runs while we are slow to *return* it must not retroactively
    // change what this call reports.
    final snapshot = value;
    if (readGate != null) await readGate!.future;
    return snapshot;
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

void main() {
  SessionManager build({
    ScriptedAuthService? service,
    FakeTokenStore? tokens,
    DateTime? now,
  }) => SessionManager(
    service: service ?? ScriptedAuthService(),
    tokens: tokens ?? FakeTokenStore(),
    now: () => now ?? kTestNow,
  );

  group('signIn', () {
    test('moves to AuthSignedIn and persists the refresh token', () async {
      final tokens = FakeTokenStore();
      final manager = build(tokens: tokens);

      final result = await manager.signIn('bob', 'pw');

      expect(result.isOk, isTrue);
      expect(manager.state, isA<AuthSignedIn>());
      final session = (manager.state as AuthSignedIn).session;
      expect(session.userId, 'u-1');
      expect(session.accessToken, 'access-1');
      expect(tokens.value, 'refresh-1');
      manager.dispose();
    });

    test(
      'stays signed out and surfaces the failure on bad credentials',
      () async {
        final manager = build(
          service: ScriptedAuthService(
            loginResults: [const Err(Failure(FailureKind.unauthorized))],
          ),
        );

        final result = await manager.signIn('bob', 'wrong');

        expect(result.isOk, isFalse);
        expect(
          result.fold((_) => null, (f) => f.kind),
          FailureKind.unauthorized,
        );
        expect(manager.state, isA<AuthSignedOut>());
        manager.dispose();
      },
    );

    test(
      'rejects a token whose claims do not parse, without signing in',
      () async {
        // An unmappable role must not produce a signed-in user with an empty
        // scope - that is the silent-narrowing failure scope_claims prevents.
        final manager = build(
          service: ScriptedAuthService(
            loginResults: [
              Ok(
                testTokens(
                  claims: {
                    'userId': 'u-1',
                    'organizationId': 'ORG_1',
                    'roles': ['galactic_overlord'],
                    'permissions': <String>[],
                  },
                ),
              ),
            ],
          ),
        );

        final result = await manager.signIn('bob', 'pw');

        expect(result.isOk, isFalse);
        expect(manager.state, isA<AuthSignedOut>());
        manager.dispose();
      },
    );
  });

  group('restore', () {
    test(
      'with a stored token: passes through AuthRestoring to signed in',
      () async {
        final manager = build(tokens: FakeTokenStore('stored-r'));
        final seen = <AuthState>[];
        final sub = manager.changes.listen(seen.add);

        await manager.restore();
        await pumpEventQueue();

        expect(seen.map((s) => s.runtimeType), [AuthRestoring, AuthSignedIn]);
        expect(manager.state, isA<AuthSignedIn>());
        await sub.cancel();
        manager.dispose();
      },
    );

    test('sends the STORED token to refresh, not a fresh one', () async {
      final service = ScriptedAuthService();
      final manager = build(
        service: service,
        tokens: FakeTokenStore('stored-r'),
      );

      await manager.restore();

      expect(service.refreshTokensSeen, ['stored-r']);
      manager.dispose();
    });

    test(
      'with no stored token: goes straight to signed out, never restoring',
      () async {
        // This is the web path. Emitting AuthRestoring there would make the
        // router hold on a splash for a state web can never leave.
        final manager = build(tokens: FakeTokenStore());
        final seen = <AuthState>[];
        final sub = manager.changes.listen(seen.add);

        await manager.restore();
        await pumpEventQueue();

        expect(seen.map((s) => s.runtimeType), [AuthSignedOut]);
        await sub.cancel();
        manager.dispose();
      },
    );

    test('a rejected stored token clears storage and signs out', () async {
      final tokens = FakeTokenStore('stale-r');
      final manager = build(
        service: ScriptedAuthService(
          refreshResults: [const Err(Failure(FailureKind.unauthorized))],
        ),
        tokens: tokens,
      );

      await manager.restore();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      expect(tokens.clearCalls, greaterThan(0));
      manager.dispose();
    });
  });

  group('refresh is single-flight', () {
    test('two concurrent refreshes make exactly ONE transport call', () async {
      // The race this closes is a 401-triggered refresh colliding with a
      // proactive one. Under server-side token rotation the loser presents a
      // token the winner already consumed, signing the user out mid-task.
      final service = ScriptedAuthService()..refreshGate = Completer<void>();
      final manager = build(service: service, tokens: FakeTokenStore('r-1'));
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final first = manager.refresh();
      final second = manager.refresh();
      service.refreshGate!.complete();
      final results = await Future.wait([first, second]);

      expect(service.refreshCalls, 1);
      expect(results[0], results[1]);
      manager.dispose();
    });

    test('a later refresh after the first completes does call again', () async {
      // The guard must clear, or the session could never be renewed twice.
      final service = ScriptedAuthService();
      final manager = build(service: service, tokens: FakeTokenStore('r-1'));
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      await manager.refresh();
      await manager.refresh();

      expect(service.refreshCalls, 2);
      manager.dispose();
    });

    test('a failed refresh signs out and clears the token', () async {
      final tokens = FakeTokenStore('r-1');
      final service = ScriptedAuthService(
        refreshResults: [const Err(Failure(FailureKind.unauthorized))],
      );
      final manager = build(service: service, tokens: tokens);
      await manager.signIn('bob', 'pw');

      final token = await manager.refresh();

      expect(token, isNull);
      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      manager.dispose();
    });
  });

  group('accessTokenForRequest — proactive renewal', () {
    test('refreshes when the token expires inside the skew window', () async {
      final service = ScriptedAuthService(
        loginResults: [Ok(testTokens(validFor: const Duration(seconds: 30)))],
        refreshResults: [Ok(testTokens(access: 'access-2'))],
      );
      final manager = build(service: service);
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final token = await manager.accessTokenForRequest();

      expect(service.refreshCalls, 1);
      expect(token, 'access-2');
      manager.dispose();
    });

    test('does NOT refresh a token with plenty of life left', () async {
      // Refreshing eagerly on every request would multiply auth traffic and,
      // under rotation, invalidate tokens other in-flight requests hold.
      final service = ScriptedAuthService(
        loginResults: [Ok(testTokens(validFor: const Duration(minutes: 20)))],
      );
      final manager = build(service: service);
      await manager.signIn('bob', 'pw');
      service.refreshCalls = 0;

      final token = await manager.accessTokenForRequest();

      expect(service.refreshCalls, 0);
      expect(token, 'access-1');
      manager.dispose();
    });

    test('returns null when signed out', () async {
      final manager = build();

      expect(await manager.accessTokenForRequest(), isNull);
      manager.dispose();
    });
  });

  group('signOut', () {
    test('clears state and storage, then calls the service', () async {
      final tokens = FakeTokenStore();
      final service = ScriptedAuthService();
      final manager = build(service: service, tokens: tokens);
      await manager.signIn('bob', 'pw');

      await manager.signOut();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      expect(service.logoutCalls, 1);
      manager.dispose();
    });

    test('signs out locally even when the server call fails', () async {
      // Staying signed in because the server was unreachable is the wrong
      // failure direction on a shared field device.
      final tokens = FakeTokenStore();
      final manager = build(
        service: ScriptedAuthService(
          logoutResult: const Err(Failure(FailureKind.network)),
        ),
        tokens: tokens,
      );
      await manager.signIn('bob', 'pw');

      await manager.signOut();

      expect(manager.state, isA<AuthSignedOut>());
      expect(tokens.value, isNull);
      manager.dispose();
    });
  });

  group('generation guard — sign-out and sign-in win races', () {
    test(
      'an in-flight refresh landing after signOut cannot resurrect the session',
      () async {
        // This is the probe case from code review: a refresh already sent
        // before signOut is called must not be able to re-sign the user in,
        // or re-persist the token signOut just cleared, once it lands.
        final tokens = FakeTokenStore('r-1');
        final service = ScriptedAuthService()..refreshGate = Completer<void>();
        final manager = build(service: service, tokens: tokens);
        await manager.signIn('bob', 'pw');

        final pendingRefresh = manager.refresh();
        await manager.signOut();

        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);

        service.refreshGate!.complete();
        await pendingRefresh;

        // Assert again after the stale refresh lands, not just after
        // signOut - a test that only checks the pre-landing state would pass
        // against the buggy code too.
        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);
        manager.dispose();
      },
    );

    test(
      'a refresh that completes normally with no sign-out still works',
      () async {
        // Guards against over-correcting the fix above into "refresh never
        // emits".
        final service = ScriptedAuthService(
          refreshResults: [Ok(testTokens(access: 'access-2'))],
        );
        final manager = build(service: service, tokens: FakeTokenStore('r-1'));
        await manager.signIn('bob', 'pw');

        final token = await manager.refresh();

        expect(token, 'access-2');
        expect(manager.state, isA<AuthSignedIn>());
        expect((manager.state as AuthSignedIn).session.accessToken, 'access-2');
        manager.dispose();
      },
    );

    test('a stale refresh whose network response arrives after a new sign-in '
        'is rejected before it can clobber the new session (entry-check '
        'coverage - see the persist-after-signOut test below for the deeper '
        'in-flight-write window)', () async {
      final service = ScriptedAuthService(
        loginResults: [
          Ok(testTokens()),
          Ok(testTokens(access: 'access-2', refresh: 'refresh-2')),
        ],
      )..refreshGate = Completer<void>();
      final manager = build(service: service, tokens: FakeTokenStore());
      await manager.signIn('bob', 'pw');

      final staleRefresh = manager.refresh();
      await manager.signOut();
      await manager.signIn('bob', 'pw');

      service.refreshGate!.complete();
      await staleRefresh;

      expect(manager.state, isA<AuthSignedIn>());
      expect((manager.state as AuthSignedIn).session.accessToken, 'access-2');
      manager.dispose();
    });

    test(
      'a persist landing after signOut cannot leave a stale token behind',
      () async {
        // The narrower bug fix-round-1 left open: checking generation only at
        // function entry misses staleness that appears *during* the persist
        // write itself. On mobile that write is real Keystore I/O, wide
        // enough for a signOut() to start and finish entirely while it is
        // still in flight - which is exactly what this reproduces by gating
        // persist() open.
        final tokens = _GatedTokenStore();
        final manager = SessionManager(
          service: ScriptedAuthService(),
          tokens: tokens,
          now: () => kTestNow,
        );
        await manager.signIn('bob', 'pw');

        // Gate the NEXT persist - the one the pending refresh below will
        // attempt - so it stays in flight while signOut runs. Held locally,
        // not re-read from tokens.persistGate, since the store nulls that
        // field once a call captures it.
        final gate = Completer<void>();
        tokens.persistGate = gate;

        final pendingRefresh = manager.refresh();
        await pumpEventQueue(); // let the refresh's network call resolve and _adopt reach the gated persist
        await manager.signOut();

        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);

        gate.complete();
        await pendingRefresh;

        // Assert again after the stale persist lands, not just after
        // signOut - the entry-only check from fix round 1 passes this first
        // assertion but fails this second one, because its write already
        // landed in storage by the time it notices it is stale.
        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);
        manager.dispose();
      },
    );

    test(
      'a signOut racing a slow boot restore leaves the user signed out',
      () async {
        // Gap 2 from code review: restore() used to capture its generation
        // *after* awaiting the stored-token read, so a signOut() completing
        // entirely during that read was already folded into the epoch
        // restore captured, and nothing later invalidated it.
        final tokens = _GatedTokenStore('stored-r')
          ..readGate = Completer<void>();
        final manager = SessionManager(
          service: ScriptedAuthService(),
          tokens: tokens,
          now: () => kTestNow,
        );

        final pendingRestore = manager.restore();
        await manager.signOut();

        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);

        tokens.readGate!.complete();
        await pendingRestore;

        expect(manager.state, isA<AuthSignedOut>());
        expect(tokens.value, isNull);
        manager.dispose();
      },
    );
  });

  group('store write ordering — two independent writes cannot invert', () {
    test('a stale sign-in whose persist parks mid-flight cannot leave storage '
        'disagreeing with a newer sign-in', () async {
      // Round 2's generation check protects a single write against a
      // later signOut/emit, but two SEPARATE writes (one per sign-in) race
      // each other on completion order, not call order - checking
      // generation says nothing about which write's I/O lands last. Gate
      // only the first persist so it parks mid-flight while a second,
      // fully independent sign-in runs its own persist to completion.
      final tokens = _GatedTokenStore();
      final manager = SessionManager(
        service: ScriptedAuthService(
          loginResults: [
            Ok(testTokens()), // user 1: access-1 / refresh-1
            Ok(testTokens(access: 'access-2', refresh: 'refresh-2')),
          ],
        ),
        tokens: tokens,
        now: () => kTestNow,
      );

      // Held locally, not re-read from tokens.persistGate: the store nulls
      // its own field once a call captures it, so completing through a
      // fresh field read could silently complete nothing if ordering
      // already broke and a second call consumed the gate first.
      final gate = Completer<void>();
      tokens.persistGate = gate;
      final signIn1 = manager.signIn('user1', 'pw');
      await pumpEventQueue(); // let it reach the gated persist('refresh-1')

      final signIn2 = manager.signIn('user2', 'pw');
      await pumpEventQueue(); // its persist('refresh-2') is now queued too

      gate.complete();
      await signIn1;
      await signIn2;

      // State and storage must agree - both must point at user 2. State
      // alone passing here is not enough: the bug this closes is exactly
      // storage disagreeing with state (see fix round 3 in the report).
      expect(manager.state, isA<AuthSignedIn>());
      final session = (manager.state as AuthSignedIn).session;
      expect(session.accessToken, 'access-2');
      expect(tokens.value, 'refresh-2');
      manager.dispose();
    });

    test('the write queue orders a clear enqueued after a persist, not only '
        'two persists', () async {
      // Proves the queue orders *mutations*, not merely two calls of the
      // same kind. A THIRD sign-in matters here, not just two: with only
      // one persist (user 1) and one clear (user 2), _persistIfCurrent's
      // own "nothing newer queued" fallback (_lastPersistGeneration) would
      // coincidentally also fix the outcome, proving nothing about the
      // queue itself. Interposing user 2's own valid persist moves
      // _lastPersistGeneration past user 1's, neutralising that fallback,
      // so only the queue's ordering is left to make user 3's clear beat
      // user 1's parked, stale persist to the finish.
      final tokens = _GatedTokenStore();
      final manager = SessionManager(
        service: ScriptedAuthService(
          loginResults: [
            Ok(testTokens()), // user 1: parks inside persist('refresh-1')
            Ok(testTokens(access: 'access-2', refresh: 'refresh-2')),
            Ok(
              testTokens(
                // Unmappable role: _adopt's claims-parse-failure branch
                // enqueues a clear() instead of a persist().
                claims: {
                  'userId': 'u-3',
                  'organizationId': 'ORG_1',
                  'roles': ['galactic_overlord'],
                  'permissions': <String>[],
                },
              ),
            ),
          ],
        ),
        tokens: tokens,
        now: () => kTestNow,
      );

      final gate = Completer<void>();
      tokens.persistGate = gate;
      final signIn1 = manager.signIn('user1', 'pw');
      await pumpEventQueue(); // parks inside persist('refresh-1')

      final signIn2 = manager.signIn('user2', 'pw');
      await pumpEventQueue(); // its persist('refresh-2') queues behind it

      final signIn3 = manager.signIn('user3', 'pw');
      await pumpEventQueue(); // its rejection queues a clear() behind both

      gate.complete();
      await signIn1;
      await signIn2;
      await signIn3;

      // Enqueue order was persist(refresh-1), persist(refresh-2), clear() -
      // the clear must have the final word.
      expect(tokens.value, isNull);
      manager.dispose();
    });
  });
}
