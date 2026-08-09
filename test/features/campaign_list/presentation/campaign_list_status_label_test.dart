import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/core/design_system/status_chip.dart';
import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/campaign/campaign_repository.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/campaign_list/application/campaign_list_notifier.dart';
import 'package:acsl_campaign/features/campaign_list/presentation/campaign_list_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// Task 6b: every status chip in the app rendered `status.name`, so a user saw
/// the raw camelCase Dart identifier — "pendingApproval" where a label belongs —
/// and the five `label(AppL10n)` extensions Tasks 1-2 built had zero call sites
/// in `lib/`. Nothing observable on any screen depended on the locale, so the
/// whole localization pipeline could have been deleted and the suite would have
/// stayed green.
///
/// These tests close that gap at the only place it matters: the pixels. They
/// pump the real [CampaignListScreen] under `Locale('bn')` and assert a real
/// Bengali glyph reaches the chip, and that NEITHER the English form NOR the raw
/// enum identifier does — a partial fallback (bn locale, English bundle) or a
/// site left on `.name` would otherwise read as success.
///
/// **The Bengali string asserted here is a contract with Task 12's Maestro
/// flow**, which asserts the same "খসড়া" (campaignStatus_draft) on an Android
/// emulator.
class _OneDraftCampaignNotifier extends CampaignListNotifier {
  @override
  Future<Paged<Campaign>> build() async => const Paged(
    items: [
      Campaign(
        id: 'c-1',
        name: 'Boro season seminar',
        type: 'seminar',
        organizationId: 'ORG_1',
        status: CampaignStatus.draft,
        ownerId: 'u-1',
      ),
    ],
    total: 1,
  );
}

void main() {
  Future<void> pump(WidgetTester tester, Locale locale) async {
    final container = buildTestContainer(
      permissions: {Permission.campaignCreate},
      overrides: [
        campaignListProvider.overrideWith(_OneDraftCampaignNotifier.new),
      ],
    );

    final router = GoRouter(
      initialLocation: '/campaigns',
      routes: [
        GoRoute(
          path: '/campaigns',
          builder: (_, __) => const CampaignListScreen(),
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

  /// The label the rendered [StatusChip] widgets actually carry. Read off the
  /// widget rather than via `find.text`, so a chip that renders an empty string
  /// is a visible failure instead of an absent finder.
  List<String> chipLabels(WidgetTester tester) => tester
      .widgetList<StatusChip>(find.byType(StatusChip))
      .map((c) => c.label)
      .toList();

  testWidgets('the status column renders Bengali under Locale(bn), and neither '
      'the English label nor the raw enum name', (tester) async {
    await pump(tester, const Locale('bn'));

    // campaignStatus_draft in bn. Task 12's locale_bengali.yaml asserts this
    // exact string on an emulator — changing it here breaks that flow.
    expect(find.text('খসড়া'), findsWidgets);
    expect(chipLabels(tester), contains('খসড়া'));

    expect(find.text('Draft'), findsNothing, reason: 'English must not leak');
    expect(
      find.text('draft'),
      findsNothing,
      reason: 'the raw CampaignStatus.name this task removes',
    );
    expect(chipLabels(tester), isNot(contains('draft')));
  });

  testWidgets('the status column renders the English label under Locale(en), '
      'not the raw enum name', (tester) async {
    await pump(tester, const Locale('en'));

    // The en case is where the raw-identifier assertion has teeth: "draft" and
    // "Draft" differ only in case, so `.name` slipping back in would still look
    // plausible to a reader skimming a screenshot.
    expect(find.text('Draft'), findsWidgets);
    expect(chipLabels(tester), contains('Draft'));
    expect(find.text('draft'), findsNothing);
    expect(find.text('খসড়া'), findsNothing);
  });

  testWidgets('the row-detail side sheet is localized too, even though its '
      'builder runs under a different Navigator', (tester) async {
    // rowDetailBuilder is invoked by showBmdSideSheet from a route above the
    // screen's own context. Resolving AppL10n inside that closure from the
    // sheet's context would be a different Localizations scope; the screen
    // captures the bundle in build() instead, and this is what pins that.
    await pump(tester, const Locale('bn'));

    await tester.tap(find.byTooltip('Show all columns').first);
    await tester.pumpAndSettle();

    // Two chips now: the table cell behind the sheet and the sheet's own.
    expect(find.text('খসড়া'), findsNWidgets(2));
    expect(find.text('draft'), findsNothing);
    expect(find.text('Draft'), findsNothing);
  });
}
