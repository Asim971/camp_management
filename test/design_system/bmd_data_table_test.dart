import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_data_table.dart';
import 'package:acsl_campaign/core/design_system/status_chip.dart';
import 'package:acsl_campaign/domain/common/status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Row = ({String id, String name, String status, String age});

const _rows = <_Row>[
  (id: 'C-1', name: 'Dhaka roadshow', status: 'Active', age: '3d'),
  (id: 'C-2', name: 'Sylhet seminar', status: 'Draft', age: '11d'),
];

List<BmdColumn<_Row>> _columns() => [
  BmdColumn(
    id: 'id',
    label: 'Code',
    priority: BmdColumnPriority.identity,
    minWidth: 120,
    cell: (r) => Text(r.id),
  ),
  BmdColumn(
    id: 'name',
    label: 'Campaign',
    priority: BmdColumnPriority.primary,
    minWidth: 200,
    flex: 3,
    cell: (r) => Text(r.name),
  ),
  BmdColumn(
    id: 'status',
    label: 'Status',
    minWidth: 140,
    cell: (r) => Text(r.status),
  ),
  BmdColumn(
    id: 'age',
    label: 'Age',
    minWidth: 100,
    numeric: true,
    cell: (r) => Text(r.age),
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  Widget Function(_Row row)? rowDetailBuilder,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: bmdTheme(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            height: 400,
            child: BmdDataTable<_Row>(
              columns: _columns(),
              rows: _rows,
              rowId: (r) => r.id,
              rowDetailBuilder: rowDetailBuilder,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('column priority', () {
    testWidgets('a wide table shows every column', (tester) async {
      await _pump(tester, width: 1200);

      for (final label in ['Code', 'Campaign', 'Status', 'Age']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('a narrow table drops secondary columns, never identity', (
      tester,
    ) async {
      // 400px fits identity (120) + primary (200) and nothing more.
      await _pump(
        tester,
        width: 400,
        rowDetailBuilder: (r) => Text('detail ${r.id}'),
      );

      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Campaign'), findsOneWidget);
      expect(find.text('Status'), findsNothing);
      expect(find.text('Age'), findsNothing);
    });

    testWidgets('dropped columns stay reachable through the row detail', (
      tester,
    ) async {
      await _pump(
        tester,
        width: 400,
        rowDetailBuilder: (r) => Text('detail ${r.id}'),
      );

      await tester.tap(find.byTooltip('Show all columns').first);
      await tester.pumpAndSettle();

      expect(find.text('detail C-1'), findsOneWidget);
    });

    testWidgets('dropping columns with no detail builder is a loud error', (
      tester,
    ) async {
      // Silent truncation reads as "you are seeing everything" when you are
      // not, so this fails in dev rather than losing data in production.
      await _pump(tester, width: 400);

      expect(tester.takeException(), isAssertionError);
    });

    testWidgets('the page body never scrolls horizontally', (tester) async {
      await _pump(
        tester,
        width: 400,
        rowDetailBuilder: (r) => Text('detail ${r.id}'),
      );

      final scrollables = tester.widgetList<Scrollable>(
        find.byType(Scrollable),
      );
      expect(
        scrollables.every((s) => s.axisDirection == AxisDirection.down),
        isTrue,
        reason: 'a horizontally scrolling table is what priority-flex removes',
      );
    });
  });

  group('narrow viewport safety', () {
    // Identity is never dropped, but primary columns now are (last-declared
    // first) once the viewport cannot fit their combined minimums alongside
    // identity — Guideline §5.4 forbids shrinking a column below its
    // minWidth to force a fit, so "drop it" replaces round 1's "squeeze it".
    // mobileS/mobileL (breakpoints.dart, 320-599px) are supported widths, so
    // the table must degrade to identity-only-or-more rather than a
    // RenderFlex overflow when it cannot honour every rendered column's
    // minWidth.
    testWidgets(
      'identity survives and primary drops at a 320px (mobileL floor) '
      'viewport, without throwing',
      (tester) async {
        // identity (120) + primary (200) + detail button (44) = 364px of
        // required content width against a 320px viewport: primary cannot
        // fit, so it drops into the row detail; identity alone (120) fits
        // comfortably in the 276px left after the detail button.
        await _pump(
          tester,
          width: 320,
          rowDetailBuilder: (r) => Text('detail ${r.id}'),
        );

        expect(find.text('Code'), findsOneWidget);
        expect(find.text('Campaign'), findsNothing);
        expect(find.byTooltip('Show all columns'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'identity survives and primary drops at the ~272px content width '
      "AdaptiveScaffold leaves after a 320px screen's 24px gutters, without "
      'throwing',
      (tester) async {
        await _pump(
          tester,
          width: 272,
          rowDetailBuilder: (r) => Text('detail ${r.id}'),
        );

        expect(find.text('Code'), findsOneWidget);
        expect(find.text('Campaign'), findsNothing);
        expect(find.byTooltip('Show all columns'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a StatusChip column too wide for the viewport drops instead of '
      'overflowing',
      (tester) async {
        // StatusChip is a Container wrapping a Row (icon + label) with no
        // overflow handling of its own. Round 1 protected it by shrinking
        // its column and clipping the paint; that also silently hard-clipped
        // ordinary Text cells site-wide. Now the column either renders at
        // its full declared minWidth (the caller's job is to pick one wide
        // enough for the content, per §5.4) or is dropped entirely — so the
        // chip is never asked to fit somewhere narrower than minWidth.
        final columns = <BmdColumn<_Row>>[
          BmdColumn(
            id: 'id',
            label: 'Code',
            priority: BmdColumnPriority.identity,
            minWidth: 60,
            cell: (r) => Text(r.id),
          ),
          BmdColumn(
            id: 'status',
            label: 'Status',
            priority: BmdColumnPriority.primary,
            minWidth: 200,
            cell: (_) => const StatusChip(
              label: 'Needs manual profile review',
              tone: StatusTone.warning,
            ),
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            theme: bmdTheme(),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 150,
                  height: 400,
                  child: BmdDataTable<_Row>(
                    columns: columns,
                    rows: _rows,
                    rowId: (r) => r.id,
                    rowDetailBuilder: (r) => Text('detail ${r.id}'),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(find.text('Code'), findsOneWidget);
        expect(find.text('Needs manual profile review'), findsNothing);
        expect(find.byTooltip('Show all columns'), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('cell content never hard-clips text', () {
    // Regression coverage for a round-1 mistake: cells were once laid out
    // under an unconstrained width (to stop a StatusChip's inner Row from
    // overflowing) and then physically clipped, which silently defeated
    // `overflow: TextOverflow.ellipsis` for every Text cell, not just
    // StatusChip ones. A hard-clipped cell reports a laid-out width far
    // larger than its column (its full, uncut natural width); an ellipsized
    // one reports a width close to the column's actual content width,
    // because the ellipsis is what makes it stop there.
    testWidgets('a long text value ellipsizes within its column instead of '
        'rendering at its full natural width', (tester) async {
      const longName =
          'A campaign name so long it could never fit any reasonable '
          'column width, used here purely to force truncation';

      final columns = <BmdColumn<_Row>>[
        BmdColumn(
          id: 'id',
          label: 'Code',
          priority: BmdColumnPriority.identity,
          minWidth: 60,
          cell: (r) => Text(r.id),
        ),
        BmdColumn(
          id: 'name',
          label: 'Campaign',
          priority: BmdColumnPriority.primary,
          minWidth: 300,
          cell: (_) => const Text(longName),
        ),
      ];

      // budget (360, no select/detail chrome) == identityMin (60) +
      // primaryMin (300) exactly, so slack is 0 and the primary column's
      // width is deterministically 300px regardless of flex.
      await tester.pumpWidget(
        MaterialApp(
          theme: bmdTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 400,
                child: BmdDataTable<_Row>(
                  columns: columns,
                  rows: _rows,
                  rowId: (r) => r.id,
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final laidOutWidth = tester.getSize(find.text(longName).first).width;

      // The column itself is 300px wide (24px of horizontal padding taken
      // out by BmdSpace.s3 on each side leaves ~276px for the text). An
      // ellipsized line reports a width close to that. A hard-clipped,
      // unconstrained line would report its full natural width, which for
      // this string is several hundred pixels wider than the column.
      expect(laidOutWidth, lessThanOrEqualTo(300));
      expect(laidOutWidth, greaterThan(200));
    });
  });

  group('selection', () {
    testWidgets('select-all covers exactly the rendered rows', (tester) async {
      Set<String>? selection;
      await tester.pumpWidget(
        MaterialApp(
          theme: bmdTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 400,
              child: BmdDataTable<_Row>(
                columns: _columns(),
                rows: _rows,
                rowId: (r) => r.id,
                selectable: true,
                onSelectionChanged: (s) => selection = s,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();

      expect(selection, {'C-1', 'C-2'});
    });

    testWidgets(
      'the select-all checkbox is indeterminate for a partial selection',
      (tester) async {
        Future<void> pumpWith(Set<String> selectedIds) => tester.pumpWidget(
          MaterialApp(
            theme: bmdTheme(),
            home: Scaffold(
              body: SizedBox(
                width: 1200,
                height: 400,
                child: BmdDataTable<_Row>(
                  columns: _columns(),
                  rows: _rows,
                  rowId: (r) => r.id,
                  selectable: true,
                  selectedIds: selectedIds,
                ),
              ),
            ),
          ),
        );

        await pumpWith({});
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          false,
        );

        await pumpWith({'C-1'});
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          isNull,
        );

        await pumpWith({'C-1', 'C-2'});
        expect(
          tester.widget<Checkbox>(find.byType(Checkbox).first).value,
          true,
        );
      },
    );
  });
}
