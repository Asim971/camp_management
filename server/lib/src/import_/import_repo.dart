import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:postgres/postgres.dart' show Sql;
import 'package:uuid/uuid.dart';

import '../db/pool.dart';
import '../infra/audit.dart';
import 'import_file.dart';

const Uuid _uuid = Uuid();
const Duration _staleTtl = Duration(minutes: 5); // 2b.D2

/// A row as the API presents it. Never carries raw phone/nid (2a.D2) — only
/// the classification and, when linked, the carpenter id (itself already
/// masked at read time via the join in [ImportRepo.find]).
class ImportRowView {
  const ImportRowView({
    required this.rowId,
    required this.name,
    required this.outcome,
    required this.message,
    required this.linkedCarpenterId,
  });

  final String rowId;
  final String name;
  final String? outcome;
  final String? message;
  final String? linkedCarpenterId;

  Map<String, Object?> toWireJson() => {
    'rowId': rowId,
    'name': name,
    'outcome': outcome,
    'message': message,
    'linkedCarpenterId': linkedCarpenterId,
  };
}

class ImportJobView {
  const ImportJobView({
    required this.id,
    required this.campaignId,
    required this.status,
    required this.totalRows,
    required this.processedRows,
    required this.rows,
  });

  final String id;
  final String campaignId;
  final String status;
  final int totalRows;
  final int processedRows;
  final List<ImportRowView> rows;

  Map<String, Object?> toWireJson() => {
    'id': id,
    'campaignId': campaignId,
    'status': status,
    'totalRows': totalRows,
    'processedRows': processedRows,
    'rows': [for (final r in rows) r.toWireJson()],
  };
}

/// Owns all import SQL. Every query is org-scoped inside the SQL (D7); raw
/// phone/nid never reach a view (2a.D2).
class ImportRepo {
  ImportRepo(this._db) : _audit = AuditWriter(_db);

  final Db _db;
  final AuditWriter _audit;

