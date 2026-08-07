import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/shell/app_shell.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_field.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../domain/verification/verification.dart';
import '../../../domain/verification/verification_case.dart';
import '../application/crm_case_controller.dart';

/// CRM Verification Case (C-02). Three zones: evidence comparison, profile/
/// capture context, and the decision panel. The machine recommendation is
/// presented as a clearly-labelled, separate advisory object — never merged
/// into the decision, and never as a raw score (§8.13).
class CrmCaseScreen extends ConsumerWidget {
  const CrmCaseScreen({required this.attendanceId, super.key});

  final String attendanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(crmCaseControllerProvider(attendanceId));

    return AppShell(
      title: 'Verification case',
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: BmdButton(
            label: 'Retry',
            variant: BmdButtonVariant.outlined,
            onPressed: () =>
                ref.invalidate(crmCaseControllerProvider(attendanceId)),
          ),
        ),
        data: (c) {
          final wide = Breakpoint.of(context).isDesktopUp;
          final evidence = _EvidenceZone(vcase: c);
          final context0 = _ContextZone(vcase: c);
          final decision = _DecisionPanel(attendanceId: attendanceId);

          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: evidence),
                const SizedBox(width: 24),
                Expanded(child: context0),
                const SizedBox(width: 24),
                SizedBox(width: 340, child: decision),
              ],
            );
          }
          return ListView(
            children: [
              evidence,
              const SizedBox(height: 24),
              context0,
              const SizedBox(height: 24),
              decision,
            ],
          );
        },
      ),
    );
  }
}

class _EvidenceZone extends StatelessWidget {
  const _EvidenceZone({required this.vcase});
  final VerificationCase vcase;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Evidence', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _EvidenceImage(
                label: 'Captured',
                url: vcase.capturedImageUrl,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _EvidenceImage(
                label: _refLabel(vcase.machine.referenceSource),
                url: vcase.referenceImageUrl,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _refLabel(ReferenceSource s) => switch (s) {
    ReferenceSource.verifiedProfilePhoto => 'Verified profile photo',
    ReferenceSource.authorizedNidPhoto => 'Authorized NID photo',
    ReferenceSource.approvedBaselinePhoto => 'Approved baseline photo',
    ReferenceSource.unavailable => 'No reference available',
  };
}

class _EvidenceImage extends StatelessWidget {
  const _EvidenceImage({required this.label, required this.url});
  final String label;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        // Same crop + scale for both images so comparison is fair (§8.13).
        AspectRatio(
          aspectRatio: 3 / 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url == null
                ? const ColoredBox(
                    color: Colors.black12,
                    child: Center(child: Text('No reference')),
                  )
                : InteractiveViewer(
                    maxScale: 4,
                    child: Image.network(
                      url!,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, p) => p == null
                          ? child
                          : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (_, __, ___) =>
                          const Center(child: Text('Image unavailable')),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ContextZone extends StatelessWidget {
  const _ContextZone({required this.vcase});
  final VerificationCase vcase;

  @override
  Widget build(BuildContext context) {
    final m = vcase.machine;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Context', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _kv(context, 'Carpenter', vcase.carpenterName),
        _kv(context, 'ID', vcase.carpenterIdMasked), // masked — never full NID
        _kv(context, 'Campaign', vcase.campaignName),
        _kv(context, 'Session', vcase.sessionName),
        _kv(context, 'Captured', vcase.capturedAt.toString()),
        const SizedBox(height: 16),
        // Machine recommendation is a SEPARATE, clearly-labelled advisory block.
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Machine recommendation (advisory)',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    Chip(label: Text('Band: ${_band(m.band)}')),
                    if (m.padReview) const Chip(label: Text('PAD review')),
                    if (m.lowQuality) const Chip(label: Text('Low quality')),
                  ],
                ),
                if (m.reasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final r in m.reasons) Text('• $r'),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(k, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(child: Text(v)),
      ],
    ),
  );

  String _band(MatchBand b) => switch (b) {
    MatchBand.high => 'High',
    MatchBand.medium => 'Medium',
    MatchBand.low => 'Low',
    MatchBand.noReference => 'No reference',
  };
}

class _DecisionPanel extends ConsumerStatefulWidget {
  const _DecisionPanel({required this.attendanceId});
  final String attendanceId;
  @override
  ConsumerState<_DecisionPanel> createState() => _DecisionPanelState();
}

class _DecisionPanelState extends ConsumerState<_DecisionPanel> {
  VerificationOutcome? _outcome;
  final _reason = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _outcome != null && _reason.text.trim().isNotEmpty && !_submitting;

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final result = await ref
        .read(crmCaseControllerProvider(widget.attendanceId).notifier)
        .decide(outcome: _outcome!, reason: _reason.text.trim());
    if (!mounted) return;
    setState(() => _submitting = false);

    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case DecisionResult.submitted:
        messenger.showSnackBar(
          const SnackBar(content: Text('Decision recorded')),
        );
        unawaited(Navigator.of(context).maybePop());
      case DecisionResult.conflict:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Another reviewer already decided. Reloaded.'),
          ),
        );
      case DecisionResult.error:
        messenger.showSnackBar(
          const SnackBar(
            content: Text("Couldn't record the decision. Try again."),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Decision', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            RadioGroup<VerificationOutcome>(
              groupValue: _outcome,
              onChanged: (v) => setState(() => _outcome = v),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final o in VerificationOutcome.values)
                    Semantics(
                      identifier: 'crm_outcome_${o.name}',
                      child: RadioListTile<VerificationOutcome>(
                        dense: true,
                        value: o,
                        title: Text(_label(o)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            BmdField.multiline(
              identifier: 'crm_reason',
              label: 'Reason',
              required: true,
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              helper: 'Recorded with the decision and shown in the audit log.',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            // Confirm the downstream effect before committing (§8.13).
            Text(
              'This updates attendance status, reward eligibility and analytics '
              'inclusion for this record.',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 12),
            BmdButton(
              label: 'Submit decision',
              identifier: 'crm_submit',
              loading: _submitting,
              onPressed: _canSubmit ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  String _label(VerificationOutcome o) => switch (o) {
    VerificationOutcome.approved => 'Approve',
    VerificationOutcome.rejected => 'Reject',
    VerificationOutcome.returnForRecapture => 'Return for recapture',
    VerificationOutcome.escalated => 'Escalate',
  };
}
