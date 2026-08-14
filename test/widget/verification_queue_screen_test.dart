import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/verification/verification.dart';
import 'package:acsl_campaign/domain/verification/verification_case.dart';
import 'package:acsl_campaign/domain/verification/verification_repository.dart';
import 'package:acsl_campaign/features/verification_queue/presentation/verification_queue_screen.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _escalatedId = 'ATT-ESCALATED';
const _unassignedId = 'ATT-UNASSIGNED';

/// A signed-in verifier. [withOverride] controls whether the session holds
/// `verification_override` — the permission the Escalated tab gates on.
AuthState _signedInVerifier({required bool withOverride}) => AuthSignedIn(
  Session(
    userId: 'u-verifier',
    displayName: 'Test Verifier',
    scope: AccessScope(
      roles: const {AppRole.crmVerifier},
      permissions: {
        Permission.verificationDecide,
        if (withOverride) Permission.verificationOverride,
      },
      organizationId: 'ORG_1',
    ),
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);

/// AppShell derives the selected nav index from GoRouterState.of(context),
/// which requires the widget under test to be built by an actual GoRouter
/// route rather than a bare MaterialApp(home: ...) (same reason
/// crm_case_screen_test.dart wraps in a router).
Widget _wrapInRouter() {
  final router = GoRouter(
    initialLocation: '/verification',
    routes: [
      GoRoute(
        path: '/verification',
        builder: (_, __) => const VerificationQueueScreen(),
        routes: [
          GoRoute(
            path: 'cases/:id',
            builder: (_, state) =>
                Scaffold(body: Text('case ${state.pathParameters['id']}')),
          ),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// In-memory [VerificationRepository] so the real [VerificationQueueNotifier]
/// runs against fixed data instead of a live Dio client. Returns the same
/// fixed list regardless of [QueueFilter] — the screen's tab switching is not
/// what this test is about; the fake just needs to be a faithful stand-in for
/// the full interface.
class _FakeVerificationRepository implements VerificationRepository {
  final List<String> claimedIds = [];
  final List<String> releasedIds = [];

  final _items = <VerificationQueueItem>[
    VerificationQueueItem(
      attendanceId: _escalatedId,
      carpenterName: 'Karim Uddin',
      campaignName: 'Campaign A',
      age: const Duration(hours: 5),
      band: MatchBand.medium,
      referenceSource: ReferenceSource.verifiedProfilePhoto,
      assigneeId: 'u-someone-else',
      escalatedAt: DateTime(2026, 8, 10),
    ),
    const VerificationQueueItem(
      attendanceId: _unassignedId,
      carpenterName: 'Rina Akter',
      campaignName: 'Campaign B',
      age: Duration(minutes: 20),
      band: MatchBand.high,
      referenceSource: ReferenceSource.authorizedNidPhoto,
      assigneeId: null,
      escalatedAt: null,
    ),
  ];

  @override
  Future<Result<List<VerificationQueueItem>>> queue({
    required QueueFilter filter,
  }) async => Ok(_items);

  @override
  Future<Result<void>> claim(String attendanceId) async {
    claimedIds.add(attendanceId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> release(String attendanceId) async {
    releasedIds.add(attendanceId);
    return const Ok(null);
  }

  @override
  Future<Result<VerificationCase>> getCase(String attendanceId) =>
      throw UnimplementedError('not used by VerificationQueueScreen');

  @override
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
    TraceId? trace,
  }) => throw UnimplementedError('not used by VerificationQueueScreen');
}

/// Finds the [Semantics] node carrying a given stable test id (the same
/// `Semantics(identifier: …)` convention Maestro flows key off).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  testWidgets(
    'verification_queue_screen: renders one item per queue entry, the '
    'always-present tabs, and the Escalated tab when the session holds '
    'verification_override',
    (tester) async {
      final repo = _FakeVerificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verificationRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWith(
              (ref) => _signedInVerifier(withOverride: true),
            ),
          ],
          child: _wrapInRouter(),
        ),
      );
      await tester.pumpAndSettle();

      expect(_byIdentifier('queue_item_$_escalatedId'), findsOneWidget);
      expect(_byIdentifier('queue_item_$_unassignedId'), findsOneWidget);

      expect(_byIdentifier('queue_tab_all'), findsOneWidget);
      expect(_byIdentifier('queue_tab_mine'), findsOneWidget);
      expect(_byIdentifier('queue_tab_unassigned'), findsOneWidget);
      expect(
        _byIdentifier('queue_tab_escalated'),
        findsOneWidget,
        reason: 'the session holds verification_override',
      );

      expect(_byIdentifier('queue_escalated_$_escalatedId'), findsOneWidget);
    },
  );

  testWidgets(
    'verification_queue_screen: the Escalated tab is absent for a session '
    'without verification_override',
    (tester) async {
      final repo = _FakeVerificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verificationRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWith(
              (ref) => _signedInVerifier(withOverride: false),
            ),
          ],
          child: _wrapInRouter(),
        ),
      );
      await tester.pumpAndSettle();

      expect(_byIdentifier('queue_tab_all'), findsOneWidget);
      expect(_byIdentifier('queue_tab_mine'), findsOneWidget);
      expect(_byIdentifier('queue_tab_unassigned'), findsOneWidget);
      expect(_byIdentifier('queue_tab_escalated'), findsNothing);
    },
  );

  testWidgets(
    'verification_queue_screen: an unassigned item shows queue_claim, and '
    'tapping it calls the repository\'s claim()',
    (tester) async {
      final repo = _FakeVerificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verificationRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWith(
              (ref) => _signedInVerifier(withOverride: true),
            ),
          ],
          child: _wrapInRouter(),
        ),
      );
      await tester.pumpAndSettle();

      final claimFinder = _byIdentifier('queue_claim_$_unassignedId');
      expect(claimFinder, findsOneWidget);

      // The escalated (assigned-to-someone-else) item shows neither claim nor
      // release — it belongs to another verifier.
      expect(_byIdentifier('queue_claim_$_escalatedId'), findsNothing);
      expect(_byIdentifier('queue_release_$_escalatedId'), findsNothing);

      await tester.tap(claimFinder);
      await tester.pumpAndSettle();

      expect(repo.claimedIds, [_unassignedId]);
    },
  );
}
