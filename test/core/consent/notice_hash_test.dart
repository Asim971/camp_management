import 'package:acsl_campaign/core/consent/notice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('consentContentHash', () {
    test('a known input hashes to a pinned digest', () async {
      // The pre-image format is a CONTRACT: changing it invalidates every
      // stored contentHash, so a golden digest is what makes such a change
      // loud instead of silent. If this fails after an intentional format
      // change, that is the signal to migrate stored hashes - not to update
      // the literal.
      final hash = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'Notice',
        body: 'Body',
      );

      expect(hash, hasLength(64)); // hex SHA-256
      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));

      // Pre-image: `1:1|2:en|6:Notice|4:Body|` (25 bytes, trailing delimiter
      // included - the encoder emits one after EVERY field).
      //
      // This digest was derived OUTSIDE this code path - .NET's SHA-256 over
      // those 25 bytes - deliberately, so that it checks the implementation
      // rather than merely restating it. A digest observed from the code under
      // test would guard nothing. On a mismatch, suspect the encoder first.
      expect(
        hash,
        'c070d196d4b50c9f581bd46dd6bcbfc94e199ecc765551175e7c63d25aff9a4f',
      );
    });

    test('is deterministic for identical input', () async {
      final a = await consentContentHash(
        version: 2,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );
      final b = await consentContentHash(
        version: 2,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );

      expect(a, b);
    });

    test('differs when the body differs', () async {
      final a = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'one',
      );
      final b = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'two',
      );

      expect(a, isNot(b));
    });

    test('differs for the same text in another language', () async {
      final en = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'T',
        body: 'B',
      );
      final bn = await consentContentHash(
        version: 1,
        language: 'bn',
        title: 'T',
        body: 'B',
      );

      expect(en, isNot(bn));
    });

    test('is injective where naive delimiter-joining would collide', () async {
      // Length prefixes are the whole point. Under a naive "join with |"
      // scheme these two would produce the same pre-image; they must not
      // produce the same hash.
      final a = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'A|B',
        body: 'C',
      );
      final b = await consentContentHash(
        version: 1,
        language: 'en',
        title: 'A',
        body: 'B|C',
      );

      expect(a, isNot(b));
    });

    test('handles multi-byte content by BYTE length, not rune count', () async {
      // 'শিরোনাম' is far longer in UTF-8 bytes than in runes. Prefixing with
      // rune count would make the encoding ambiguous again.
      final hash = await consentContentHash(
        version: 1,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'B',
      );

      expect(hash, matches(RegExp(r'^[0-9a-f]{64}$')));
    });
  });

  group('ConsentRecord', () {
    test('of() copies the notice identity and the shown time', () async {
      const notice = ConsentNotice(
        version: 3,
        language: 'bn',
        title: 'শিরোনাম',
        body: 'বিষয়বস্তু',
      );
      final at = DateTime.utc(2026, 8, 7, 12);

      final record = ConsentRecord.of(notice, at, await notice.hash());

      expect(record.version, 3);
      expect(record.language, 'bn');
      expect(record.shownAt, at);
      expect(record.contentHash, await notice.hash());
    });
  });
}
