import 'dart:typed_data';

import 'package:acsl_campaign/features/bulk_import/application/import_controller.dart';
import 'package:acsl_campaign/features/bulk_import/presentation/bulk_import_screen.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/single_primary.dart';

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
      final container = ProviderContainer(
        overrides: [
          importControllerProvider.overrideWith(_FakeImportController.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: BulkImportScreen(campaignId: campaignId),
          ),
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

      // TODO: This assertion fails because bulk_import_screen shows both
      // "Choose file" (line 95) and "Commit valid rows" (line 204) buttons
      // as primary. Which should be demoted to tonal or outlined is a design
      // decision that needs to be made.
      expectSinglePrimaryAction(tester);
    },
  );

  testWidgets(
    'bulk_import_screen: cancelling the picker (null XFile) never calls '
    'uploadDryRun',
    (tester) async {
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(null);

      const campaignId = 'CAMP-2';
      final container = ProviderContainer(
        overrides: [
          importControllerProvider.overrideWith(_FakeImportController.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: BulkImportScreen(campaignId: campaignId),
          ),
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
