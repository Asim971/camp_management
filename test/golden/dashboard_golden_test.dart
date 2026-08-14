import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/features/dashboard/application/dashboard_notifier.dart';
import 'package:acsl_campaign/features/dashboard/presentation/dashboard_screen.dart';
import 'package:acsl_campaign/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/golden.dart';
import '../support/harness.dart';

/// Dashboard baselines across both themes and both surface widths — Linux
/// only (`goldenTest` skips elsewhere; font rasterisation differs enough
/// between platforms that a non-Linux baseline is not trustworthy — see
/// `test/support/golden.dart`). NOT generated in this task: `--update-goldens`
/// is a no-op on Windows, so these `.png`s must be produced on Linux CI and
/// committed from there.
const _viewports = <String, Size>{
  'desktop': Size(1280, 2600),
  'mobile': Size(390, 2600),
};

/// Sets the test binding's *physical* view directly (mirrors
/// `test/golden/gallery_golden_test.dart`'s `_setViewport`: on this
/// toolchain, `tester.binding.setSurfaceSize` does not drive
/// `MediaQuery.sizeOf`, which several dashboard widgets size themselves
/// from via `Breakpoint.of`).
void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// A full, non-empty [DashboardView] — every exception bucket (including
/// the always-zero ones), four KPIs, a four-stage funnel and an eight-way
/// status breakdown — so the baseline actually exercises every section
/// instead of an empty/placeholder look.
class _SeededDashboardNotifier extends DashboardNotifier {
  @override
  Future<DashboardView> build() async => const DashboardView(
    exceptions: [
      DashboardException(
        key: 'overdue_verification',
        label: 'Overdue verification',
        count: 3,
        tone: StatusTone.error,
      ),
      DashboardException(
        key: 'escalated',
        label: 'Escalated',
        count: 1,
        tone: StatusTone.warning,
      ),
      DashboardException(
        key: 'no_reference',
        label: 'No reference photo',
        count: 2,
        tone: StatusTone.warning,
      ),
      DashboardException(
        key: 'pending_sync',
        label: 'Pending sync',
        count: 4,
        tone: StatusTone.info,
      ),
      DashboardException(
        key: 'rejected',
        label: 'Returned / rejected',
        count: 1,
        tone: StatusTone.warning,
      ),
      DashboardException(
        key: 'suspected_spoof',
        label: 'Suspected spoof',
        count: 0,
        tone: StatusTone.neutral,
      ),
      DashboardException(
        key: 'reconciliation',
        label: 'Reconciliation',
        count: 0,
        tone: StatusTone.neutral,
      ),
    ],
    kpis: [
      DashboardKpi(label: 'Campaigns', value: 12),
      DashboardKpi(label: 'Active campaigns', value: 7),
      DashboardKpi(label: 'Verification queue', value: 9),
      DashboardKpi(label: 'Pending sync', value: 4),
    ],
    funnel: AttendanceFunnel(
      stages: [
        ('Target audience', 500),
        ('Verified attendance', 320),
        ('Pending verification', 9),
        ('Escalated', 1),
      ],
    ),
    statusBreakdown: CampaignStatusBreakdown(
      byStatus: {
        CampaignStatus.draft: 2,
        CampaignStatus.pendingApproval: 1,
        CampaignStatus.returned: 1,
        CampaignStatus.approved: 0,
        CampaignStatus.active: 7,
        CampaignStatus.paused: 0,
        CampaignStatus.completed: 1,
        CampaignStatus.cancelled: 0,
      },
    ),
  );
}

Widget _host(Brightness brightness) {
  final container = buildTestContainer(
    permissions: const {},
    overrides: [dashboardProvider.overrideWith(_SeededDashboardNotifier.new)],
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [GoRoute(path: '/', builder: (_, __) => const DashboardScreen())],
  );
  addTearDown(router.dispose);

  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: bmdTheme(brightness: brightness),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  for (final viewport in _viewports.entries) {
    for (final brightness in Brightness.values) {
      final suffix = '${viewport.key}-${brightness.name}';

      goldenTest('dashboard · $suffix', (tester) async {
        _setViewport(tester, viewport.value);

        await tester.pumpWidget(_host(brightness));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/dashboard-$suffix.png'),
        );
      });
    }
  }
}
