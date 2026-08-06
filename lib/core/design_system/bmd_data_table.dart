import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';
import 'bmd_overlays.dart';

/// How hard a column fights for space when the viewport is tight.
enum BmdColumnPriority {
  /// The column that tells the user which row they are reading. Always
  /// shown, even below its own [BmdColumn.minWidth] if there is truly no
  /// other choice — the alternative is an unreadable row, not a missing one.
  identity,

  /// Status, owner, SLA age, next action — rendered before secondary
  /// columns (§5.5). Dropped into the row detail, last-declared first, when
  /// the viewport cannot fit it alongside identity and any primary columns
  /// declared before it.
  primary,

  /// Everything else. Dropped into the row detail first, before any primary
  /// column, when space runs out.
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

  /// Width below which this column is unreadable rather than merely
  /// cramped — a real floor, never shrunk to force a fit (Guideline §5.4:
  /// "the label is the controlled word verbatim — never abbreviated to fit
  /// a column; if it does not fit, the column is too narrow"). A column
  /// that cannot have its minWidth honoured is dropped into the row detail
  /// instead. The one exception is an [BmdColumnPriority.identity] column:
  /// it is never dropped, so if there is nowhere left to cut, it renders
  /// below its own minimum rather than not render at all.
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
///  * **No horizontal scroll.** Columns flex to the viewport: identity
///    always renders (below its own minimum if there is truly no room to
///    spare), primary columns render next and drop into the row detail
///    (last-declared first) once the viewport cannot fit them, secondary
///    columns are admitted only while their [BmdColumn.minWidth] still
///    fits, and leftover width among the columns that do render is shared
///    by [BmdColumn.flex]. No column ever renders narrower than its
///    minWidth to force a fit (§5.4) — it is dropped instead. A frozen
///    identity column is therefore unnecessary — and a frozen column would
///    split each row into two widget subtrees, so a screen reader would
///    read column-major instead of row by row.
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
  ///
  /// `identity` columns are never dropped. `primary` columns are dropped
  /// last-declared-first — each one removed only if identity plus the
  /// remaining primaries still cannot fit their combined minimums — until
  /// what's left fits or none remain. Only once identity and the surviving
  /// primaries fit does the remaining budget admit `secondary` columns, in
  /// declaration order, while their [BmdColumn.minWidth] still fits. No
  /// column here is ever asked to render narrower than its own minWidth
  /// (Guideline §5.4) — a column that cannot have its minimum honoured is
  /// dropped, not shrunk. The single exception is identity: see [_widths].
  List<BmdColumn<T>> _visible(double available) {
    final budget = _contentWidth(available);

    final identity = widget.columns
        .where((c) => c.priority == BmdColumnPriority.identity)
        .toList();
    final primary = widget.columns
        .where((c) => c.priority == BmdColumnPriority.primary)
        .toList();
    final secondary = widget.columns
        .where((c) => c.priority == BmdColumnPriority.secondary)
        .toList();

    final identityMin = identity.fold(0.0, (sum, c) => sum + c.minWidth);

    final keptPrimary = List<BmdColumn<T>>.from(primary);
    while (keptPrimary.isNotEmpty) {
      final primaryMin = keptPrimary.fold(0.0, (sum, c) => sum + c.minWidth);
      if (identityMin + primaryMin <= budget) break;
      keptPrimary.removeLast();
    }

    var remaining =
        budget -
        identityMin -
        keptPrimary.fold(0.0, (sum, c) => sum + c.minWidth);

    final keptSecondaryIds = <String>{};
    for (final column in secondary) {
      if (remaining - column.minWidth < 0) break;
      remaining -= column.minWidth;
      keptSecondaryIds.add(column.id);
    }

    final keptIds = <String>{
      for (final c in identity) c.id,
      for (final c in keptPrimary) c.id,
      ...keptSecondaryIds,
    };

    return widget.columns.where((c) => keptIds.contains(c.id)).toList();
  }

  /// Each column's minimum, plus a flex-weighted share of the slack. Flex
  /// alone would ignore the minimums and starve a wide column next to a
  /// narrow one.
  ///
  /// [_visible] only ever returns a combination whose minimums fit
  /// [_contentWidth] — it drops primary and secondary columns until that is
  /// true. The one case it cannot fix is identity alone still not fitting
  /// (there is nothing left to drop): when that happens, every surviving
  /// column's width is scaled down proportionally to its minWidth so the
  /// total fits exactly rather than overflowing the row's [Row]. In every
  /// other case this is a no-op, because slack is never negative there.
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
              '${widget.columns.length - visible.length} column(s) '
              '(possibly including a primary column) at '
              '${constraints.maxWidth.toStringAsFixed(0)}px with no '
              'rowDetailBuilder, so that data is unreachable. Supply '
              'rowDetailBuilder, lower minWidth, widen the layout, or mark '
              'fewer columns primary/secondary.',
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
                    // The cell is laid out under the column's genuine width
                    // (Align only loosens the minimum, not the maximum), so
                    // a Text cell's `overflow: ellipsis` below still does
                    // its job (Guideline §5.4: never abbreviate a label to
                    // fit — but ellipsis is truncation with a visible
                    // marker, not abbreviation, and is the accepted way to
                    // show "there is more here"). ClipRect is a defensive
                    // backstop only, for a caller-supplied cell widget whose
                    // own internals (e.g. a Flex with no Flexible child)
                    // might otherwise paint a stray pixel past the column —
                    // it is not load-bearing the way it was before this
                    // column's width itself is meant to already fit the
                    // content per its declared minWidth.
                    child: ClipRect(
                      child: Align(
                        alignment: visible[i].numeric
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
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
