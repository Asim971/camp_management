import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'bmd_overlays.dart';

/// How hard a column fights for space when the viewport is tight.
enum BmdColumnPriority {
  /// The column that tells the user which row they are reading. Always shown.
  identity,

  /// Status, owner, SLA age, next action — shown before anything else (§5.5).
  primary,

  /// Everything else. Dropped into the row detail when space runs out.
  secondary,
}

/// A column definition for [BmdDataTable].
class BmdColumn<T> {
  const BmdColumn({
    required this.id,
    required this.label,
    required this.cell,
    this.priority = BmdColumnPriority.secondary,
    this.minWidth = 96,
    this.flex = 1,
    this.numeric = false,
  });

  final String id;
  final String label;

  /// The preferred floor below which this column is unreadable rather than
  /// merely cramped — honoured whenever the viewport can afford it. When
  /// even every rendered column's minimum cannot fit at once (a narrow phone
  /// with an identity and a primary column that are both never dropped),
  /// each rendered column is scaled down proportionally to its [minWidth]
  /// instead, so the row stays visible rather than overflowing.
  final double minWidth;

  /// Share of the leftover width once every rendered column has its minimum.
  final int flex;

  final bool numeric;
  final BmdColumnPriority priority;

  /// Builds the cell content for a row. Keep it lightweight — it renders for
  /// every visible row.
  final Widget Function(T row) cell;
}

/// The shared operational table (Guideline §5.5, §11). One implementation
/// reused by campaign list, import results, CRM queue, Carpenter 360 and
/// analytics drill tables.
///
///  * **Vertically virtualized** — `ListView.builder` renders only visible
///    rows, so 10k-row result sets stay smooth.
///  * **Sticky header** — the header stays pinned while the body scrolls.
///  * **No horizontal scroll.** Columns flex to the viewport: identity and
///    primary columns always render, secondary columns are admitted while
///    their [BmdColumn.minWidth] still fits, and leftover width is shared by
///    [BmdColumn.flex]. A frozen identity column is therefore unnecessary —
///    and a frozen column would split each row into two widget subtrees, so a
///    screen reader would read column-major instead of row by row.
///  * **Overflow goes to the side sheet** — §5.3 already sends low-value
///    columns there, so [rowDetailBuilder] renders the whole row on demand.
///  * **Safe bulk-select** — opt-in via [selectable]; the caller decides where
///    a batch action is safe (bulk assign yes, bulk approve no — §8.12).
///  * **Compact 44–48px rows** with one `Semantics` node per row.
class BmdDataTable<T> extends StatefulWidget {
  const BmdDataTable({
    required this.columns,
    required this.rows,
    required this.rowId,
    this.onRowTap,
    this.selectable = false,
    this.selectedIds = const {},
    this.onSelectionChanged,
    this.rowDetailBuilder,
    this.rowDetailTitle,
    super.key,
  });

  final List<BmdColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) rowId;
  final void Function(T row)? onRowTap;

  final bool selectable;
  final Set<String> selectedIds;
  final ValueChanged<Set<String>>? onSelectionChanged;

  /// Renders every field of a row, including columns the viewport could not
  /// fit. Required whenever any column may be dropped.
  final Widget Function(T row)? rowDetailBuilder;

  final String Function(T row)? rowDetailTitle;

  @override
  State<BmdDataTable<T>> createState() => _BmdDataTableState<T>();
}

class _BmdDataTableState<T> extends State<BmdDataTable<T>> {
  static const double _rowHeight = BmdSize.rowHeight; // 46
  static const double _selectWidth = 48;
  static const double _detailWidth = BmdSize.controlHeightWeb; // 44

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

  /// [available] minus the fixed-width chrome (select checkbox column, detail
  /// affordance column) that both [_visible] and [_widths] must subtract
  /// identically before dividing up what is left among the data columns.
  double _contentWidth(double available) {
    var budget = available;
    if (widget.selectable) budget -= _selectWidth;
    if (widget.rowDetailBuilder != null) budget -= _detailWidth;
    return budget;
  }

  /// Columns that fit [available], in declaration order.
  List<BmdColumn<T>> _visible(double available) {
    var budget = _contentWidth(available);

    final kept = <String>{};
    for (final column in widget.columns) {
      if (column.priority != BmdColumnPriority.secondary) {
        kept.add(column.id);
        budget -= column.minWidth;
      }
    }
    for (final column in widget.columns) {
      if (column.priority != BmdColumnPriority.secondary) continue;
      if (budget - column.minWidth < 0) break;
      budget -= column.minWidth;
      kept.add(column.id);
    }

    return widget.columns.where((c) => kept.contains(c.id)).toList();
  }

