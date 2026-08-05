import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/single_primary.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('BmdIconButton', () {
    testWidgets('an icon button always carries a tooltip', (tester) async {
      // §5.1: an unlabelled control needs a tooltip on web, or nobody can tell
      // what it does.
      await _pump(
        tester,
        BmdIconButton(
          icon: Icons.filter_list,
          tooltip: 'Filter campaigns',
          onPressed: () {},
        ),
      );

      expect(find.byTooltip('Filter campaigns'), findsOneWidget);
    });

    testWidgets('the target clears the minimum touch size', (tester) async {
      await _pump(
        tester,
        BmdIconButton(icon: Icons.close, tooltip: 'Close', onPressed: () {}),
      );

      final size = tester.getSize(find.byType(BmdIconButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  group('expectSinglePrimaryAction', () {
    testWidgets('passes with one primary', (tester) async {
      await _pump(
        tester,
        Column(
          children: [
            BmdButton(label: 'Submit', onPressed: () {}),
            BmdButton(
              label: 'Cancel',
              variant: BmdButtonVariant.outlined,
              onPressed: () {},
            ),
          ],
        ),
      );

      expectSinglePrimaryAction(tester);
    });

    testWidgets('fails with two, and names them', (tester) async {
      await _pump(
        tester,
        Column(
          children: [
            BmdButton(label: 'Submit', onPressed: () {}),
            BmdButton(label: 'Approve', onPressed: () {}),
          ],
        ),
      );

      expect(
        () => expectSinglePrimaryAction(tester),
        throwsA(
          isA<TestFailure>().having(
            (f) => f.message,
            'message',
            allOf(contains('Submit'), contains('Approve')),
          ),
        ),
      );
    });
  });
}
