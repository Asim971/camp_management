import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/bmd_button.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../domain/campaign/campaign_draft.dart';
import '../application/wizard_controller.dart';

/// Create/Edit Campaign Wizard (W-03). Five steps with a persistent draft save
/// and a final read-only review; submit is blocked until every step validates.
class CampaignWizardScreen extends ConsumerWidget {
  const CampaignWizardScreen({super.key});

  static const _steps = [
    'Basics',
    'Audience',
    'Sessions',
    'Targets',
    'Review',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Navigate away once the campaign has been submitted for approval.
    ref.listen(wizardControllerProvider.select((s) => s.submittedId), (_, id) {
      if (id != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Submitted for approval')),
        );
        context.go('/campaigns');
      }
    });

    final state = ref.watch(wizardControllerProvider);
    final c = ref.read(wizardControllerProvider.notifier);
    final errors = state.showErrors ? state.draft.validate(state.step) : const <String>[];

    return AdaptiveScaffold(
      title: 'Create campaign',
      selectedIndex: 1,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StepHeader(current: state.step, labels: _steps),
          const SizedBox(height: 16),
          if (errors.isNotEmpty) _ErrorSummary(errors: errors),
          Expanded(
            child: SingleChildScrollView(
              child: switch (state.step) {
                0 => _BasicsStep(state: state, c: c),
                1 => _AudienceStep(state: state, c: c),
                2 => _SessionsStep(state: state, c: c),
                3 => _TargetsStep(state: state, c: c),
                _ => _ReviewStep(state: state),
              },
            ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 12),
          _Footer(state: state, c: c),
        ],
      ),
    );
  }
}

// ---- shared step chrome -----------------------------------------------------

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current, required this.labels});
  final int current;
  final List<String> labels;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          CircleAvatar(
            radius: 14,
            backgroundColor: i <= current
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text('${i + 1}',
                style: TextStyle(
                  color: i <= current ? Colors.white : null,
                  fontSize: 12,
                )),
          ),
          const SizedBox(width: 6),
          Text(labels[i], style: Theme.of(context).textTheme.labelMedium),
          if (i < labels.length - 1)
            const Expanded(child: Divider(indent: 8, endIndent: 8)),
        ],
      ],
    );
  }
}

class _ErrorSummary extends StatelessWidget {
  const _ErrorSummary({required this.errors});
  final List<String> errors;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in errors)
            Row(children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(child: Text(e)),
            ]),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.c});
  final WizardState state;
  final WizardController c;
  @override
  Widget build(BuildContext context) {
    final isLast = state.step == WizardState.lastStep;
    return Row(
      children: [
        if (state.step > 0)
          BmdButton(
            label: 'Back',
            variant: BmdButtonVariant.text,
            onPressed: c.back,
          ),
        const Spacer(),
        BmdButton(
          label: 'Save draft',
          variant: BmdButtonVariant.outlined,
          loading: state.saving,
          onPressed: c.saveDraft,
        ),
        const SizedBox(width: 12),
        if (isLast)
          BmdButton(
            label: 'Submit for approval',
            identifier: 'wizard_submit',
            loading: state.submitting,
            onPressed: c.submit,
          )
        else
          BmdButton(
            label: 'Continue',
            identifier: 'wizard_continue',
            onPressed: c.next,
          ),
      ],
    );
  }
}

// ---- steps ------------------------------------------------------------------

class _BasicsStep extends StatelessWidget {
  const _BasicsStep({required this.state, required this.c});
  final WizardState state;
  final WizardController c;
  static const _types = ['seminar', 'workshop', 'roadshow'];
  @override
  Widget build(BuildContext context) {
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: d.name,
          decoration: const InputDecoration(labelText: 'Campaign name'),
          onChanged: (v) => c.edit((x) => x.copyWith(name: v)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: d.type.isEmpty ? null : d.type,
          decoration: const InputDecoration(labelText: 'Campaign type'),
          items: [
            for (final t in _types)
              DropdownMenuItem(value: t, child: Text(t)),
          ],
          onChanged: (v) => c.edit((x) => x.copyWith(type: v ?? '')),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: d.objective,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Objective (optional)'),
          onChanged: (v) => c.edit((x) => x.copyWith(objective: v)),
        ),
      ],
    );
  }
}

