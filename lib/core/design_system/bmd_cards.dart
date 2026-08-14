import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// A KPI card carrying everything needed to defend the number (Guideline §6.3).
///
/// There are no bare numbers in this system. A value with no denominator and no
/// definition gets quoted in a board pack and cannot be traced back, so every
/// required element is a constructor argument rather than an option: label,
/// value, denominator where the metric is a rate, definition, source and
/// freshness.
///
/// Activity and outcome are never placed in the same KPI row — a reader
/// scanning four numbers will treat them as the same kind of thing.
class KpiCard extends StatelessWidget {
  const KpiCard({
    required this.label,
    required this.value,
    required this.definition,
    required this.source,
    required this.freshness,
    this.denominator,
    this.delta,
    this.deltaDirection = KpiDelta.flat,
    this.deltaContext,
    this.footer,
    this.glass = false,
    super.key,
  });

  /// A clear business term, not a database name.
  final String label;

  /// Distinct count, rate or canonical quantity with its unit.
  final String value;

  /// Visible on the card wherever the metric is a rate — not hidden in a
  /// tooltip, because the card is what gets screenshotted.
  final String? denominator;

  /// Formula and exclusions, surfaced through the info affordance.
  final String definition;

  /// Campaign, attendance, verification, Sales Eco or order facts.
  final String source;

  /// Last refresh, plus any delayed-data note.
  final String freshness;

  final String? delta;
  final KpiDelta deltaDirection;
  final String? deltaContext;

  /// Optional extra row — a sparkline, a caveat, an exclusion note.
  final Widget? footer;

  /// Renders as a translucent glass surface — [BmdTokens.glassFill] fill,
  /// a [BmdTokens.glassBorder] hairline and [BmdElevation.level2] ambient
  /// elevation — instead of the default opaque [Card]. Defaults to false, so
  /// every existing caller keeps today's look unchanged (slice 1).
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;

    final content = Padding(
      padding: const EdgeInsets.all(BmdSpace.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: BmdSpace.s1),
              Tooltip(
                message: definition,
                child: Icon(Icons.info_outline, size: 14, color: bmd.textFaint),
              ),
            ],
          ),
          const SizedBox(height: BmdSpace.s2),
          // A standalone value reads better with proportional figures;
          // tabular is for columns that must align vertically.
          Text(
            value,
            style: theme.textTheme.displayLarge?.copyWith(
              fontSize: 34,
              height: 40 / 34,
              letterSpacing: -0.68,
              fontFeatures: const [FontFeature.proportionalFigures()],
            ),
          ),
          if (denominator != null) ...[
            const SizedBox(height: BmdSpace.s1),
            Text(denominator!, style: theme.textTheme.bodyMedium),
          ],
          if (delta != null) ...[
            const SizedBox(height: BmdSpace.s2),
            Row(
              children: [
                Icon(
                  switch (deltaDirection) {
                    KpiDelta.up => Icons.arrow_upward,
                    KpiDelta.down => Icons.arrow_downward,
                    KpiDelta.flat => Icons.remove,
                  },
                  size: 12,
                  color: _deltaColor(bmd),
                ),
                const SizedBox(width: 2),
                Text(
                  delta!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _deltaColor(bmd),
                  ),
                ),
                if (deltaContext != null) ...[
                  const SizedBox(width: BmdSpace.s2),
                  Flexible(
                    child: Text(
                      deltaContext!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ],
          if (footer != null) ...[const SizedBox(height: BmdSpace.s2), footer!],
          const SizedBox(height: BmdSpace.s2),
          Text('$source · $freshness', style: theme.textTheme.bodySmall),
        ],
      ),
    );

    if (!glass) return Card(child: content);

    // Glass surface (slice 1): a plain Container stands in for the Card so
    // the translucent fill and hairline border are the only edge drawn —
    // stacking this on top of the opaque Card's own themed border would
    // double it up. Radius and padding are unchanged from the default look.
    return Container(
      decoration: BoxDecoration(
        color: bmd.glassFill,
        border: Border.all(color: bmd.glassBorder),
        borderRadius: BorderRadius.circular(BmdRadius.card),
        boxShadow: BmdElevation.level2,
      ),
      child: content,
    );
  }

  Color _deltaColor(BmdTokens bmd) => switch (deltaDirection) {
    KpiDelta.up => bmd.success,
    KpiDelta.down => bmd.error,
    KpiDelta.flat => bmd.textFaint,
  };
}

