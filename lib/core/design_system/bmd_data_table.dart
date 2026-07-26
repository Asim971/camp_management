import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// A column definition for [BmdDataTable].
class BmdColumn<T> {
  const BmdColumn({
    required this.id,
    required this.label,
    required this.cell,
    this.width = 160,
    this.numeric = false,
  });

  final String id;
  final String label;
  final double width;
  final bool numeric;

  /// Builds the cell content for a row. Keep it lightweight — it renders for
  /// every visible row.
  final Widget Function(T row) cell;
}

/// The shared operational table (Guideline §5.5, §11). One implementation reused
/// by campaign list, import results, CRM queue, Carpenter 360 and analytics
/// drill tables.
///
///  * **Vertically virtualized** — `ListView.builder` renders only visible rows,
///    so 10k-row result sets stay smooth.
///  * **Sticky header** — the header stays pinned while the body scrolls.
///  * **Horizontal scroll** — wide tables scroll sideways as a unit; the page
///    body never scrolls horizontally.
///  * **Safe bulk-select** — opt-in via [selectable]; the caller decides where a
///    batch action is safe (bulk assign yes, bulk approve no — §8.12).
///  * **Compact 44–48px rows** with a sticky header and accessible semantics.
///
/// NOTE: a horizontally *frozen* identity column is a planned enhancement
/// (needs a linked scroll-controller group); tracked under Task T-0.2.7.
class BmdDataTable<T> extends StatefulWidget {
  const BmdDataTable({
    required this.columns,
    required this.rows,
    required this.rowId,
    this.onRowTap,
    this.selectable = false,
    this.selectedIds = const {},
    this.onSelectionChanged,
    super.key,
  });

  final List<BmdColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowId;
  final void Function(T row)? onRowTap;

  final bool selectable;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;

  @override
  State<BmdDataTable<T>> createState() => _BmdDataTableState<T>();
}

class _BmdDataTableState<T> extends State<BmdDataTable<T>> {
  final _horizontal = ScrollController();

  static const double _rowHeight = BmdSize.rowHeight; // 46
  static const double _selectWidth = 48;

  double get _totalWidth =>
      (widget.selectable ? _selectWidth : 0) +
      widget.columns.fold(0.0, (sum, c) => sum + c.width);

  void _toggle(String id, bool? on) {
    final next = Set<String>.from(widget.selectedIds);
    (on ?? false) ? next.add(id) : next.remove(id);
    widget.onSelectionChanged?.call(next);
  }

  void _toggleAll(bool? on) {
    final next = (on ?? false)
        ? widget.rows.map(widget.rowId).toSet()
        : <String>{};
    widget.onSelectionChanged?.call(next);
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allSelected = widget.rows.isNotEmpty &&
        widget.selectedIds.length == widget.rows.length;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(BmdRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        child: Scrollbar(
          controller: _horizontal,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: _totalWidth < 0 ? 0 : _totalWidth,
              child: Column(
                children: [
                  _header(theme, allSelected),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.rows.length,
                      itemExtent: _rowHeight,
                      itemBuilder: (context, i) => _row(theme, widget.rows[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme, bool allSelected) {
    final style = theme.textTheme.labelMedium?.copyWith(color: BmdColor.ink700);
    return Container(
      height: _rowHeight,
      color: BmdColor.navy50,
      child: Row(
        children: [
          if (widget.selectable)
            SizedBox(
              width: _selectWidth,
              child: Checkbox(
                value: allSelected,
                tristate: true,
                onChanged: _toggleAll,
              ),
            ),
          for (final col in widget.columns)
            SizedBox(
              width: col.width,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BmdSpace.s3),
                child: Align(
                  alignment:
                      col.numeric ? Alignment.centerRight : Alignment.centerLeft,
                  child: Text(col.label, style: style),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(ThemeData theme, T row) {
    final id = widget.rowId(row);
    final selected = widget.selectedIds.contains(id);

    return Semantics(
      button: widget.onRowTap != null,
      selected: widget.selectable ? selected : null,
      child: InkWell(
        onTap: widget.onRowTap == null ? null : () => widget.onRowTap!(row),
        child: Container(
          height: _rowHeight,
          color: selected ? BmdColor.red50 : null,
          child: Row(
            children: [
              if (widget.selectable)
                SizedBox(
                  width: _selectWidth,
                  child: Checkbox(
                    value: selected,
                    onChanged: (on) => _toggle(id, on),
                  ),
                ),
              for (final col in widget.columns)
                SizedBox(
                  width: col.width,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: BmdSpace.s3),
                    child: Align(
                      alignment: col.numeric
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: DefaultTextStyle.merge(
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        child: col.cell(row),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
