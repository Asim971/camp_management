import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/campaign_approval/application/approval_controller.dart';
import 'package:acsl_campaign/features/campaign_approval/presentation/campaign_approval_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// Task 6b, third of the three screens that rendered `status.name`. This is the
/// site the brief singles out: an approver reviewing a submitted plan saw the
/// chip read "pendingApproval".
class _FixedApprovalController extends ApprovalController {
  @override
  Future<Campaign> build(String campaignId) async => const Campaign(
    id: 'c-1',
    name: 'Boro season seminar',
    type: 'seminar',
    organizationId: 'ORG_1',
    status: CampaignStatus.pendingApproval,
    // Not 'u-1': matching the signed-in user would trip the segregation-of-
    // duties banner, which is irrelevant here and adds unrelated text.
    ownerId: 'someone-else',
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    final container = buildTestContainer(
      permissions: {Permission.campaignApprove},
      overrides: [
        approvalControllerProvider.overrideWith(_FixedApprovalController.new),
      ],
    );

    final router = GoRouter(
      initialLocation: '/campaigns/c-1/approve',
      routes: [
        GoRoute(
          path: '/campaigns/:id/approve',
          builder: (_, state) =>
              CampaignApprovalScreen(campaignId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: locale,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the plan summary chip renders Bengali under Locale(bn)', (
    tester,
  ) async {
    await pump(tester, const Locale('bn'));

    expect(find.text('অনুমোদনের অপেক্ষায়'), findsOneWidget);
    expect(find.text('Pending approval'), findsNothing);
    expect(find.text('pendingApproval'), findsNothing);
  });

  testWidgets('the plan summary chip renders the English label under '
      'Locale(en), not the raw enum name', (tester) async {
    await pump(tester, const Locale('en'));

    expect(find.text('Pending approval'), findsOneWidget);
    expect(find.text('pendingApproval'), findsNothing);
    expect(find.text('অনুমোদনের অপেক্ষায়'), findsNothing);
  });
}
