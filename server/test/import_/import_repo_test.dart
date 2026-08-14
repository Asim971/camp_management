import 'dart:convert';

import 'package:campaign_service/src/db/migrator.dart';
import 'package:campaign_service/src/db/pool.dart';
import 'package:campaign_service/src/import_/import_file.dart';
import 'package:campaign_service/src/import_/import_repo.dart';
import 'package:test/test.dart';

import '../support/seed_fixtures.dart';
import '../support/test_db.dart';

ParsedImport parsedOf(List<ParsedRow> rows) => ParsedImport(rows);

void main() {
  late Db db;
  late ImportRepo repo;

  setUp(() async {
    db = await freshDb();
    await Migrator(db).applyPending();
    await seedOrganizationWithUser(db); // org-1 / user-1 / campaign_creator
    await seedCampaign(db, id: 'camp-1');
    repo = ImportRepo(db);
  });
  tearDown(() async => db.close());

  ParsedRow r(String id, String name, String phone) =>
      ParsedRow(rowId: id, name: name, phone: phone);

  test(
    'createJob returns null for a cross-org campaign (route → 404)',
    () async {
      await seedOrganizationWithUser(
        db,
        orgId: 'org-2',
        territoryId: 't2',
        userId: 'u2',
        username: 'other',
      );
      await seedCampaign(
        db,
        id: 'camp-2',
        organizationId: 'org-2',
        ownerId: 'u2',
      );
      final result = await repo.createJob(
        campaignId: 'camp-2',
        organizationId: 'org-1',
        parsed: parsedOf([r('row-1', 'A', '+8801700000001')]),
        filename: 'x.csv',
        fileHash: 'h',
        uploadedBy: 'user-1',
      );
      expect(result, isNull);
    },
  );

  test('createJob stores a PROCESSING job with rows unclassified', () async {
    final job = await repo.createJob(
      campaignId: 'camp-1',
      organizationId: 'org-1',
      parsed: parsedOf([
        r('row-1', 'Md. Karim', '+8801700004821'),
        r('row-2', 'New Person', '+8801711112222'),
      ]),
      filename: 'x.csv',
      fileHash: 'h',
      uploadedBy: 'user-1',
    );
    expect(job!.status, 'PROCESSING');
    expect(job.totalRows, 2);
    expect(job.rows.every((row) => row.outcome == null), isTrue);
  });

  test(
    'classify assigns each of the four produced outcomes correctly',
    () async {
      // A master carpenter that a row will match (VALID), and a registration
      // that makes another row DUPLICATE.
      await seedCarpenter(
        db,
        id: 'c-1',
        phone: '+8801700004821',
        displayCode: 'CARP-00004821',
      ); // Md. Karim (default name)
      await seedCarpenter(
        db,
        id: 'c-dup',
        name: 'Already Reg',
        phone: '+8801700009999',
        displayCode: 'CARP-00009999',
      );
      await seedRegistration(db, campaignId: 'camp-1', carpenterId: 'c-dup');

      final job = await repo.createJob(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        parsed: parsedOf([
          r('row-1', 'Md. Karim', '+8801700004821'), // matches c-1 → VALID
          r(
            'row-2',
            'Already Reg',
            '+8801700009999',
          ), // c-dup registered → DUPLICATE
          r('row-3', 'Brand New', '+8801733334444'), // no match → NEEDS_PROFILE
          r('row-4', '', ''), // malformed → ERROR
        ]),
        filename: 'x.csv',
        fileHash: 'h',
        uploadedBy: 'user-1',
      );

      await repo.classify(job!.id);

      final done = await repo.find(job.id, organizationId: 'org-1');
      expect(done!.status, 'READY_TO_COMMIT');
      expect(done.processedRows, 4);
      final byRow = {for (final row in done.rows) row.rowId: row.outcome};
      expect(byRow['row-1'], 'VALID');
      expect(byRow['row-2'], 'DUPLICATE');
      expect(byRow['row-3'], 'NEEDS_PROFILE');
      expect(byRow['row-4'], 'ERROR');
      // VALID row is linked to the matched carpenter.
      final valid = done.rows.firstWhere((row) => row.rowId == 'row-1');
      expect(valid.linkedCarpenterId, 'c-1');
    },
  );

  test(
    'classify never emits raw phone in a row message or wire JSON',
    () async {
      final job = await repo.createJob(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        parsed: parsedOf([r('row-1', 'X', 'not-a-phone')]),
        filename: 'x.csv',
        fileHash: 'h',
        uploadedBy: 'user-1',
      );
      await repo.classify(job!.id);
      final done = await repo.find(job.id, organizationId: 'org-1');
      expect(jsonEncodeSafe(done!), isNot(contains('not-a-phone')));
    },
  );

  test('reapStale fails a PROCESSING job older than the TTL', () async {
    await seedImportJob(db, id: 'stale', status: 'PROCESSING', rows: const []);
    // Age its claimed_at past the 5-minute TTL.
    await db.execute(
      "UPDATE import_jobs SET claimed_at = now() - interval '6 minutes' "
      "WHERE id = 'stale'",
    );
    final reaped = await repo.reapStale();
    expect(reaped, greaterThanOrEqualTo(1));
    final job = await repo.find('stale', organizationId: 'org-1');
    expect(job!.status, 'FAILED');
  });

  test('reapStale leaves a fresh PROCESSING job alone', () async {
    await seedImportJob(db, id: 'fresh', status: 'PROCESSING', rows: const []);
    await repo.reapStale();
    final job = await repo.find('fresh', organizationId: 'org-1');
    expect(job!.status, 'PROCESSING');
  });

  test('classify of an unknown job id is a no-op, never throws', () async {
    await repo.classify('nope'); // must not throw
  });

  group('commit', () {
    setUp(() async {
      await seedCarpenter(
        db,
        id: 'c-1',
        phone: '+8801700004821',
        displayCode: 'CARP-00004821',
      );
    });

    Future<ImportJobView> readyJob() async {
      final job = await repo.createJob(
        campaignId: 'camp-1',
        organizationId: 'org-1',
        parsed: parsedOf([
          r('row-1', 'Md. Karim', '+8801700004821'), // VALID (matches c-1)
          r('row-2', 'Brand New', '+8801733334444'), // NEEDS_PROFILE
          r('row-3', '', ''), // ERROR (not committable)
        ]),
        filename: 'x.csv',
        fileHash: 'h',
        uploadedBy: 'user-1',
      );
      await repo.classify(job!.id);
      return (await repo.find(job.id, organizationId: 'org-1'))!;
    }

    test(
      'registers the committable set (valid + needsProfile) and completes',
      () async {
        final job = await readyJob();
        final done = await repo.commit(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          jobId: job.id,
          committedBy: 'user-1',
        );
        expect(done!.status, 'COMPLETED');

        // c-1 registered; a provisional carpenter created + registered for row-2.
        final regs = await db.execute(
          'SELECT carpenter_id FROM registrations WHERE campaign_id = @c',
          params: {'c': 'camp-1'},
        );
        expect(regs, hasLength(2));
        final provisional = await db.execute(
          "SELECT 1 FROM carpenters WHERE source = 'PROFILE_REQUEST' "
          "AND full_name = 'Brand New'",
        );
        expect(provisional, hasLength(1));
      },
    );

    test(
      'a replayed commit registers each row at most once (idempotent set)',
      () async {
        final job = await readyJob();
        await repo.commit(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          jobId: job.id,
          committedBy: 'user-1',
        );
        // The job is COMPLETED now, so a second commit is a 409 at the route;
        // at the repo level, re-committing a COMPLETED job is a no-op guarded by
        // the status check.
        expect(
          () => repo.commit(
            campaignId: 'camp-1',
            organizationId: 'org-1',
            jobId: job.id,
            committedBy: 'user-1',
          ),
          throwsA(isA<Object>()),
        );
        final regs = await db.execute(
          'SELECT 1 FROM registrations WHERE campaign_id = @c',
          params: {'c': 'camp-1'},
        );
        expect(regs, hasLength(2), reason: 'no duplicate registrations');
      },
    );

    test('commit of a not-ready job throws (route → 409)', () async {
      await seedImportJob(db, id: 'proc', status: 'PROCESSING', rows: const []);
      expect(
        () => repo.commit(
          campaignId: 'camp-1',
          organizationId: 'org-1',
          jobId: 'proc',
          committedBy: 'user-1',
        ),
        throwsA(isA<Object>()),
      );
    });

    test('commit of a cross-org job is null (route → 404)', () async {
      final job = await readyJob();
      final result = await repo.commit(
        campaignId: 'camp-1',
        organizationId: 'org-2',
        jobId: job.id,
        committedBy: 'user-1',
      );
      expect(result, isNull);
    });
  });
}

/// jsonEncode over the job's wire JSON — a tiny local helper so the PII
/// assertion reads the actual serialized surface.
String jsonEncodeSafe(ImportJobView j) => jsonEncode(j.toWireJson());