class _AudienceStep extends StatelessWidget {
  const _AudienceStep({required this.state, required this.c});
  final WizardState state;
  final WizardController c;
  static const _audiences = [
    'carpenter',
    'contractor',
    'engineer',
    'retailer',
    'dealer',
  ];
  static const _territories = [
    'Dhaka North',
    'Dhaka South',
    'Chattogram',
    'Sylhet',
  ];
  @override
  Widget build(BuildContext context) {
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Audience types', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final a in _audiences)
              FilterChip(
                label: Text(a),
                selected: d.audienceTypes.contains(a),
                onSelected: (on) => c.edit((x) => x.copyWith(
                      audienceTypes: _toggle(x.audienceTypes, a, on),
                    )),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Territories', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final t in _territories)
              FilterChip(
                label: Text(t),
                selected: d.territoryIds.contains(t),
                onSelected: (on) => c.edit((x) => x.copyWith(
                      territoryIds: _toggle(x.territoryIds, t, on),
                    )),
              ),
          ],
        ),
      ],
    );
  }

  List<String> _toggle(List<String> list, String v, bool on) {
    final next = [...list];
    on ? next.add(v) : next.remove(v);
    return next;
  }
}

class _SessionsStep extends StatelessWidget {
  const _SessionsStep({required this.state, required this.c});
  final WizardState state;
  final WizardController c;

  Future<DateTime?> _pick(BuildContext context, DateTime? initial) async {
    final base = initial ?? DateTime(2026, 7, 26, 9);
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      initialDate: base,
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in d.sessions)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: s.venue,
                    decoration: const InputDecoration(labelText: 'Venue'),
                    onChanged: (v) => c.updateSession(s.copyWith(venue: v)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final dt = await _pick(context, s.startAt);
                            if (dt != null) c.updateSession(s.copyWith(startAt: dt));
                          },
                          child: Text(s.startAt == null
                              ? 'Start time'
                              : 'Start: ${s.startAt}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final dt = await _pick(context, s.endAt);
                            if (dt != null) c.updateSession(s.copyWith(endAt: dt));
                          },
                          child: Text(
                              s.endAt == null ? 'End time' : 'End: ${s.endAt}'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => c.removeSession(s.id),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        BmdButton(
          label: 'Add session',
          variant: BmdButtonVariant.tonal,
          icon: Icons.add,
          onPressed: c.addSession,
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: d.geofenceEnabled,
          onChanged: (v) => c.edit((x) => x.copyWith(geofenceEnabled: v)),
          title: const Text('Enforce venue geofence at capture'),
        ),
      ],
    );
  }
}

class _TargetsStep extends StatelessWidget {
  const _TargetsStep({required this.state, required this.c});
  final WizardState state;
  final WizardController c;
  static const _approvers = ['approver-1', 'approver-2'];
  @override
  Widget build(BuildContext context) {
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: d.target == 0 ? '' : '${d.target}',
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Target participants'),
          onChanged: (v) =>
              c.edit((x) => x.copyWith(target: int.tryParse(v) ?? 0)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: d.budgetReference ?? '',
          decoration:
              const InputDecoration(labelText: 'Budget reference (optional)'),
          onChanged: (v) => c.edit((x) => x.copyWith(budgetReference: v)),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: d.approverId,
          decoration: const InputDecoration(labelText: 'Approver'),
          items: [
            for (final a in _approvers)
              DropdownMenuItem(value: a, child: Text(a)),
          ],
          onChanged: (v) => c.edit((x) => x.copyWith(approverId: v)),
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.state});
  final WizardState state;
  @override
  Widget build(BuildContext context) {
    final d = state.draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _row('Name', d.name),
        _row('Type', d.type),
        _row('Audience', d.audienceTypes.join(', ')),
        _row('Territories', d.territoryIds.join(', ')),
        _row('Sessions', '${d.sessions.length}'),
        _row('Target', '${d.target}'),
        _row('Approver', d.approverId ?? '—'),
        const SizedBox(height: 12),
        Row(children: [
          Icon(
            d.isValid ? Icons.check_circle_outline : Icons.error_outline,
            color: d.isValid ? null : Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 8),
          Text(d.isValid
              ? 'Ready to submit for approval'
              : 'Some steps are incomplete'),
        ]),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(k)),
            Expanded(child: Text(v.isEmpty ? '—' : v)),
          ],
        ),
      );
}
