import 'dart:typed_data';

import 'package:acsl_campaign/core/auth/rbac.dart';
import 'package:acsl_campaign/features/bulk_import/application/import_controller.dart';
import 'package:acsl_campaign/features/bulk_import/presentation/bulk_import_screen.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/harness.dart';
import '../support/single_primary.dart';

/// AppShell derives the selected nav index from GoRouterState.of(context),
/// which requires the widget under test to be built by an actual GoRouter
/// route rather than a bare MaterialApp(home: ...).
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

/// Fakes the platform file dialog so the widget test never touches a real
/// OS picker — it hands back a canned in-memory [XFile], the same seam
/// `file_selector` itself uses for testing (`FileSelectorPlatform.instance`).
class _FakeFileSelectorPlatform extends FileSelectorPlatform {
  _FakeFileSelectorPlatform(this.fileToReturn);
  final XFile? fileToReturn;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => fileToReturn;
}

/// Records what `uploadDryRun` was called with instead of hitting the
/// network — the point of this test is the wiring from "file picked" to
/// "controller invoked with its bytes/name", not the mock backend.
class _FakeImportController extends ImportController {
  List<int>? receivedBytes;
  String? receivedFilename;

  @override
  Future<void> uploadDryRun(List<int> bytes, String filename) async {
    receivedBytes = bytes;
    receivedFilename = filename;
  }
}

void main() {
  testWidgets(
    'bulk_import_screen: choosing a file wires its bytes and name into '
    'uploadDryRun (T-1.6.1 file_picker -> file_selector migration coverage)',
    (tester) async {
      final bytes = Uint8List.fromList('name,phone\nKarim,017\n'.codeUnits);
      final pickedFile = XFile.fromData(
        bytes,
        mimeType: 'text/csv',
        path: 'participants.csv',
      );
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(pickedFile);

      const campaignId = 'CAMP-1';
      // Signed in holding the permission bulk import itself requires: AppShell
      // (which BulkImportScreen renders through) reads authStateProvider for
      // its destinations and account menu.
      final container = buildTestContainer(
        permissions: {Permission.bulkImport},
        overrides: [
          importControllerProvider.overrideWith(_FakeImportController.new),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapInRouter(campaignId),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Choose file'));
      await tester.pumpAndSettle();

      final controller =
          container.read(importControllerProvider(campaignId).notifier)
              as _FakeImportController;

      expect(controller.receivedFilename, 'participants.csv');
      expect(controller.receivedBytes, isNotNull);
      expect(
        String.fromCharCodes(controller.receivedBytes!),
        'name,phone\nKarim,017\n',
      );

      // This assertion passes, but cannot detect a real §5.1 violation:
      // bulk_import_screen.dart renders _UploadPanel unconditionally (line 30),
      // then _Results separately below it (line 58) when committable rows exist.
      // In production, both "Choose file" (line 95, default primary) and
      // "Commit N valid row(s)" (line 204, default primary) are on screen
      // simultaneously. The test cannot reach this state because
      // _FakeImportController.uploadDryRun never populates job state, so
      // _Results never renders. Which button should be demoted to tonal or
      // outlined is an open design decision.
      expectSinglePrimaryAction(tester);
    },
  );

  testWidgets(
    'bulk_import_screen: cancelling the picker (null XFile) never calls '
    'uploadDryRun',
    (tester) async {
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(null);

      const campaignId = 'CAMP-2';
      final container = buildTestContainer(
        permissions: {Permission.bulkImport},
        overrides: [
          importControllerProvider.overrideWith(_FakeImportController.new),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _wrapInRouter(campaignId),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Choose file'));
      await tester.pumpAndSettle();

      final controller =
          container.read(importControllerProvider(campaignId).notifier)
              as _FakeImportController;

      expect(controller.receivedBytes, isNull);
      expect(controller.receivedFilename, isNull);

      expectSinglePrimaryAction(tester);
    },
  );
}