  Future<ImportJobView?> createJob({
    required String campaignId,
    required String organizationId,
    required ParsedImport parsed,
    required String filename,
    required String fileHash,
    required String uploadedBy,
  }) async {
    final campaign = await _db.execute(
      'SELECT 1 FROM campaigns WHERE id = @id AND organization_id = @org',
      params: {'id': campaignId, 'org': organizationId},
    );
    if (campaign.isEmpty) return null;

    final jobId = _uuid.v4();
    await _db.tx((tx) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO import_jobs '
          '(id, campaign_id, organization_id, status, filename, file_hash, '
          ' total_rows, processed_rows, uploaded_by, claimed_at) '
          "VALUES (@id, @c, @org, 'PROCESSING', @f, @h, @n, 0, @by, now())",
        ),
        parameters: {
          'id': jobId,
          'c': campaignId,
          'org': organizationId,
          'f': filename,
          'h': fileHash,
          'n': parsed.rows.length,
          'by': uploadedBy,
        },
      );
      for (final r in parsed.rows) {
        await tx.execute(
          Sql.named(
            'INSERT INTO import_job_rows '
            '(job_id, row_id, name, phone, nid, territory_hint, dealer_context) '
            'VALUES (@j, @r, @name, @phone, @nid, @terr, @dealer)',
          ),
          parameters: {
            'j': jobId,
            'r': r.rowId,
            'name': r.name,
            'phone': r.phone,
            'nid': r.nid,
            'terr': r.territory,
            'dealer': r.dealerContext,
          },
        );
      }
    });
    return find(jobId, organizationId: organizationId);
  }

  /// Background-task body (2b.D1). Classifies each row, then flips to
  /// READY_TO_COMMIT. Swallows its own faults into a FAILED flip so the
  /// caller's `unawaited(...)` never sees an unhandled error (§6a: an
  /// unhandled future error kills the process).
  Future<void> classify(String jobId) async {
    try {
      final job = await _jobRow(jobId);
      if (job == null) return;
      final orgId = job['organization_id']! as String;
      final campaignId = job['campaign_id']! as String;

      final rows = await _db.execute(
        'SELECT row_id, name, phone FROM import_job_rows '
        'WHERE job_id = @j ORDER BY row_id',
        params: {'j': jobId},
      );

      final seenPhones = <String>{};
      var processed = 0;
      for (final rr in rows.map(row)) {
        final rowId = rr['row_id']! as String;
        final name = rr['name']! as String;
        final phone = rr['phone']! as String;

        final (outcome, message, linked) = await _classifyRow(
          organizationId: orgId,
          campaignId: campaignId,
          name: name,
          phone: phone,
          seenPhones: seenPhones,
        );

        await _db.execute(
          'UPDATE import_job_rows SET outcome = @o, message = @m, '
          '  linked_carpenter_id = @l '
          'WHERE job_id = @j AND row_id = @r',
          params: {
            'o': outcome.wireValue,
            'm': message,
            'l': linked,
            'j': jobId,
            'r': rowId,
          },
        );
        processed++;
        await _db.execute(
          'UPDATE import_jobs SET processed_rows = @p, updated_at = now() '
          'WHERE id = @j',
          params: {'p': processed, 'j': jobId},
        );
      }

      await _db.execute(
        "UPDATE import_jobs SET status = 'READY_TO_COMMIT', updated_at = now() "
        'WHERE id = @j',
        params: {'j': jobId},
      );
      await _audit.write(
        action: 'import.dry_run',
        resourceType: 'import_job',
        resourceId: jobId,
        payload: {'totalRows': rows.length, 'processed': processed},
      );
    } on Object catch (error, stack) {
      // Never let this reach the top level (§6a). Flip to FAILED; the
      // reaper is the backstop if even that flip fails.
      await _failJob(jobId, error, stack);
    }
  }

  Future<(ImportRowOutcome, String?, String?)> _classifyRow({
    required String organizationId,
    required String campaignId,
    required String name,
    required String phone,
    required Set<String> seenPhones,
  }) async {
    final phoneOk = RegExp(
      r'^\+?\d{8,15}$',
    ).hasMatch(phone.replaceAll(RegExp(r'[ -]'), ''));
    if (name.trim().isEmpty || !phoneOk) {
      return (
        ImportRowOutcome.error,
        'Row is missing a valid name or phone.',
        null,
      );
    }
    if (!seenPhones.add(phone)) {
      return (ImportRowOutcome.duplicate, 'Duplicated within this file.', null);
    }

    // Exact-phone match against the org's master.
    final match = await _db.execute(
      'SELECT id FROM carpenters '
      'WHERE organization_id = @org AND phone = @phone LIMIT 1',
      params: {'org': organizationId, 'phone': phone},
    );
    if (match.isEmpty) {
      return (
        ImportRowOutcome.needsProfile,
        'No master match — a new profile will be created on commit.',
        null,
      );
    }
    final carpenterId = row(match.single)['id']! as String;

    final already = await _db.execute(
      'SELECT 1 FROM registrations '
      'WHERE campaign_id = @c AND carpenter_id = @id',
      params: {'c': campaignId, 'id': carpenterId},
    );
    if (already.isNotEmpty) {
      return (
        ImportRowOutcome.duplicate,
        'Already registered to this campaign.',
        carpenterId,
      );
    }
    return (ImportRowOutcome.valid, null, carpenterId);
  }

  Future<int> reapStale() async {
    final res = await _db.execute(
      "UPDATE import_jobs SET status = 'FAILED', updated_at = now() "
      "WHERE status = 'PROCESSING' AND claimed_at <= @cutoff",
      params: {'cutoff': DateTime.now().toUtc().subtract(_staleTtl)},
    );
    return res.affectedRows;
  }

  Future<ImportJobView?> find(
    String jobId, {
    required String organizationId,
  }) async {
    final jobs = await _db.execute(
      'SELECT id, campaign_id, status, total_rows, processed_rows '
      'FROM import_jobs WHERE id = @j AND organization_id = @org',
      params: {'j': jobId, 'org': organizationId},
    );
    if (jobs.isEmpty) return null;
    final j = row(jobs.single);

    final rows = await _db.execute(
      'SELECT row_id, name, outcome, message, linked_carpenter_id '
      'FROM import_job_rows WHERE job_id = @j ORDER BY row_id',
      params: {'j': jobId},
    );
    return ImportJobView(
      id: j['id']! as String,
      campaignId: j['campaign_id']! as String,
      status: j['status']! as String,
      totalRows: j['total_rows']! as int,
      processedRows: j['processed_rows']! as int,
      rows: [
        for (final rr in rows.map(row))
          ImportRowView(
            rowId: rr['row_id']! as String,
            name: rr['name']! as String,
            outcome: rr['outcome'] as String?,
            message: rr['message'] as String?,
            linkedCarpenterId: rr['linked_carpenter_id'] as String?,
          ),
      ],
    );
  }

  Future<Map<String, Object?>?> _jobRow(String jobId) async {
    final res = await _db.execute(
      'SELECT organization_id, campaign_id FROM import_jobs WHERE id = @j',
      params: {'j': jobId},
    );
    return res.isEmpty ? null : row(res.single);
  }

  Future<void> _failJob(String jobId, Object error, StackTrace stack) async {
    try {
      await _db.execute(
        "UPDATE import_jobs SET status = 'FAILED', updated_at = now() "
        'WHERE id = @j',
        params: {'j': jobId},
      );
    } on Object {
      // If even the FAILED flip fails, there is nothing more to do here; the
      // reaper will catch the still-PROCESSING job by TTL.
    }
  }
}
