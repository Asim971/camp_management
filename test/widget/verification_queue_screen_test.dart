import 'package:acsl_campaign/app/di/providers.dart';
import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/app/theme/tokens.dart';
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
///
/// [reducedMotion] applies the OS "reduce motion" signal inside
/// `MaterialApp.router`'s own `builder`, below the app's view-derived
/// `MediaQuery` — an ancestor `MediaQuery` placed outside `MaterialApp.router`
/// would be replaced by the one the app builds from the test view, per
/// Flutter's `WidgetsApp` wiring (mirrors
/// `dashboard_reduced_motion_test.dart`).
Widget _wrapInRouter({bool reducedMotion = false}) {
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
  return MaterialApp.router(
    routerConfig: router,
    builder: reducedMotion
        ? (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          )
        : null,
  );
}

/// In-memory [VerificationRepository] so the real [VerificationQueueNotifier]
/// runs against fixed data instead of a live Dio client. Returns the same
/// fixed list regardless of [QueueFilter] — the screen's tab switching is not
/// what this test is about; the fake just needs to be a faithful stand-in for
/// the full interface.
class _FakeVerificationRepository implements VerificationRepository {
  /// [items] defaults to the standard escalated/unassigned fixture used by
  /// most of this file's tests; pass a custom list for tests (e.g. the S1
  /// urgency ramp) that need specific ages/bands.
  _FakeVerificationRepository({List<VerificationQueueItem>? items})
    : _items = items ?? _defaultItems;

  final List<String> claimedIds = [];
  final List<String> releasedIds = [];

  final List<VerificationQueueItem> _items;

  static final _defaultItems = <VerificationQueueItem>[
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
  // Slice 2 RD2.D4 adds a `ScreenHero` above the filter tabs; at the default
  // 800x600 test surface that leaves too little vertical room for two full
  // queue cards to render without scrolling, which made
  // `tester.tap(claimFinder)` below miss its target. Widen the surface the
  // same way `crm_case_screen_test.dart` does for an analogous
  // desktop-width-dependent layout — this changes only how much screen the
  // widget gets, not any assertion any test makes.
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 900);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.views.first.reset();
  });

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

  testWidgets('S1 urgency ramp: a tile past the 24h window renders its '
      '"Waiting" label in the error tone at wght 600; a fresh tile does not', (
    tester,
  ) async {
    final repo = _FakeVerificationRepository(
      items: const [
        VerificationQueueItem(
          attendanceId: 'CASE_OVERDUE',
          carpenterName: 'Overdue Carpenter',
          campaignName: 'Campaign A',
          age: Duration(hours: 25),
          band: MatchBand.medium,
          referenceSource: ReferenceSource.verifiedProfilePhoto,
          assigneeId: null,
          escalatedAt: null,
        ),
        VerificationQueueItem(
          attendanceId: 'CASE_FRESH',
          carpenterName: 'Fresh Carpenter',
          campaignName: 'Campaign B',
          age: Duration(hours: 2),
          band: MatchBand.high,
          referenceSource: ReferenceSource.authorizedNidPhoto,
          assigneeId: null,
          escalatedAt: null,
        ),
      ],
    );

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

    final overdue = tester.widget<Text>(find.text('Waiting 1d'));
    final fresh = tester.widget<Text>(find.text('Waiting 2h 0m'));
    final errorColor = bmdTheme(
      brightness: Brightness.light,
    ).extension<BmdTokens>()!.error;
    expect(overdue.style?.color, errorColor);
    expect(
      overdue.style?.fontVariations,
      contains(const FontVariation('wght', 600)),
    );
    expect(fresh.style?.color, isNot(errorColor));
  });

  testWidgets('frozen identifiers survive the redesign', (tester) async {
    final repo = _FakeVerificationRepository(
      items: const [
        VerificationQueueItem(
          attendanceId: 'CASE_A',
          carpenterName: 'Case A Carpenter',
          campaignName: 'Campaign A',
          age: Duration(hours: 3),
          band: MatchBand.high,
          referenceSource: ReferenceSource.authorizedNidPhoto,
          assigneeId: null,
          escalatedAt: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verificationRepositoryProvider.overrideWithValue(repo),
          authStateProvider.overrideWith(
            (ref) => _signedInVerifier(withOverride: true),
          ),
        ],
        child: _wrapInRouter(reducedMotion: true),
      ),
    );
    await tester.pumpAndSettle();

    for (final id in [
      'queue_tab_all',
      'queue_tab_mine',
      'queue_tab_unassigned',
      'queue_item_CASE_A',
      'queue_claim_CASE_A',
    ]) {
      expect(
        _byIdentifier(id),
        findsOneWidget,
        reason: 'identifier $id must survive (Maestro contract)',
      );
    }
  });

  testWidgets('reduced motion renders the full list in a single pump', (
    tester,
  ) async {
    final repo = _FakeVerificationRepository(
      items: const [
        VerificationQueueItem(
          attendanceId: 'CASE_A',
          carpenterName: 'Case A Carpenter',
          campaignName: 'Campaign A',
          age: Duration(hours: 3),
          band: MatchBand.high,
          referenceSource: ReferenceSource.authorizedNidPhoto,
          assigneeId: null,
          escalatedAt: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          verificationRepositoryProvider.overrideWithValue(repo),
          authStateProvider.overrideWith(
            (ref) => _signedInVerifier(withOverride: true),
          ),
        ],
        child: _wrapInRouter(reducedMotion: true),
      ),
    );

    // Exactly one pump — no pumpAndSettle — the whole point of the
    // assertion: reduced motion must hold on the very first paint.
    await tester.pump();

    expect(_byIdentifier('queue_item_CASE_A'), findsOneWidget);
  });
}
