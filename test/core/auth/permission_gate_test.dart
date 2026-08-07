import 'dart:ui';

import 'package:acsl_campaign/app/router/app_router.dart';
import 'package:acsl_campaign/core/auth/permission_gate.dart';
import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/auth/session.dart';
import 'package:acsl_campaign/core/auth/session_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AuthState signedIn(Set<Permission> permissions) => AuthSignedIn(
    Session(
      userId: 'u-1',
      displayName: 'Test User',
      scope: AccessScope(
        roles: const {AppRole.fieldUser},
        permissions: permissions,
        organizationId: 'ORG_1',
      ),
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
  );

  Future<void> pump(
    WidgetTester tester, {
    required AuthState auth,
    required Widget child,
  }) => tester.pumpWidget(
    ProviderScope(
      overrides: [authStateProvider.overrideWith((ref) => auth)],
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );

  group('PermissionGate.hidden', () {
    testWidgets('renders the child when the permission is held', (
      tester,
    ) async {
      await pump(
        tester,
        auth: signedIn({Permission.export}),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsOneWidget);
    });

    testWidgets('renders NOTHING when the permission is missing', (
      tester,
    ) async {
      await pump(
        tester,
        auth: signedIn(const {}),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsNothing);
    });

    testWidgets('renders nothing when signed out', (tester) async {
      await pump(
        tester,
        auth: const AuthSignedOut(),
        child: const PermissionGate.hidden(
          Permission.export,
          child: Text('Analytics'),
        ),
      );

      expect(find.text('Analytics'), findsNothing);
    });
  });

  group('PermissionGate.disabled', () {
    testWidgets('renders the child untouched when the permission is held', (
      tester,
    ) async {
      var tapped = false;
      await pump(
        tester,
        auth: signedIn({Permission.campaignApprove}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Approve'),
          ),
        ),
      );

      await tester.tap(find.text('Approve'));
      expect(tapped, isTrue);
    });

    testWidgets('keeps the child VISIBLE but blocks interaction', (
      tester,
    ) async {
      // Visible-but-disabled is the whole point: a missing button leaves the
      // user unable to tell permission from lifecycle state from bug.
      var tapped = false;
      await pump(
        tester,
        auth: signedIn(const {}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          child: ElevatedButton(
            onPressed: () => tapped = true,
            child: const Text('Approve'),
          ),
        ),
      );

      expect(find.text('Approve'), findsOneWidget);
      await tester.tap(find.text('Approve'), warnIfMissed: false);
      expect(tapped, isFalse);
    });

    testWidgets('exposes the reason to a screen reader, not just a tooltip', (
      tester,
    ) async {
      // T-3.4.1's accessibility gate checks this: a mouse-only explanation is
      // no explanation for a keyboard or screen-reader user.
      const reason = 'Only a Campaign Approver can approve this campaign.';
      await pump(
        tester,
        auth: signedIn(const {}),
        child: const PermissionGate.disabled(
          Permission.campaignApprove,
          reason: reason,
          child: Text('Approve'),
        ),
      );

      final semantics = tester.getSemantics(find.text('Approve'));
      expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        tester
            .widgetList<Semantics>(find.byType(Semantics))
            .any((s) => s.properties.label?.contains(reason) ?? false),
        isTrue,
        reason: 'the denial reason must reach the semantics tree',
      );
    });
  });
}
