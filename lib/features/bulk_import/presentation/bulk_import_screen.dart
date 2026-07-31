import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_data_table.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../core/responsive/adaptive_scaffold.dart';
import '../../../domain/common/status.dart';
import '../../../domain/import/import_job.dart';
import '../application/import_controller.dart';

/// Bulk Import Job & Results (W-07). Four stages: upload → dry-run summary →
/// row-level validation → commit. Every row shows a stable id and an explicit
/// outcome; commit persists only valid rows and is idempotent.
class BulkImportScreen extends ConsumerWidget {
  const BulkImportScreen({required this.campaignId, super.key});
  final String campaignId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(importControllerProvider(campaignId));
    final c = ref.read(importControllerProvider(campaignId).notifier);

    return AdaptiveScaffold(
      title: 'Bulk import',
      selectedIndex: 1,
      body: ListView(
        children: [
          _UploadPanel(
            onPick: () async {
              const csvGroup = XTypeGroup(
                label: 'CSV',
                extensions: <String>['csv'],
                mimeTypes: <String>['text/csv'],
              );
              final file = await openFile(
                acceptedTypeGroups: <XTypeGroup>[csvGroup],
              );
              if (file != null) {
                await c.uploadDryRun(await file.readAsBytes(), file.name);
              }
            },
          ),
          const SizedBox(height: 16),
          state.job.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            )),
            error: (_, __) => const Text(
                'Import failed to process. Check the file and retry.'),
            data: (job) => job == null
                ? const _Hint()
                : _Results(
                    job: job, committing: state.committing, onCommit: c.commit),
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
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'Upload a participant CSV using the approved template. '
                'A dry run validates every row before anything is committed.',
              ),
            ),
            const SizedBox(width: 16),
            BmdButton(
              label: 'Download template',
              variant: BmdButtonVariant.text,
              onPressed: () {
                /* asset: assets/templates/participants_template.csv */
              },
            ),
            const SizedBox(width: 8),
            BmdButton(
              label: 'Choose file',
              icon: Icons.upload_file,
              onPressed: () => onPick(),
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
        ImportRowOutcome.warning => (
            label: 'Warning',
            tone: StatusTone.warning
          ),
        ImportRowOutcome.duplicate => (
            label: 'Duplicate',
            tone: StatusTone.warning
          ),
        ImportRowOutcome.needsProfile => (
            label: 'Needs profile',
            tone: StatusTone.info
          ),
        ImportRowOutcome.unauthorized => (
            label: 'Unauthorized',
            tone: StatusTone.error
          ),
        ImportRowOutcome.error => (label: 'Error', tone: StatusTone.error),
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
            columns: [
              BmdColumn(
                id: 'row',
                label: 'Row',
                width: 80,
                cell: (r) => Text(r.rowId),
              ),
              BmdColumn(
                id: 'name',
                label: 'Name',
                width: 200,
                cell: (r) => Text(r.name),
              ),
              BmdColumn(
                id: 'outcome',
                label: 'Outcome',
                width: 150,
                cell: (r) {
                  final o = _outcome(r.outcome);
                  return StatusChip(label: o.label, tone: o.tone);
                },
              ),
              BmdColumn(
                id: 'message',
                label: 'Detail / action',
                width: 280,
                cell: (r) => Text(r.message ?? r.linkedCarpenterId ?? '—'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Spacer(),
            BmdButton(
              label: 'Commit ${job.committable} valid row(s)',
              loading: committing,
              onPressed: job.committable == 0 ? null : () => onCommit(),
            ),
          ],
        ),
      ],
    );
  }
}
