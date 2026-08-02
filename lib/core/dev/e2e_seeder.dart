import 'dart:convert';

import 'package:drift/drift.dart';

import '../storage/app_database.dart';

/// Seeds deterministic local data for Maestro E2E runs (test-only; invoked from
/// main() when `AppConfig.e2e`). Provides the offline roster that
/// `carpenter_search` reads and one pending sync item for the queue flow, so
/// those journeys pass without a live backend. See TESTING_MAESTRO.md §3.3.
Future<void> seedE2EData(AppDatabase db, {String seed = ''}) async {
  const sessionId = 'SESSION_E2E';

  final roster = [
    {
      'id': 'CARP_E2E',
      'name': 'Md. Karim',
      'displayId': 'CARP-••4821',
      'phoneSuffix': '821',
      'territory': 'Dhaka North',
      'dealerContext': 'Rahman Traders',
      'thumbnailUrl': null,
      'eligible': true,
      'attendanceState': 'notCaptured',
    },
    {
      'id': 'CARP_E2E_2',
      'name': 'Karim Uddin',
      'displayId': 'CARP-••7734',
      'phoneSuffix': '734',
      'territory': 'Dhaka South',
      'dealerContext': null,
      'thumbnailUrl': null,
      'eligible': true,
      'attendanceState': 'notCaptured',
    },
  ];

  await db
      .into(db.cachedReferences)
      .insertOnConflictUpdate(
        CachedReferencesCompanion.insert(
          key: 'session:$sessionId:registrations',
          valueJson: jsonEncode(roster),
          fetchedAt: DateTime(2026, 7, 26),
        ),
      );

  // One pending item — only when requested (SEED=queue), so capture flows that
  // assert an exact pending count aren't polluted.
  if (seed.contains('queue')) {
    await db
        .into(db.syncTasks)
        .insert(
          SyncTasksCompanion.insert(
            id: 'seed-pending-1',
            type: 'attendance',
            payloadJson: jsonEncode({
              'sessionId': sessionId,
              'carpenterId': 'CARP_E2E_2',
            }),
            createdAt: DateTime(2026, 7, 26),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }
}
