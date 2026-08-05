import 'package:acsl_campaign/app/theme/bmd_theme.dart';
import 'package:acsl_campaign/core/design_system/bmd_data_table.dart';
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
  });
}
