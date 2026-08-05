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
    // Identity and primary columns are never dropped (see 'never identity'
    // above), but nothing about that guarantees their *combined* minimums
    // fit a genuinely narrow phone. mobileS/mobileL (breakpoints.dart) are
    // supported widths, so the table must degrade to cramped-but-visible
    // rather than a RenderFlex overflow when it cannot honour every
    // rendered column's minWidth.
    testWidgets(
      'identity + primary survive a 250px viewport without throwing',
      (tester) async {
        // identity (120) + primary (200) + detail button (44) = 364px of
        // required content width against a 250px viewport: the combined
        // minimums cannot fit, which is exactly the case that must not
        // overflow.
        await _pump(
          tester,
          width: 250,
          rowDetailBuilder: (r) => Text('detail ${r.id}'),
        );

        expect(find.text('Code'), findsOneWidget);
        expect(find.text('Campaign'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('identity + primary survive a 320px (mobileL) viewport without '
        'throwing', (tester) async {
      await _pump(
        tester,
        width: 320,
        rowDetailBuilder: (r) => Text('detail ${r.id}'),
      );

      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Campaign'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'a StatusChip cell clips instead of overflowing a narrow column',
      (tester) async {
        // StatusChip is a Container wrapping a Row (icon + label): unlike a
        // Text cell, it has no built-in ellipsis, so a too-wide chip in a
        // narrow column is the realistic way a cell's own content — not
        // just the table's column math — can overflow.
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
            minWidth: 60,
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
                  width: 200,
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
      },
    );
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
