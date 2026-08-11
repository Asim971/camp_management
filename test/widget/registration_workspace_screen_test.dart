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
}
