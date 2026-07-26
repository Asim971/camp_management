import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../domain/campaign/campaign.dart';
import '../../../domain/campaign/campaign_repository.dart';
import '../../../domain/common/status.dart';
import '../application/approval_controller.dart';

/// Campaign Approval (W-04). Two columns: the submitted plan and the decision
/// panel. Approve is blocked on unacknowledged warnings and on a segregation-of-
/// duties violation; return/reject require a reason.
class CampaignApprovalScreen extends ConsumerWidget {
  const CampaignApprovalScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(approvalControllerProvider(campaignId));

    return AdaptiveScaffold(
      title: 'Campaign approval',
      selectedIndex: 1,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: BmdButton(
            label: 'Retry',
            variant: BmdButtonVariant.outlined,
            onPressed: () =>
                ref.invalidate(approvalControllerProvider(campaignId)),
          ),
        ),
        data: (campaign) {
          final plan = _PlanSummary(campaign: campaign);
          final panel = _DecisionPanel(campaignId: campaignId);
          if (Breakpoint.of(context).isDesktopUp) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: plan),
                const SizedBox(width: 24),
                SizedBox(width: 360, child: panel),
              ],
            );
          }
          return ListView(children: [plan, const SizedBox(height: 24), panel]);
        },
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.campaign});
  final Campaign campaign;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(campaign.name,
                style: Theme.of(context).textTheme.titleLarge),
          ),
          StatusChip(label: campaign.status.name, tone: StatusTone.info),
        ]),
        const SizedBox(height: 12),
        _row(context, 'Type', campaign.type),
        _row(context, 'Owner', campaign.ownerId),
        _row(context, 'Territories', campaign.territoryIds.join(', ')),
        _row(context, 'Target', '${campaign.targetAudience}'),
        _row(context, 'Objective', campaign.objective ?? '—'),
        if (campaign.venue != null) _row(context, 'Venue', campaign.venue!),
      ],
    );
  }

  Widget _row(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: Text(k, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: Text(v.isEmpty ? '—' : v)),
        ]),
      );
}

class _DecisionPanel extends ConsumerStatefulWidget {
  const _DecisionPanel({required this.campaignId});
  final String campaignId;
  @override
  ConsumerState<_DecisionPanel> createState() => _DecisionPanelState();
}

class _DecisionPanelState extends ConsumerState<_DecisionPanel> {
  CampaignDecision? _decision;
  final _reason = TextEditingController();
  bool _acknowledged = false;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _reasonRequired =>
      _decision == CampaignDecision.returnForCorrection ||
      _decision == CampaignDecision.reject;

  bool _canSubmit(bool sod) {
    if (_decision == null || _busy) return false;
    if (_reasonRequired && _reason.text.trim().isEmpty) return false;
    if (_decision == CampaignDecision.approve && (!_acknowledged || sod)) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final result = await ref
        .read(approvalControllerProvider(widget.campaignId).notifier)
        .decide(
          decision: _decision!,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        );
    if (!mounted) return;
    setState(() => _busy = false);
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case ApprovalResult.done:
        messenger.showSnackBar(const SnackBar(content: Text('Decision recorded')));
        context.go('/campaigns');
      case ApprovalResult.conflict:
        messenger.showSnackBar(const SnackBar(
            content: Text('Campaign changed since you opened it. Reloaded.')));
      case ApprovalResult.error:
        messenger.showSnackBar(const SnackBar(
            content: Text("Couldn't record the decision. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sod =
        ref.read(approvalControllerProvider(widget.campaignId).notifier).sodViolation;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Decision', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (sod)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'You created this campaign. Segregation of duties requires a '
                  'different approver — you can return or reject, but not approve.',
                ),
              ),
            for (final d in CampaignDecision.values)
              RadioListTile<CampaignDecision>(
                dense: true,
                value: d,
                groupValue: _decision,
                onChanged: (v) => setState(() => _decision = v),
                title: Text(_label(d)),
              ),
            if (_decision == CampaignDecision.approve)
              CheckboxListTile(
                dense: true,
                value: _acknowledged,
                onChanged: sod
                    ? null
                    : (v) => setState(() => _acknowledged = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('I acknowledge readiness and SoD warnings'),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText:
                    _reasonRequired ? 'Reason (required)' : 'Reason (optional)',
              ),
            ),
            const SizedBox(height: 12),
            BmdButton(
              label: 'Submit decision',
              loading: _busy,
              onPressed: _canSubmit(sod) ? _submit : null,
            ),
          ],
        ),
      ),
    );
  }

  String _label(CampaignDecision d) => switch (d) {
        CampaignDecision.approve => 'Approve',
        CampaignDecision.returnForCorrection => 'Return for correction',
        CampaignDecision.reject => 'Reject',
      };
}
