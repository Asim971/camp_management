import 'package:acsl_campaign/core/storage/app_database.dart';
// `show Value` and not a bare import: drift also exports `isNull`, which
// collides with matcher's `isNull` and makes every null assertion below
// ambiguous.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v1.dart' as v1;
import '../../generated/schema_v2.dart' as v2;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  test('migrates v1 to v2', () async {
    final schema = await verifier.schemaAt(1);
    final db = AppDatabase(schema.newConnection());

    await verifier.migrateAndValidate(db, 2);

    await db.close();
  });

  test('preserves queued field data across the upgrade', () async {
    // This is the assertion that protects users. A migration that silently
    // drops a queued attendance capture loses field evidence which cannot be
    // recaptured - the carpenter has left the venue.
    final schema = await verifier.schemaAt(1);

    final oldDb = v1.DatabaseAtV1(schema.newConnection());
    await oldDb
        .into(oldDb.syncTasks)
        .insert(
          v1.SyncTasksData(
            id: 'task-1',
            type: 'attendance',
            payloadJson: '{"sessionId":"s1"}',
            status: 'pendingSync',
            retryCount: 3,
            createdAt: DateTime.utc(2026, 8, 1, 9, 30),
            lastError: 'connection refused',
          ),
        );
    await oldDb
        .into(oldDb.attendanceDrafts)
        .insert(
          v1.AttendanceDraftsData(
            id: 'task-1',
            sessionId: 's1',
            carpenterId: 'c1',
            encryptedMediaPath: '/enc/task-1.bin',
            capturedAt: DateTime.utc(2026, 8, 1, 9, 29),
            capturedBy: 'field-user-1',
          ),
        );
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 2);

    final tasks = await db.select(db.syncTasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.id, 'task-1');
    expect(tasks.single.retryCount, 3);
    expect(tasks.single.lastError, 'connection refused');

    final drafts = await db.select(db.attendanceDrafts).get();
    expect(drafts, hasLength(1));
    expect(drafts.single.encryptedMediaPath, '/enc/task-1.bin');
    expect(drafts.single.capturedBy, 'field-user-1');

    // The new table exists and starts empty.
    expect(await db.select(db.auditEvents).get(), isEmpty);

    await db.close();
  });

  test('migrates v2 to v3', () async {
    final schema = await verifier.schemaAt(2);
    final db = AppDatabase(schema.newConnection());

    await verifier.migrateAndValidate(db, 3);

    await db.close();
  });

  test('v2 to v3 preserves queued field data and audit rows', () async {
    // The assertion that protects users. A migration that drops a queued
    // attendance capture loses field evidence that cannot be recaptured - the
    // carpenter has left the venue.
    final schema = await verifier.schemaAt(2);

    final oldDb = v2.DatabaseAtV2(schema.newConnection());
    await oldDb
        .into(oldDb.syncTasks)
        .insert(
          v2.SyncTasksData(
            id: 'task-1',
            type: 'attendance',
            payloadJson: '{"sessionId":"s1"}',
            status: 'pendingSync',
            retryCount: 2,
            createdAt: DateTime.utc(2026, 8, 1, 9, 30),
            lastError: 'connection refused',
          ),
        );
    await oldDb
        .into(oldDb.attendanceDrafts)
        .insert(
          v2.AttendanceDraftsData(
            id: 'task-1',
            sessionId: 's1',
            carpenterId: 'c1',
            encryptedMediaPath: '/enc/task-1.bin',
            capturedAt: DateTime.utc(2026, 8, 1, 9, 29),
            capturedBy: 'field-user-1',
          ),
        );
    await oldDb
        .into(oldDb.auditEvents)
        .insert(
          v2.AuditEventsData(
            seq: 1,
            id: 'audit-1',
            action: 'attendanceCaptured',
            entity: 'attendance',
            entityId: 'task-1',
            correlationId: 'corr-1',
            actorId: 'field-user-1',
            occurredAt: DateTime.utc(2026, 8, 1, 9, 29, 30),
            attempts: 1,
          ),
        );
    await oldDb.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 3);

    final tasks = await db.select(db.syncTasks).get();
    expect(tasks, hasLength(1));
    expect(tasks.single.retryCount, 2);
    expect(tasks.single.lastError, 'connection refused');

    final drafts = await db.select(db.attendanceDrafts).get();
    expect(drafts, hasLength(1));
    expect(drafts.single.encryptedMediaPath, '/enc/task-1.bin');
    expect(drafts.single.capturedBy, 'field-user-1');
    // Pre-existing rows have no consent - the columns must be nullable.
    expect(drafts.single.consentVersion, isNull);
    expect(drafts.single.consentLanguage, isNull);
    expect(drafts.single.consentShownAt, isNull);
    expect(drafts.single.consentContentHash, isNull);

    // The audit buffer added in v2 survives too: a queued audit event is the
    // only record that an offline action happened at all.
    final audits = await db.select(db.auditEvents).get();
    expect(audits, hasLength(1));
    expect(audits.single.id, 'audit-1');
    expect(audits.single.actorId, 'field-user-1');
    expect(audits.single.attempts, 1);

    expect(await db.select(db.consentNotices).get(), isEmpty);

    await db.close();
  });

  test('the consent columns round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db
        .into(db.attendanceDrafts)
        .insert(
          AttendanceDraftsCompanion.insert(
            id: 'a-1',
            sessionId: 's1',
            carpenterId: 'c1',
            encryptedMediaPath: '/enc/a-1.bin',
            capturedAt: DateTime.utc(2026, 8, 7, 12),
            capturedBy: 'u-1',
            consentVersion: const Value(4),
            consentLanguage: const Value('bn'),
            consentShownAt: Value(DateTime.utc(2026, 8, 7, 11, 59)),
            consentContentHash: const Value('deadbeef'),
          ),
        );

    final row = await db.select(db.attendanceDrafts).getSingle();
    expect(row.consentVersion, 4);
    expect(row.consentLanguage, 'bn');
    expect(row.consentShownAt?.toUtc(), DateTime.utc(2026, 8, 7, 11, 59));
    expect(row.consentContentHash, 'deadbeef');
  });

  test('consent_notices is keyed on version AND language', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    Future<void> put(int version, String language) => db
        .into(db.consentNotices)
        .insert(
          ConsentNoticesCompanion.insert(
            version: version,
            language: language,
            title: 't',
            body: 'b',
            contentHash: 'h',
            fetchedAt: DateTime.utc(2026, 8, 7),
          ),
        );

    // Same version in two languages must coexist.
    await put(1, 'en');
    await put(1, 'bn');

    expect(await db.select(db.consentNotices).get(), hasLength(2));
  });
}
