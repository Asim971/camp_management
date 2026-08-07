import 'package:acsl_campaign/core/design_system/bmd_button.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts Guideline §5.1: one filled primary action per screen or step.
///
/// A test-time check rather than a runtime one. A subtree-counting widget would
/// false-positive the moment a dialog with its own primary sits over a page
/// with one, and it would ship debug machinery into the app bundle. Scoped to
/// the pumped widget under test, this has neither problem.
void expectSinglePrimaryAction(WidgetTester tester) {
  final primaries = tester
      .widgetList<BmdButton>(find.byType(BmdButton))
      .where((b) => b.variant == BmdButtonVariant.primary)
      .toList();

  expect(
    primaries.length,
    lessThanOrEqualTo(1),
    reason:
        'Guideline §5.1 allows one filled primary action per screen or step. '
        'Found ${primaries.length}: '
        '${primaries.map((b) => b.label).join(", ")}. '
        'Demote all but the most important to tonal or outlined.',
  );
}
