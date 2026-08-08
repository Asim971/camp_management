import 'dart:io';

import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/app/theme/tokens.dart';
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

  group('responsive control height (Guideline §5.1, §11)', () {
    // Regression coverage: deleting the Breakpoint.of(context).isMobile ? … :
    // … ternary at bmd_button.dart:41 would leave the rest of the suite
    // green. tester.binding.setSurfaceSize() does not drive MediaQuery.sizeOf
    // on this Flutter version (3.44.8), so tester.view is driven directly.
    // Verified by mutation: deleting the ternary (replacing it with a single
    // constant) fails exactly this test; restoring it turns the suite green
    // again.
    testWidgets('BmdButton is 52px tall on mobile and 44px on web/tablet+', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, BmdButton(label: 'Continue', onPressed: () {}));
      expect(
        tester.getSize(find.byType(BmdButton)).height,
        BmdSize.controlHeightMobile,
      );

      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, BmdButton(label: 'Continue', onPressed: () {}));
      expect(
        tester.getSize(find.byType(BmdButton)).height,
        BmdSize.controlHeightWeb,
      );
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

  group('the Maestro `id:` node carries the enabled state', () {
    // `Semantics(identifier:)` compiles to its OWN semantics node, separate
    // from the Material button's. Probed on Flutter 3.44.8, a plain
    // `Semantics(identifier: 'x', child: FilledButton(onPressed: null))` yields
    //
    //   node A  identifier "x"  label ""                isEnabled none
    //     node B identifier ""  label "Submit decision" isEnabled false
    //
    // Flutter's Android AccessibilityBridge reports a node with no enabled
    // state as `enabled=true`, so node A — the one Maestro finds by `id:` —
    // claimed to be enabled even when the button was disabled. That made
    // `assertVisible: {id: ..., enabled: false}` fail and its `enabled: true`
    // counterpart pass vacuously, in the two E2E flows whose entire subject is
    // a gated action: `confirm_continue` (the mandatory second identity cue,
    // .maestro/flows/carpenter_search_confirm.yaml) and `crm_submit` (the
    // mandatory decision reason, .maestro/flows/crm_case_decision.yaml).
    //
    // Non-vacuous by construction: deleting `enabled: _interactive` from
    // BmdButton.build turns the disabled expectation below from `isEnabled
    // false` into `isEnabled none`, which `matchesSemantics(hasEnabledState:
    // true)` rejects.
    testWidgets('reflects onPressed and loading, not just the child button', (
      tester,
    ) async {
      // Disposed at the end of the body, not via addTearDown: the framework's
      // "a SemanticsHandle was active at the end of the test" check runs BEFORE
      // tear-downs, so a tear-down disposal fails the test it is protecting.
      final handle = tester.ensureSemantics();

      await _pump(
        tester,
        const BmdButton(
          label: 'Submit decision',
          identifier: 'crm_submit',
          onPressed: null,
        ),
      );
      expect(
        tester.getSemantics(find.byType(BmdButton)),
        matchesSemantics(
          identifier: 'crm_submit',
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      await _pump(
        tester,
        BmdButton(
          label: 'Submit decision',
          identifier: 'crm_submit',
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(BmdButton)),
        matchesSemantics(
          identifier: 'crm_submit',
          hasEnabledState: true,
          isEnabled: true,
        ),
      );

      // `loading` suppresses onPressed, so the identifier node must say so too
      // — otherwise a flow could tap a spinner and wait forever.
      await _pump(
        tester,
        BmdButton(
          label: 'Submit decision',
          identifier: 'crm_submit',
          loading: true,
          onPressed: () {},
        ),
      );
      expect(
        tester.getSemantics(find.byType(BmdButton)),
        matchesSemantics(
          identifier: 'crm_submit',
          hasEnabledState: true,
          isEnabled: false,
        ),
      );

      handle.dispose();
    });
  });

  group('single renderer', () {
    test('no feature screen builds a raw filled/outlined button', () {
      // expectSinglePrimaryAction only counts BmdButton instances, so a screen
      // could carry any number of raw FilledButton/ElevatedButton/
      // OutlinedButton widgets and still pass it -- they bypass the design
      // system entirely, and a widget-tree count can't fix that here: BmdButton
      // *renders* a FilledButton internally, so counting FilledButtons in the
      // tree would double-count every legitimate BmdButton too. A filesystem
      // guard, consistent with the overlay and field guards above, is the
      // right tool.
      //
      // TextButton and IconButton are deliberately not in this blocklist:
      // BmdButton's `text` variant renders a TextButton, and several
      // design-system internals legitimately use IconButton, so either name
      // would flag legitimate design-system output as well as raw screen code.
      final offenders = <String>[];
      final dir = Directory('lib/features');
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.contains('FilledButton(') ||
              line.contains('ElevatedButton(') ||
              line.contains('OutlinedButton(')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'Use BmdButton (primary/tonal/outlined/danger variant) instead:\n'
            '${offenders.join("\n")}',
      );
    });
  });
}
