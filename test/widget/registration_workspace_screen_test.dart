import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/registration/registration.dart';
import 'package:acsl_campaign/features/registration/application/registration_controller.dart';
import 'package:acsl_campaign/features/registration/presentation/registration_workspace_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';

/// Seeds the search results with one already-resolved carpenter so the test
/// exercises the real [RegistrationController.addToBasket] / basket-state
/// wiring without driving the debounced search field or a network repository
/// — the only thing overridden is the initial `build()`.
class _SeededController extends RegistrationController {
  _SeededController(this._seed);
  final RegisteredCarpenter _seed;

  @override
  RegistrationState build(String campaignId) =>
      RegistrationState(results: AsyncData([_seed]));
}

const _person = RegisteredCarpenter(
  id: 'c-1',
  name: 'Karim Uddin',
  displayId: 'CARP-••1234',
  phoneSuffix: '1234',
  territory: 'Dhaka',
  attendanceState: AttendanceStatus.notCaptured,
);

/// Resolves [RegistrationController.requestNewProfile] locally instead of
/// through [registrationRepositoryProvider] — the profile-request sheet's
/// crash (below) is about the sheet's OWN controller/Navigator lifecycle, not
/// about what the repository returns, so this sidesteps network plumbing the
/// same way [_SeededController] sidesteps `searchMaster`.
class _NoopProfileController extends RegistrationController {
  @override
  RegistrationState build(String campaignId) => const RegistrationState();

  @override
  Future<void> requestNewProfile(String name, String phone) async {
    state = state.copyWith(
      basket: {
        ...state.basket,
        'new-1': const RegisteredCarpenter(
          id: 'new-1',
          name: 'Flow Person',
          displayId: 'CARP-PENDING',
          phoneSuffix: '0001',
          territory: 'Pending',
          attendanceState: AttendanceStatus.notCaptured,
        ),
      },
      message: 'Profile request submitted — pending sync',
    );
  }
}

/// Finds the [Semantics] node carrying a given stable test id (the same
/// `Semantics(identifier: …)` convention Maestro flows key off).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Widget _wrapInRouter(String campaignId) {
  final router = GoRouter(
    initialLocation: '/campaigns/$campaignId/register',
    routes: [
      GoRoute(
        path: '/campaigns/:id/register',
        builder: (_, state) => RegistrationWorkspaceScreen(
          campaignId: state.pathParameters['id']!,
        ),
      ),
    ],
  );
  return MaterialApp.router(
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    routerConfig: router,
  );
}

void main() {
  testWidgets(
    'registration_add_<id> reports enabled=false once the carpenter is in '
    'the basket, not just isEnabled: none (the Android AccessibilityBridge '
    'reads a bare Semantics(identifier:) node with no enabled state as '
    'enabled=true — see bmd_button.dart:44-59)',
    (tester) async {
      // Disposed at the end of the body: the framework's "a SemanticsHandle
      // was active at the end of the test" check runs before tearDowns.
      final handle = tester.ensureSemantics();

      final container = buildTestContainer(
        permissions: const {},
        overrides: [
          registrationControllerProvider.overrideWith(
            () => _SeededController(_person),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapInRouter('camp-1'),
        ),
      );
      await tester.pumpAndSettle();

      final addFinder = _byIdentifier('registration_add_c-1');
      expect(addFinder, findsOneWidget);

      expect(
        tester.getSemantics(addFinder),
        matchesSemantics(
          identifier: 'registration_add_c-1',
          hasEnabledState: true,
          isEnabled: true,
        ),
        reason: 'not yet in the basket — the add action is available',
      );

      await tester.tap(
        find.descendant(of: addFinder, matching: find.byType(IconButton)),
      );
      await tester.pump();

      expect(
        tester.getSemantics(addFinder),
        matchesSemantics(
          identifier: 'registration_add_c-1',
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason:
            'now in the basket — the identifier node Maestro finds by id: '
            'must say so itself, non-vacuously (deleting `enabled: '
            '!inBasket` turns this into isEnabled: none, which '
            'matchesSemantics(hasEnabledState: true) rejects)',
      );

      handle.dispose();
    },
  );

  testWidgets(
    'profile-request sheet survives its own exit animation — regression for '
    'the framework.dart:6268 "_dependents.isEmpty" red screen PR #7\'s e2e '
    'flow hit tapping profile_submit (registration_workspace_screen.dart\'s '
    '_showRequestProfileSheet used to dispose its TextEditingControllers the '
    'instant showBmdSideSheet\'s awaited Future resolved — which is when '
    'Navigator.pop completes the route, NOT when its reverse transition '
    'finishes painting the still-mounted BmdFields)',
    (tester) async {
      final container = buildTestContainer(
        permissions: const {},
        overrides: [
          registrationControllerProvider.overrideWith(
            () => _NoopProfileController(),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapInRouter('camp-1'),
        ),
      );
      await tester.pumpAndSettle();

      // Default state.results is AsyncData([]) — the empty-state's "Request
      // new profile" affordance is already showing, no search needed.
      await tester.tap(find.text('Request new profile'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: _byIdentifier('profile_name'),
          matching: find.byType(TextFormField),
        ),
        'Crash Repro',
      );
      await tester.enterText(
        find.descendant(
          of: _byIdentifier('profile_phone'),
          matching: find.byType(TextFormField),
        ),
        '+8801799990001',
      );

      await tester.tap(find.text('Submit request'));
      // Pumps every frame of the sheet's exit transition to completion —
      // exactly the window the real e2e run's crash happened in (the sheet
      // was still animating out when the disposed-too-early controllers were
      // read). A prior instant `pump()` isn't enough: the assertion fires
      // partway through the reverse animation, not on the first frame.
      await tester.pumpAndSettle();

      // The sheet is gone and the request landed in the basket — the crash
      // this regresses left the whole screen showing framework.dart's red
      // error text instead.
      expect(find.text('Submit request'), findsNothing);
      expect(find.textContaining('Registration basket (1)'), findsOneWidget);
    },
  );
}
