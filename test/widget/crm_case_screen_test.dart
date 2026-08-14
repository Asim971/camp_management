import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:acsl_campaign/core/result/result.dart';
import 'package:acsl_campaign/core/trace/trace_id.dart';
import 'package:acsl_campaign/domain/verification/verification.dart';
import 'package:acsl_campaign/domain/verification/verification_case.dart';
import 'package:acsl_campaign/domain/verification/verification_repository.dart';
import 'package:acsl_campaign/features/crm_case/presentation/crm_case_screen.dart';
import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/single_primary.dart';

/// A signed-in verifier, holding the permission the verification case screen
/// itself gates on. AppShell (which CrmCaseScreen now renders through) reads
/// [authStateProvider] for its destinations and account menu.
AuthState _signedInVerifier() => AuthSignedIn(
  Session(
    userId: 'u-verifier',
    displayName: 'Test Verifier',
    scope: const AccessScope(
      roles: {AppRole.crmVerifier},
      permissions: {Permission.verificationDecide},
      organizationId: 'ORG_1',
    ),
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  ),
);

/// AppShell derives the selected nav index from GoRouterState.of(context),
/// which requires the widget under test to be built by an actual GoRouter
/// route rather than a bare MaterialApp(home: ...).
Widget _wrapInRouter(String attendanceId) {
  final router = GoRouter(
    initialLocation: '/verification/cases/$attendanceId',
    routes: [
      GoRoute(
        path: '/verification/cases/:id',
        builder: (_, state) =>
            CrmCaseScreen(attendanceId: state.pathParameters['id']!),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// In-memory [VerificationRepository] so the real [CrmCaseController] runs
/// against fixed data instead of a live Dio client — no network stack needed
/// to exercise the screen's decision gating.
class _FakeVerificationRepository implements VerificationRepository {
  VerificationDecision? lastDecision;

  @override
  Future<Result<List<VerificationQueueItem>>> queue({
    required QueueFilter filter,
  }) => throw UnimplementedError('not used by CrmCaseScreen');

  @override
  Future<Result<void>> claim(String attendanceId) =>
      throw UnimplementedError('not used by CrmCaseScreen');

  @override
  Future<Result<void>> release(String attendanceId) =>
      throw UnimplementedError('not used by CrmCaseScreen');

  @override
  Future<Result<VerificationCase>> getCase(String attendanceId) async {
    return Ok(
      VerificationCase(
        attendanceId: attendanceId,
        version: 1,
        status: AttendanceStatus.crmReview,
        carpenterName: 'Karim Uddin',
        carpenterIdMasked: '••••1234',
        campaignName: 'Test Campaign',
        sessionName: 'Session A',
        capturedAt: DateTime(2026, 7, 30),
        capturedImageUrl: 'https://example.test/captured.png',
        machine: const MachineResult(
          band: MatchBand.high,
          referenceSource: ReferenceSource.verifiedProfilePhoto,
        ),
      ),
    );
  }

  @override
  Future<Result<void>> decide(
    VerificationDecision decision, {
    required int expectedVersion,
    TraceId? trace,
  }) async {
    lastDecision = decision;
    return const Ok(null);
  }
}

/// Finds the [Semantics] node carrying a given stable test id (the same
/// `Semantics(identifier: …)` convention Maestro flows key off, per
/// TESTING_MAESTRO.md §3.1).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

void main() {
  testWidgets(
    'crm_case_screen: Submit stays disabled until an outcome is chosen; a '
    'plain approve needs no reason, and decide() carries that outcome '
    '(T-0.1.3 migration coverage for the RadioGroup/groupValue '
    'hand-migration)',
    (tester) async {
      // CrmCaseScreen only lays the decision panel out in a fixed (always
      // built) Row at desktop widths; below that it stacks everything in a
      // lazy ListView, which never inflates the off-screen Decision panel at
      // the default 800x600 test surface. Force a desktop-width surface so
      // the panel actually exists in the widget tree.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _FakeVerificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verificationRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWith((ref) => _signedInVerifier()),
          ],
          child: _wrapInRouter('ATT-1'),
        ),
      );
      await tester.pumpAndSettle();

      final submitFinder = find.widgetWithText(FilledButton, 'Submit decision');
      expect(
        tester.widget<FilledButton>(submitFinder).onPressed,
        isNull,
        reason: 'no outcome and no reason yet',
      );

      // Tap the "Approve" radio tile via its stable Semantics identifier —
      // the same id Maestro flows use (crm_outcome_approved).
      final approveFinder = _byIdentifier('crm_outcome_approved');
      expect(approveFinder, findsOneWidget);
      await tester.tap(approveFinder);
      await tester.pump();

      expect(
        tester.widget<FilledButton>(submitFinder).onPressed,
        isNotNull,
        reason: 'a plain approve needs no reason',
      );

      await tester.enterText(find.byType(TextField), 'Matches profile photo.');
      await tester.pump();

      expect(
        tester.widget<FilledButton>(submitFinder).onPressed,
        isNotNull,
        reason: 'an outcome is set and the optional reason was filled in too',
      );

      await tester.tap(submitFinder);
      await tester.pumpAndSettle();

      expect(repo.lastDecision, isNotNull);
      expect(repo.lastDecision!.outcome, VerificationOutcome.approved);
      expect(repo.lastDecision!.reason, 'Matches profile photo.');

      expectSinglePrimaryAction(tester);
    },
  );

  testWidgets(
    'crm_case_screen: choosing a different outcome (Reject) is what decide() '
    'receives — proves the radio group drives state, not just its presence',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final repo = _FakeVerificationRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            verificationRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWith((ref) => _signedInVerifier()),
          ],
          child: _wrapInRouter('ATT-2'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_byIdentifier('crm_outcome_rejected'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Face mismatch.');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Submit decision'));
      await tester.pumpAndSettle();

      expect(repo.lastDecision!.outcome, VerificationOutcome.rejected);

      expectSinglePrimaryAction(tester);
    },
  );
}
