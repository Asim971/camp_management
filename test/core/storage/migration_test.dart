import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated/schema.dart';
import '../../generated/schema_v1.dart' as v1;

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
}
