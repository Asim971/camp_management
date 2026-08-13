import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/providers.dart';
import '../../../app/shell/app_shell.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_data_table.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../domain/common/status.dart';
import '../../../domain/import/import_job.dart';
import '../application/import_controller.dart';

/// Bulk Import Job & Results (W-07). Four stages: upload → dry-run (async,
/// polled to a terminal state) → row-level validation → commit. Every row
/// shows a stable id and an explicit outcome; commit persists the
/// committable rows (valid + needs-profile) and is idempotent.
class BulkImportScreen extends ConsumerWidget {
  const BulkImportScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider(campaignId));
    final c = ref.read(importControllerProvider(campaignId).notifier);

    return AppShell(
      title: 'Bulk import',
      breadcrumb: const ['Campaigns'],
      body: ListView(
        children: [
          _UploadPanel(
            onPick: () async {
              final result = await ref.read(fileSourceProvider).pickCsv();
              if (result != null) {
                await c.uploadDryRun(result.bytes, result.name);
              }
            },
          ),
          const SizedBox(height: 16),
          state.job.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, __) => const Text(
              'Import failed to process. Check the file and retry.',
            ),
            data: (job) => job == null
                ? const _Hint()
                : _Results(
                    job: job,
                    committing: state.committing,
                    onCommit: c.commit,
                  ),
          ),
        ],
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({required this.onPick});
  final Future<void> Function() onPick;
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        // A Row([Expanded(description), Download template, Choose file])
        // clamps the Expanded description to near-zero on a narrow
        // CI-emulator viewport (~320-360dp) once both buttons' intrinsic
        // widths are subtracted from it — rendering the description one
        // letter per line and pushing/clipping "Choose file" (import_pick,
        // the id the bulk-import e2e flow drives) off-screen. The
        // description now takes the full card width on its own line, with
        // the actions below in a Wrap that flows to a second line rather
        // than overflowing horizontally.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload a participant CSV using the approved template. '
              'A dry run validates every row before anything is committed.',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                BmdButton(
                  label: 'Download template',
                  variant: BmdButtonVariant.text,
                  onPressed: () {
                    /* asset: assets/templates/participants_template.csv */
                  },
                ),
                BmdButton(
                  identifier: 'import_pick',
                  label: 'Choose file',
                  icon: Icons.upload_file,
                  onPressed: () => onPick(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: Text('No import yet. Choose a file to dry-run.')),
  );
}

class _Results extends StatelessWidget {
  const _Results({
    required this.job,
    required this.committing,
    required this.onCommit,
  });
  final ImportJob job;
  final bool committing;
  final Future<void> Function() onCommit;

  ({String label, StatusTone tone}) _outcome(ImportRowOutcome o) => switch (o) {
    ImportRowOutcome.valid => (label: 'Valid', tone: StatusTone.success),
    ImportRowOutcome.warning => (label: 'Warning', tone: StatusTone.warning),
    ImportRowOutcome.duplicate => (
      label: 'Duplicate',
      tone: StatusTone.warning,
    ),
    ImportRowOutcome.needsProfile => (
      label: 'Needs profile',
      tone: StatusTone.info,
    ),
    ImportRowOutcome.unauthorized => (
      label: 'Unauthorized',
      tone: StatusTone.error,
    ),
    ImportRowOutcome.error => (label: 'Error', tone: StatusTone.error),
  };

  /// Stable, status-derived header text. "Ready to commit" in particular is
  /// asserted verbatim by the E2E flow (Task 11) as the signal that polling
  /// has reached a terminal, committable state — it must not be rephrased
  /// without updating that assertion.
  String get _statusHeadline => switch (job.status) {
    ImportStatus.processing => 'Processing import…',
    ImportStatus.readyToCommit || ImportStatus.dryRun => 'Ready to commit',
    ImportStatus.failed => 'Import failed. Check the file and retry.',
    ImportStatus.completed => 'Import completed.',
    ImportStatus.partiallyCompleted => 'Import completed with rows skipped.',
    ImportStatus.cancelled => 'Import cancelled.',
  };

  bool get _canCommit =>
      (job.status == ImportStatus.readyToCommit ||
          job.status == ImportStatus.dryRun) &&
      job.committable > 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (job.status == ImportStatus.processing) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
        ],
        Text(_statusHeadline, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        // Dry-run summary.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in ImportRowOutcome.values)
              if (job.count(o) > 0)
                StatusChip(
                  label: '${_outcome(o).label}: ${job.count(o)}',
                  tone: _outcome(o).tone,
                ),
          ],
        ),
        const SizedBox(height: 16),
        // Row-level validation table.
        SizedBox(
          height: 360,
          child: BmdDataTable<ImportRow>(
            rows: job.rows,
            rowId: (r) => r.rowId,
            rowDetailTitle: (r) => 'Row ${r.rowId}',
            rowDetailBuilder: (r) {
              final o = _outcome(r.outcome);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.name),
                  const SizedBox(height: BmdSpace.s3),
                  StatusChip(label: o.label, tone: o.tone),
                  const SizedBox(height: BmdSpace.s3),
                  Text(r.message ?? r.linkedCarpenterId ?? '—'),
                ],
              );
            },
            columns: [
              BmdColumn(
                id: 'row',
                label: 'Row',
                priority: BmdColumnPriority.identity,
                minWidth: 80,
                flex: 0,
                cell: (r) => Text(r.rowId),
              ),
              BmdColumn(
                id: 'name',
                label: 'Name',
                priority: BmdColumnPriority.primary,
                minWidth: 160,
                flex: 2,
                cell: (r) => Text(r.name),
              ),
              BmdColumn(
                id: 'outcome',
                label: 'Outcome',
                priority: BmdColumnPriority.primary,
                minWidth: 150,
                cell: (r) {
                  final o = _outcome(r.outcome);
                  return StatusChip(label: o.label, tone: o.tone);
                },
              ),
              BmdColumn(
                id: 'message',
                label: 'Detail / action',
                minWidth: 200,
                flex: 2,
                cell: (r) => Text(r.message ?? r.linkedCarpenterId ?? '—'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Row([Spacer(), BmdButton]) overflowed the same way _UploadPanel's
        // Row did: the label grows with the row count ("Commit N valid
        // row(s)"), and a Spacer cannot shrink a non-flexible sibling that is
        // already wider than the narrow viewport. Align + FittedBox keeps the
        // button right-aligned and scales it down only as much as the
        // viewport actually requires, so the whole control (and its tappable
        // area) always stays fully on-screen rather than being clipped past
        // the edge.
        Align(
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: BmdButton(
              identifier: 'import_commit',
              label: 'Commit ${job.committable} valid row(s)',
              loading: committing,
              onPressed: _canCommit ? () => onCommit() : null,
            ),
          ),
        ),
      ],
    );
  }
}
