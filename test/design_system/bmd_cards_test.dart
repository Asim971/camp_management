import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/app/theme/tokens.dart';
import 'package:acsl_campaign/core/design_system/bmd_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

BoxDecoration? _decorationOf(WidgetTester tester, Finder finder) {
  final container = tester.widget<Container>(finder);
  return container.decoration as BoxDecoration?;
}

void main() {
  group('KpiCard glass=false (default) stays the current look', () {
    testWidgets('renders inside a Card and carries no glass container', (
      tester,
    ) async {
      await _pump(
        tester,
        const KpiCard(
          label: 'Verified attendance',
          value: '1,107',
          definition: 'Distinct carpenters with a CRM-approved record.',
          source: 'verification facts',
          freshness: 'refreshed 09:42',
          delta: '+2.1pp',
          deltaDirection: KpiDelta.up,
          deltaContext: 'vs last week',
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      // The default look draws no standalone decorated Container for the
      // card body — only the Card's own themed shape.
      expect(find.byType(Container), findsNothing);

      // Sub-content survives untouched: definition tooltip, delta arrow,
      // source/freshness footer.
      expect(
        find.byTooltip('Distinct carpenters with a CRM-approved record.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('verification facts · refreshed 09:42'), findsOneWidget);
    });
  });

  group('KpiCard glass=true', () {
    testWidgets('renders a glass container instead of a Card', (tester) async {
      await _pump(
        tester,
        const KpiCard(
          label: 'Verified attendance',
          value: '1,107',
          definition: 'Distinct carpenters with a CRM-approved record.',
          source: 'verification facts',
          freshness: 'refreshed 09:42',
          delta: '+2.1pp',
          deltaDirection: KpiDelta.up,
          deltaContext: 'vs last week',
          glass: true,
        ),
      );

      expect(find.byType(Card), findsNothing);
      final containerFinder = find.byType(Container);
      expect(containerFinder, findsOneWidget);

      final bmd = bmdTheme().bmd;
      final decoration = _decorationOf(tester, containerFinder);
      expect(decoration?.color, bmd.glassFill);
      expect((decoration?.border as Border?)?.top.color, bmd.glassBorder);
      expect(decoration?.boxShadow, BmdElevation.level2);

      // Sub-content is preserved under glass too.
      expect(
        find.byTooltip('Distinct carpenters with a CRM-approved record.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(find.text('verification facts · refreshed 09:42'), findsOneWidget);
    });
  });

  group('ExceptionCard glass=false (default) stays the current look', () {
    testWidgets('renders inside a Card with only the tone accent border', (
      tester,
    ) async {
      await _pump(
        tester,
        ExceptionCard(
          label: 'Captures awaiting sync',
          count: '34',
          tone: ExceptionTone.warning,
          detail: '34 devices, oldest queued in Chattogram.',
          oldest: '2h 14m',
          agePressure: 0.62,
          actionLabel: 'Open queue',
          onAction: () {},
        ),
      );

      expect(find.byType(Card), findsOneWidget);
      final decoration = _decorationOf(tester, find.byType(Container));
      expect(decoration?.color, isNull);
      expect(decoration?.boxShadow, isNull);
      expect((decoration?.border as Border?)?.top, BorderSide.none);

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('2h 14m'), findsOneWidget);
      expect(find.text('Open queue →'), findsOneWidget);
    });
  });

  group('ExceptionCard glass=true', () {
    testWidgets('renders a glass container keeping the tone accent + age bar', (
      tester,
    ) async {
      await _pump(
        tester,
        ExceptionCard(
          label: 'Captures awaiting sync',
          count: '34',
          tone: ExceptionTone.warning,
          detail: '34 devices, oldest queued in Chattogram.',
          oldest: '2h 14m',
          agePressure: 0.62,
          actionLabel: 'Open queue',
          onAction: () {},
          glass: true,
        ),
      );

      expect(find.byType(Card), findsNothing);
      // Stacked instead: the glass surface plus a separate leading accent
      // bar (a Border can't mix a radius with non-uniform side colors).
      expect(find.byType(Stack), findsWidgets);

      final bmd = bmdTheme().bmd;
      final decoration = _decorationOf(
        tester,
        find.byWidgetPredicate(
          (w) =>
              w is Container && (w.decoration as BoxDecoration?)?.color != null,
        ),
      );
      expect(decoration?.color, bmd.glassFill);
      expect(decoration?.boxShadow, BmdElevation.level2);
      final border = decoration?.border as Border?;
      expect(border?.isUniform, isTrue);
      expect(border?.top.color, bmd.glassBorder);

      // The tone accent stays on the leading edge as a separate overlay.
      expect(
        find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == bmd.warning,
        ),
        findsOneWidget,
      );

      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('2h 14m'), findsOneWidget);
      expect(find.text('Open queue →'), findsOneWidget);
    });
  });
}
