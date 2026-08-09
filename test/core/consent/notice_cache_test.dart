import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:acsl_campaign/core/consent/notice_repository.dart';
import 'package:acsl_campaign/core/storage/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Bengali notice as well as an English one, because the hash is computed
/// over UTF-8 BYTE lengths and a multi-byte body is where a rune-vs-byte
/// mistake would show up.
const _notices = [
  ConsentNotice(
    version: 4,
    language: 'en',
    title: 'Attendance notice',
    body: 'Your photo is captured for attendance verification.',
  ),
  ConsentNotice(
    version: 4,
    language: 'bn',
    title: 'উপস্থিতি বিজ্ঞপ্তি',
    body: 'উপস্থিতি যাচাইয়ের জন্য আপনার ছবি নেওয়া হচ্ছে।',
  ),
];

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('driftNoticeWriter stores the REAL hash of each row it writes', () async {
    // Asserting merely that contentHash is non-empty would pass for a
    // placeholder string, which is the exact defect the column exists to make
    // impossible. So the hash is recomputed from the row's OWN persisted
    // fields and compared - if the writer stored a placeholder, or hashed the
    // wrong notice, or reused one hash for every row, this fails.
    await driftNoticeWriter(db)(_notices);

    final rows = await db.select(db.consentNotices).get();
    expect(rows, hasLength(2));

    for (final row in rows) {
      expect(row.contentHash, isNotEmpty);
      expect(
        row.contentHash,
        await consentContentHash(
          version: row.version,
          language: row.language,
          title: row.title,
          body: row.body,
        ),
        reason:
            'consent_notices(${row.version}, ${row.language}).contentHash does '
            'not match a hash recomputed from that row - a stored consent '
            'record naming this version could never be verified.',
      );
    }

    // ...and the two rows do not share a hash, so "equals the recomputed
    // value" cannot be satisfied by a single constant.
    expect(rows[0].contentHash, isNot(rows[1].contentHash));
  });

  test('driftNoticeReader reads back what the writer stored', () async {
    await driftNoticeWriter(db)(_notices);

    final read = await driftNoticeReader(db)();

    expect(read, hasLength(2));
    final byLanguage = {for (final n in read) n.language: n};
    expect(byLanguage['en']!.version, 4);
    expect(byLanguage['en']!.title, 'Attendance notice');
    expect(byLanguage['bn']!.body, contains('ছবি'));
    // Round-tripping through the cache must not change the hash, or a consent
    // record written from a cached notice would not verify.
    expect(await byLanguage['bn']!.hash(), await _notices[1].hash());
  });

  test(
    'rewriting a version replaces its row rather than duplicating',
    () async {
      // This is what bounds the table: insertOrReplace against the
      // (version, language) primary key means at most one row per version per
      // language, which is why ConsentNotices deliberately never prunes.
      await driftNoticeWriter(db)(_notices);
      await driftNoticeWriter(db)(_notices);

      expect(await db.select(db.consentNotices).get(), hasLength(2));
    },
  );

  test(
    'a corrected body for the same version updates the stored hash',
    () async {
      await driftNoticeWriter(db)([_notices[0]]);
      final before =
          (await db.select(db.consentNotices).getSingle()).contentHash;

      await driftNoticeWriter(db)([
        const ConsentNotice(
          version: 4,
          language: 'en',
          title: 'Attendance notice',
          body: 'Corrected wording.',
        ),
      ]);

      final after = await db.select(db.consentNotices).getSingle();
      expect(after.body, 'Corrected wording.');
      expect(after.contentHash, isNot(before));
      expect(
        after.contentHash,
        await consentContentHash(
          version: after.version,
          language: after.language,
          title: after.title,
          body: after.body,
        ),
      );
    },
  );
}
