import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/motion/count_up.dart';
import 'package:acsl_campaign/core/motion/reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] in the app theme and a [MediaQuery] with [disableAnimations]
/// set, so a primitive can be pumped exactly as it will be reached in the
/// app (via `MediaQuery.of(context)` / `Theme.of(context)`).
Widget _wrap({required bool disableAnimations, required Widget child}) {
  return MaterialApp(
    theme: bmdTheme(),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  // CountUp shows the final value immediately under reduced motion.
  testWidgets('CountUp renders the target value instantly when motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(disableAnimations: true, child: const CountUp(42)),
    );
    await tester.pump(); // no time advance
    expect(find.text('42'), findsOneWidget);
  });

  // Reveal shows its child at full opacity immediately under reduced motion.
  testWidgets('Reveal shows child instantly when motion is off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        disableAnimations: true,
        child: const Reveal(index: 3, child: Text('hi')),
      ),
    );
    await tester.pump();
    final op = tester.widget<Opacity>(
      find.ancestor(of: find.text('hi'), matching: find.byType(Opacity)).first,
    );
    expect(op.opacity, 1.0);
  });

  // With motion on, CountUp starts below the target and reaches it.
  testWidgets('CountUp animates to the target when motion is on', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(disableAnimations: false, child: const CountUp(42)),
    );
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.text('42'), findsNothing); // mid-flight
    await tester.pumpAndSettle();
    expect(find.text('42'), findsOneWidget);
  });
}
