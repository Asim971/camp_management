import 'dart:ui';

import 'package:acsl_campaign/app/di/providers.dart';
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
          label: 'Approve',
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
          label: 'Approve',
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
      // no explanation for a keyboard or screen-reader user. A bare Text
      // child (as this test used to use) is not a semantics boundary, so
      // everything merges into one node and hides the real bug: a real
      // control like ElevatedButton wraps itself in its OWN Semantics
      // boundary reporting `enabled: true`, and that boundary node - not the
      // gate's - is the one a screen reader actually focuses.
      const reason = 'Only a Campaign Approver can approve this campaign.';
      await pump(
        tester,
        auth: signedIn(const {}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: reason,
          label: 'Approve',
          child: ElevatedButton(onPressed: () {}, child: const Text('Approve')),
        ),
      );

      final semantics = tester.getSemantics(find.byType(ElevatedButton));
      expect(semantics.flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        semantics.hint,
        contains(reason),
        reason:
            'the denial reason must reach the semantics tree as a hint, '
            'after the label and the disabled state, not as the label '
            'itself',
      );
    });

    testWidgets('strips the tap action so assistive tech cannot activate it', (
      tester,
    ) async {
      // The reviewer confirmed via SDK source that IgnorePointer marks the
      // node as blocking user actions, which strips SemanticsAction.tap on
      // merge - this pins that behaviour so a future Flutter upgrade cannot
      // silently regress it into a control that looks disabled but is not.
      await pump(
        tester,
        auth: signedIn(const {}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          label: 'Approve',
          child: ElevatedButton(onPressed: () {}, child: const Text('Approve')),
        ),
      );

      final semantics = tester.getSemantics(find.text('Approve'));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
    });

    testWidgets('carries a tap action when the permission is held', (
      tester,
    ) async {
      // The positive counterpart: without this, a bug that strips the tap
      // action unconditionally (rather than only when gated) would pass the
      // test above too.
      await pump(
        tester,
        auth: signedIn({Permission.campaignApprove}),
        child: PermissionGate.disabled(
          Permission.campaignApprove,
          reason: 'Only a Campaign Approver can approve this campaign.',
          label: 'Approve',
          child: ElevatedButton(onPressed: () {}, child: const Text('Approve')),
        ),
      );

      final semantics = tester.getSemantics(find.text('Approve'));
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    });
  });
}