/// Direction of a KPI comparison. Note this is the direction of *movement*,
/// and the caller decides whether up is good — a rising median time to decision
/// is a [down]-toned fact even though the number went up.
enum KpiDelta { up, down, flat }

/// An exception card — the dashboard's opening block, not its footer (§6.1).
///
/// Dashboards begin with overdue, rejected, pending-sync, no-reference and
/// reconciliation exceptions before any aggregate total, because the first
/// question an operator has in the morning is "what is stuck", not "what is the
/// total".
///
/// The age bar is the point: fourteen breaches whose oldest is twenty-one hours
/// is a different morning from fourteen whose oldest is forty minutes, and a
/// count alone cannot say which one this is.
class ExceptionCard extends StatelessWidget {
  const ExceptionCard({
    required this.label,
    required this.count,
    required this.tone,
    required this.detail,
    this.oldest,
    this.agePressure,
    this.actionLabel,
    this.onAction,
    this.glass = false,
    super.key,
  });

  final String label;
  final String count;
  final ExceptionTone tone;

  /// What the count is made of — "6 unassigned", "7 devices · 3 sessions".
  final String detail;

  /// How long the oldest item in this bucket has waited, e.g. "21h".
  final String? oldest;

  /// 0–1, how far the oldest item has travelled toward its limit. Drives the
  /// hairline bar; pass null to omit it.
  final double? agePressure;

  final String? actionLabel;
  final VoidCallback? onAction;

  /// Renders as a translucent glass surface — [BmdTokens.glassFill] fill,
  /// a [BmdTokens.glassBorder] hairline (the tone accent bar stays on the
  /// leading edge) and [BmdElevation.level2] ambient elevation — instead of
  /// the default opaque [Card]. Defaults to false, so every existing caller
  /// keeps today's look unchanged (slice 1).
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final accent = switch (tone) {
      ExceptionTone.error => bmd.error,
      ExceptionTone.warning => bmd.warning,
      ExceptionTone.info => bmd.info,
    };

    // A [Border] can only combine a [borderRadius] with a non-uniform side
    // color when exactly one side is visible (Flutter throws "A borderRadius
    // can only be given on borders with uniform colors" otherwise) — so the
    // glass surface's all-round [BmdTokens.glassBorder] hairline and the
    // tone accent can't live in the same [BoxDecoration.border]. The accent
    // is drawn as a separate leading bar, clipped to the same corner radius,
    // layered on top of the glass surface instead.
    final body = Container(
      padding: const EdgeInsets.all(BmdSpace.s4),
      decoration: glass
          ? BoxDecoration(
              color: bmd.glassFill,
              border: Border.all(color: bmd.glassBorder),
              borderRadius: BorderRadius.circular(BmdRadius.card),
              boxShadow: BmdElevation.level2,
            )
          : BoxDecoration(
              border: Border(left: BorderSide(color: accent, width: 3)),
              borderRadius: BorderRadius.circular(BmdRadius.card),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(), style: theme.textTheme.labelSmall),
          const SizedBox(height: BmdSpace.s2),
          Text(
            count,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 30,
              height: 34 / 30,
              fontFeatures: const [FontFeature.proportionalFigures()],
            ),
          ),
          if (agePressure != null) ...[
            const SizedBox(height: BmdSpace.s3),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: agePressure!.clamp(0.0, 1.0),
                      minHeight: 4,
                      backgroundColor: bmd.surfaceSunken,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                ),
                if (oldest != null) ...[
                  const SizedBox(width: BmdSpace.s2),
                  Text(oldest!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ],
          const SizedBox(height: BmdSpace.s3),
          Text(detail, style: theme.textTheme.bodySmall),
          if (actionLabel != null) ...[
            const SizedBox(height: BmdSpace.s2),
            InkWell(
              onTap: onAction,
              child: Text(
                '$actionLabel →',
                style: theme.textTheme.bodySmall?.copyWith(color: bmd.info),
              ),
            ),
          ],
        ],
      ),
    );

    if (!glass) return Card(child: body);

    return Stack(
      children: [
        body,
        // `top`/`bottom: 0` (rather than `Positioned.fill` + `Align`) gives
        // this a tight height matching the card exactly — an unconstrained
        // height inside a loosened `Align` collapses to zero.
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 3,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(BmdRadius.card),
              bottomLeft: Radius.circular(BmdRadius.card),
            ),
            child: ColoredBox(color: accent),
          ),
        ),
      ],
    );
  }
}

enum ExceptionTone { error, warning, info }
