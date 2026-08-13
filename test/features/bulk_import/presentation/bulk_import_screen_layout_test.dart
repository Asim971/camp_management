import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:acsl_campaign/domain/import/import_job.dart';
import 'package:acsl_campaign/features/bulk_import/application/import_controller.dart';
import 'package:acsl_campaign/features/bulk_import/presentation/bulk_import_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/harness.dart';

/// `_UploadPanel`'s original `Row(children: [Expanded(description), Download
/// template, Choose file])` pushed its two non-flexible `BmdButton`s past the
/// width of a narrow CI-emulator viewport (~320-360dp), clamping the
/// `Expanded` description to near-zero width. That renders the description
/// one letter per line, overflows the Row horizontally, and clips/pushes the
/// "Choose file" button (`import_pick`, the id the bulk-import e2e flow drives)
/// off-screen — which is why that flow failed with "import_pick element not
/// found" on the emulator. Same overflow class as the campaign-detail header
/// (64d91d9), just one screen over.
///
/// Pumps the FULL [BulkImportScreen] (not just `_UploadPanel` in isolation) at
/// a 320px logical width — the same `tester.view.physicalSize`/
/// `devicePixelRatio` idiom `campaign_detail_header_layout_test.dart` and
/// `registration_workspace_screen_test.dart` use — in both states the e2e
/// flow actually traverses: the initial upload state, and the ready-to-commit
/// review state the flow reaches after the dry-run poll completes.
Finder _byIdentifier(String id) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.identifier == id,
);

Widget _wrapInRouter(String campaignId) {
  final router = GoRouter(
    initialLocation: '/campaigns/$campaignId/import',
    routes: [
      GoRoute(
        path: '/campaigns/:id/import',
        builder: (_, state) =>
            BulkImportScreen(campaignId: state.pathParameters['id']!),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

/// Seeds a ready-to-commit job with a mix of outcomes straight into [build] —
/// the review surface (outcome chips, "Ready to commit" headline, commit
/// button) renders without driving an actual upload, mirroring
/// `test/widget/bulk_import_screen_test.dart`'s `_JobSeededController`.
class _JobSeededController extends ImportController {
  @override
  ImportState build(String campaignId) => const ImportState(
    job: AsyncData(
      ImportJob(
        id: 'IMPORT-1',
        campaignId: 'CAMP-1',
        status: ImportStatus.readyToCommit,
        rows: [
          ImportRow(
            rowId: 'row-1',
            name: 'Md. Karim',
            outcome: ImportRowOutcome.valid,
          ),
          ImportRow(
            rowId: 'row-2',
            name: 'Abdul Rahman',
            outcome: ImportRowOutcome.needsProfile,
          ),
          ImportRow(
            rowId: 'row-3',
            name: 'Rina Akter',
            outcome: ImportRowOutcome.warning,
            message: 'Phone number looks malformed.',
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('bulk_import_screen (upload state): no RenderFlex overflow and '
      '"import_pick" is findable at a 320px-wide viewport', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = buildTestContainer(permissions: {Permission.bulkImport});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _wrapInRouter('CAMP-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      _byIdentifier('import_pick'),
      findsOneWidget,
      reason:
          'the pick control must stay on-screen and reachable at 320px; '
          'an unclamped Row pushes it past the viewport edge instead',
    );
  });

  testWidgets(
    'bulk_import_screen (ready-to-commit state): no RenderFlex overflow, '
    '"Ready to commit" and "import_commit" are findable at a 320px-wide '
    'viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = buildTestContainer(
        permissions: {Permission.bulkImport},
        overrides: [
          importControllerProvider.overrideWith(_JobSeededController.new),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapInRouter('CAMP-1'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Ready to commit'), findsOneWidget);
      expect(
        _byIdentifier('import_commit'),
        findsOneWidget,
        reason: 'the commit control must stay on-screen and reachable at 320px',
      );
    },
  );
}
