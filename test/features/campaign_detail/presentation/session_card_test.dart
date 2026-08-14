import 'package:acsl_campaign/domain/campaign/campaign.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/session/campaign_session.dart';
import 'package:acsl_campaign/features/campaign_detail/application/campaign_detail_controller.dart';
import 'package:acsl_campaign/features/campaign_detail/presentation/campaign_detail_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// Finds the [Semantics] node carrying a given stable test id — the same
/// `Semantics(identifier: …)` convention Maestro flows key off (mirrors
/// `test/widget/bulk_import_screen_test.dart`'s `_byIdentifier`).
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

// draft, deliberately: its label ("Draft") is the one CampaignStatus text
// that never collides with a SessionStatus label under test below (three of
// the five — Active/Paused/Completed — share their English word with a
// CampaignStatus, and the header renders its own status chip alongside the
// session card's).
const _campaign = Campaign(
  id: 'c-1',
  name: 'Boro season seminar',
  type: 'seminar',
  organizationId: 'ORG_1',
  status: CampaignStatus.draft,
  ownerId: 'u-1',
);

/// Seeds exactly one session straight into [build] — the point of these tests
/// is the Sessions-tab card's per-status control gating, not the
/// campaign/session load wiring already covered elsewhere.
class _SeededController extends CampaignDetailController {
  _SeededController(this.session);
  final CampaignSession session;

  @override
  Future<CampaignDetailData> build(String campaignId) async =>
      CampaignDetailData(campaign: _campaign, sessions: [session]);
}

Future<void> _pumpSessionsTab(
  WidgetTester tester,
  CampaignSession session,
) async {
  final container = buildTestContainer(
    permissions: const {},
    overrides: [
      campaignDetailProvider.overrideWith(() => _SeededController(session)),
    ],
  );

  final router = GoRouter(
    initialLocation: '/campaigns/c-1',
    routes: [
      GoRoute(
        path: '/campaigns/:id',
        builder: (_, state) =>
            CampaignDetailScreen(campaignId: state.pathParameters['id']!),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The Sessions tab is index 1 and TabBarView builds pages lazily, so the
  // card does not exist until the tab is selected.
  await tester.tap(find.text('Sessions'));
  await tester.pumpAndSettle();
}

CampaignSession _session({
  required SessionStatus status,
  bool readinessOk = true,
}) => CampaignSession(
  id: 's-1',
  campaignId: 'c-1',
  venue: 'Rangpur union hall',
  status: status,
  readinessOk: readinessOk,
);

void main() {
  testWidgets('upcoming + readinessOk: session_start is present and enabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();

    await _pumpSessionsTab(
      tester,
      _session(status: SessionStatus.upcoming, readinessOk: true),
    );

    final start = _byIdentifier('session_start');
    expect(start, findsOneWidget);
    expect(
      tester.getSemantics(start),
      matchesSemantics(
        identifier: 'session_start',
        hasEnabledState: true,
        isEnabled: true,
      ),
    );
    expect(_byIdentifier('session_pause'), findsNothing);
    expect(_byIdentifier('session_close'), findsNothing);

    handle.dispose();
  });

  testWidgets(
    'upcoming + !readinessOk: session_start is present but disabled',
    (tester) async {
      final handle = tester.ensureSemantics();

      await _pumpSessionsTab(
        tester,
        _session(status: SessionStatus.upcoming, readinessOk: false),
      );

      final start = _byIdentifier('session_start');
      expect(start, findsOneWidget);
      expect(
        tester.getSemantics(start),
        matchesSemantics(
          identifier: 'session_start',
          hasEnabledState: true,
          isEnabled: false,
        ),
        reason:
            'a session that is not ready must not be startable, and the '
            'identifier node itself must say so non-vacuously (bare '
            'Semantics(identifier:) with no enabled state reads as '
            'enabled=true on Android — see bmd_button.dart)',
      );

      handle.dispose();
    },
  );

  testWidgets(
    'active: session_pause and session_close are present; no session_start',
    (tester) async {
      await _pumpSessionsTab(tester, _session(status: SessionStatus.active));

      expect(_byIdentifier('session_pause'), findsOneWidget);
      expect(_byIdentifier('session_close'), findsOneWidget);
      expect(_byIdentifier('session_start'), findsNothing);
    },
  );

  testWidgets(
    'paused: session_start (resume) and session_close are present; no '
    'session_pause',
    (tester) async {
      await _pumpSessionsTab(tester, _session(status: SessionStatus.paused));

      expect(_byIdentifier('session_start'), findsOneWidget);
      expect(_byIdentifier('session_close'), findsOneWidget);
      expect(_byIdentifier('session_pause'), findsNothing);
    },
  );

  testWidgets(
    'captureClosed: none of the three operation controls are present',
    (tester) async {
      await _pumpSessionsTab(
        tester,
        _session(status: SessionStatus.captureClosed),
      );

      expect(_byIdentifier('session_start'), findsNothing);
      expect(_byIdentifier('session_pause'), findsNothing);
      expect(_byIdentifier('session_close'), findsNothing);
    },
  );

  testWidgets('completed: none of the three operation controls are present', (
    tester,
  ) async {
    await _pumpSessionsTab(tester, _session(status: SessionStatus.completed));

    expect(_byIdentifier('session_start'), findsNothing);
    expect(_byIdentifier('session_pause'), findsNothing);
    expect(_byIdentifier('session_close'), findsNothing);
  });

  const chipLabels = {
    SessionStatus.upcoming: 'Upcoming',
    SessionStatus.active: 'Active',
    SessionStatus.paused: 'Paused',
    SessionStatus.captureClosed: 'Capture closed',
    SessionStatus.completed: 'Completed',
  };

  // One testWidgets per status — not a for-loop pumping repeatedly inside a
  // single test, which leaves the previous GoRouter/session tree's timers
  // pending when the next pumpWidget replaces it.
  for (final entry in chipLabels.entries) {
    testWidgets('${entry.key} renders the stable chip label "${entry.value}"', (
      tester,
    ) async {
      await _pumpSessionsTab(tester, _session(status: entry.key));
      expect(
        find.text(entry.value),
        findsOneWidget,
        reason: '${entry.key} must render the chip label "${entry.value}"',
      );
    });
  }
}
