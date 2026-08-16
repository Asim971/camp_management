import 'package:flutter/material.dart';

import '../../../../domain/analytics/analytics_summary.dart';

/// The three date-range presets as [ChoiceChip]s, each wrapped in a
/// `Semantics(identifier: 'analytics_range_<preset.name>')` (spec RD3.D2,
/// Task 6). Shared by both [AnalyticsPanel] mounts — the global `/analytics`
/// screen and the campaign-detail Analytics tab — so the identifiers and
/// labels can never drift between them.
class RangeChipRow extends StatelessWidget {
  const RangeChipRow({required this.value, required this.onChanged, super.key});

  final DateRangePreset value;
  final ValueChanged<DateRangePreset> onChanged;

  static String labelFor(DateRangePreset preset) => switch (preset) {
    DateRangePreset.d7 => '7d',
    DateRangePreset.d30 => '30d',
    DateRangePreset.d90 => '90d',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final preset in DateRangePreset.values)
          Semantics(
            identifier: 'analytics_range_${preset.name}',
            child: ChoiceChip(
              label: Text(labelFor(preset)),
              selected: value == preset,
              onSelected: (_) => onChanged(preset),
            ),
          ),
      ],
    );
  }
}
