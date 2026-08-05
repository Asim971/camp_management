import 'dart:io';

import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a host with a button that opens the overlay under test, and returns a
/// getter for whatever the overlay eventually resolves to.
Future<Future<void> Function()> _host(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open, {
  Size size = const Size(1280, 900),
}) async {
  // `binding.setSurfaceSize` only resizes the RenderView's layout
  // constraints on this Flutter version -- MediaQuery.sizeOf (and therefore
  // Breakpoint.of) keeps reporting the default test view size unless the
  // view itself is resized, so the breakpoint-dependent side-sheet/bottom
  // -sheet test would silently exercise the wrong branch. Setting
  // `tester.view` directly is what the binding's own doc comment recommends.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => open(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  return () async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  };
}

void main() {
  group('showBmdConfirm', () {
    testWidgets('confirm stays disabled until a required reason is given', (
      tester,
    ) async {
      // T-1.4.2 and T-3.1.4 both require this; owning it here means neither
      // screen can forget it.
      final open = await _host(
        tester,
        (context) => showBmdConfirm(
          context: context,
          title: 'Return this campaign?',
          body: 'The creator will be asked to correct it.',
          confirmLabel: 'Return for correction',
          reasonLabel: 'Reason',
        ),
      );
      await open();

      final confirm = find.widgetWithText(
        FilledButton,
        'Return for correction',
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(find.byType(TextFormField), 'Venue is missing');
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('a whitespace-only reason does not satisfy the gate', (
      tester,
    ) async {
      // A reason of only spaces is not substantive -- it must not be
      // mistaken for one that was actually given (T-1.4.2, T-3.1.4).
      final open = await _host(
        tester,
        (context) => showBmdConfirm(
          context: context,
          title: 'Return this campaign?',
          body: 'The creator will be asked to correct it.',
          confirmLabel: 'Return for correction',
          reasonLabel: 'Reason',
        ),
      );
      await open();

      final confirm = find.widgetWithText(
        FilledButton,
        'Return for correction',
      );

      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: 'whitespace alone is not a substantive reason',
      );
    });

    testWidgets('confirm stays disabled until every box is acknowledged', (
      tester,
    ) async {
      final open = await _host(
        tester,
        (context) => showBmdConfirm(
          context: context,
          title: 'Approve this campaign?',
          body: 'Approval activates registration.',
          confirmLabel: 'Approve',
          acknowledgements: const [
            'I reviewed the session schedule',
            'I acknowledge the SoD warning',
          ],
        ),
      );
      await open();

      final confirm = find.widgetWithText(FilledButton, 'Approve');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.tap(find.text('I reviewed the session schedule'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(confirm).onPressed,
        isNull,
        reason: 'one of two acknowledgements is not enough',
      );

      await tester.tap(find.text('I acknowledge the SoD warning'));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    });

    testWidgets('the downstream effect is stated before committing', (
      tester,
    ) async {
      final open = await _host(
        tester,
        (context) => showBmdConfirm(
          context: context,
          title: 'Cancel this campaign?',
          body: 'This cannot be undone.',
          confirmLabel: 'Cancel campaign',
          danger: true,
          effect: 'This will remove 34 registrations and 12 captures.',
        ),
      );
      await open();

      expect(
        find.text('This will remove 34 registrations and 12 captures.'),
        findsOneWidget,
      );
    });

    testWidgets('the reason comes back with the result', (tester) async {
      BmdConfirmResult? result;
      final open = await _host(tester, (context) async {
        result = await showBmdConfirm(
          context: context,
          title: 'Reject this capture?',
          body: 'The field user will be asked to recapture.',
          confirmLabel: 'Reject',
          reasonLabel: 'Reason',
        );
      });
      await open();

      await tester.enterText(find.byType(TextFormField), 'Face not visible');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(result?.reason, 'Face not visible');
    });

    testWidgets('the returned reason is trimmed of surrounding whitespace', (
      tester,
    ) async {
      // A reason recorded against a decision must be the substance, not
      // whatever incidental padding the input carried (T-1.4.2, T-3.1.4).
      BmdConfirmResult? result;
      final open = await _host(tester, (context) async {
        result = await showBmdConfirm(
          context: context,
          title: 'Reject this capture?',
          body: 'The field user will be asked to recapture.',
          confirmLabel: 'Reject',
          reasonLabel: 'Reason',
        );
      });
      await open();

      await tester.enterText(
        find.byType(TextFormField),
        '  Face not visible  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reject'));
      await tester.pumpAndSettle();

      expect(result?.reason, 'Face not visible');
    });

    testWidgets('cancelling resolves to null', (tester) async {
      var called = false;
      BmdConfirmResult? result;
      final open = await _host(tester, (context) async {
        result = await showBmdConfirm(
          context: context,
          title: 'Discard?',
          body: 'The draft will be lost.',
          confirmLabel: 'Discard',
        );
        called = true;
      });
      await open();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNull);
    });
  });

  group('showBmdSideSheet', () {
    testWidgets('returns the value the body pops', (tester) async {
      String? picked;
      final open = await _host(tester, (context) async {
        picked = await showBmdSideSheet<String>(
          context: context,
          title: 'Filters',
          builder: (sheetContext) => TextButton(
            onPressed: () => Navigator.pop(sheetContext, 'sla-breach'),
            child: const Text('SLA breach'),
          ),
        );
      });
      await open();

      expect(find.byKey(bmdSideSheetKey), findsOneWidget);
      await tester.tap(find.text('SLA breach'));
      await tester.pumpAndSettle();

      expect(picked, 'sla-breach');
    });

    testWidgets('below tablet it becomes a bottom sheet', (tester) async {
      // §5.6 assigns side sheets to web and bottom sheets to mobile, so one
      // call site is correct on both surfaces.
      final open = await _host(
        tester,
        (context) => showBmdSideSheet<void>(
          context: context,
          title: 'Filters',
          builder: (_) => const Text('body'),
        ),
        size: const Size(390, 844),
      );
      await open();

      expect(find.byKey(bmdSideSheetKey), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Filters'), findsOneWidget);
    });
  });

  group('showBmdBottomSheet', () {
    testWidgets('shows its title and returns its value', (tester) async {
      bool? confirmed;
      final open = await _host(tester, (context) async {
        confirmed = await showBmdBottomSheet<bool>(
          context: context,
          title: 'Confirm carpenter',
          builder: (sheetContext) => TextButton(
            onPressed: () => Navigator.pop(sheetContext, true),
            child: const Text('Continue'),
          ),
        );
      }, size: const Size(390, 844));
      await open();

      expect(find.text('Confirm carpenter'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });
  });

  group('single renderer', () {
    test('no feature screen hand-rolls a dialog or modal sheet', () {
      final offenders = <String>[];
      for (final entity in Directory(
        'lib/features',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('AlertDialog(') ||
              line.contains('showModalBottomSheet(') ||
              line.contains('showDialog<')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use showBmdConfirm / showBmdSideSheet / showBmdBottomSheet:\n'
            '${offenders.join("\n")}',
      );
    });
  });
}