  /// Each column's minimum, plus a flex-weighted share of the slack. Flex alone
  /// would ignore the minimums and starve a wide column next to a narrow one.
  ///
  /// `identity`/`primary` columns are never dropped by [_visible], so their
  /// minimums can still exceed [available] on a narrow phone. Handing each
  /// its full [BmdColumn.minWidth] in that case would make the sum of
  /// [_widths] exceed the budget and overflow the row's [Row] — so instead
  /// every rendered column's width is scaled down proportionally to its
  /// minWidth until the total fits exactly. The invariant this preserves:
  /// the widths returned here never sum to more than [_contentWidth].
  List<double> _widths(List<BmdColumn<T>> columns, double available) {
    final budget = _contentWidth(available);

    final minSum = columns.fold(0.0, (sum, c) => sum + c.minWidth);
    final slack = budget - minSum;

    if (slack < 0) {
      final clamped = budget <= 0 ? 0.0 : budget;
      if (minSum <= 0) return [for (final _ in columns) 0.0];
      return [for (final column in columns) clamped * column.minWidth / minSum];
    }

    final flexSum = columns.fold(0, (sum, c) => sum + c.flex);
    return [
      for (final column in columns)
        column.minWidth + (flexSum == 0 ? 0 : slack * column.flex / flexSum),
    ];
  }

  Future<void> _showDetail(T row) {
    return showBmdSideSheet<void>(
      context: context,
      title: widget.rowDetailTitle?.call(row) ?? 'Row detail',
      builder: (_) => widget.rowDetailBuilder!(row),
    );
  }

  /// `true` when every row is selected, `false` when none is, `null` for a
  /// partial selection — a genuine tristate value for the header checkbox
  /// rather than the plain bool a partial selection would otherwise collapse
  /// to "unchecked".
  bool? get _headerCheckboxValue {
    if (widget.rows.isEmpty || widget.selectedIds.isEmpty) return false;
    if (widget.selectedIds.length == widget.rows.length) return true;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(BmdRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(BmdRadius.card),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visible = _visible(constraints.maxWidth);
            final widths = _widths(visible, constraints.maxWidth);

            assert(
              visible.length == widget.columns.length ||
                  widget.rowDetailBuilder != null,
              'BmdDataTable dropped '
              '${widget.columns.length - visible.length} column(s) at '
              '${constraints.maxWidth.toStringAsFixed(0)}px with no '
              'rowDetailBuilder, so that data is unreachable. Supply '
              'rowDetailBuilder, lower minWidth, or mark fewer columns '
              'secondary.',
            );

            return Column(
              children: [
                _header(theme, visible, widths, _headerCheckboxValue),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.rows.length,
                    itemExtent: _rowHeight,
                    itemBuilder: (context, i) =>
                        _row(theme, widget.rows[i], visible, widths),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header(
    ThemeData theme,
    List<BmdColumn<T>> visible,
    List<double> widths,
    bool? headerCheckboxValue,
  ) {
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
                value: headerCheckboxValue,
                tristate: true,
                onChanged: _toggleAll,
              ),
            ),
          for (var i = 0; i < visible.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: BmdSpace.s3),
                child: Align(
                  alignment: visible[i].numeric
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    visible[i].label,
                    style: style,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          if (widget.rowDetailBuilder != null)
            const SizedBox(width: _detailWidth),
        ],
      ),
    );
  }

  Widget _row(
    ThemeData theme,
    T row,
    List<BmdColumn<T>> visible,
    List<double> widths,
  ) {
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
              for (var i = 0; i < visible.length; i++)
                SizedBox(
                  width: widths[i],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: BmdSpace.s3,
                    ),
                    // An arbitrary cell widget (a StatusChip is a Row of an
                    // icon and a label with no overflow handling of its own)
                    // can demand more width than a cramped column has. A
                    // bounded maxWidth doesn't prevent that: RenderFlex
                    // overflows whenever a Flex's non-flexible children want
                    // more room than the Flex itself was given, regardless
                    // of anything clipping it from outside. OverflowBox
                    // grants the cell its natural size so nothing inside it
                    // ever overflows, and the surrounding ClipRect trims
                    // the paint back to the column's actual bounds — a hard
                    // clip rather than an ellipsis, but never a crash.
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: visible[i].numeric
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        maxWidth: double.infinity,
                        child: DefaultTextStyle.merge(
                          style: theme.textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          child: visible[i].cell(row),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.rowDetailBuilder != null)
                SizedBox(
                  width: _detailWidth,
                  child: IconButton(
                    tooltip: 'Show all columns',
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onPressed: () => _showDetail(row),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
