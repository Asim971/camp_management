import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// A consent/purpose notice as shown to a carpenter (Guideline §10.3).
class ConsentNotice {
  const ConsentNotice({
    required this.version,
    required this.language,
    required this.title,
    required this.body,
  });

  /// Monotonic integer, deliberately not a version string: "newest held
  /// version wins" needs an unambiguous comparison, and semver-style strings
  /// invite `'10' < '9'`.
  final int version;

  final String language; // 'en' | 'bn'
  final String title;
  final String body;

  Future<String> hash() => consentContentHash(
    version: version,
    language: language,
    title: title,
    body: body,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'language': language,
    'title': title,
    'body': body,
  };

  static ConsentNotice fromJson(Map<String, Object?> json) => ConsentNotice(
    version: (json['version']! as num).toInt(),
    language: json['language']! as String,
    title: json['title']! as String,
    body: json['body']! as String,
  );
}

/// What was actually shown, recorded with each capture.
///
/// Stores the hash rather than the text, so the record PROVES the wording
/// instead of merely pointing at a version — on a dispute, fetch version N in
/// language L and verify the hash matches.
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.language,
    required this.shownAt,
    required this.contentHash,
  });

  /// The hash is passed in rather than computed here because
  /// [ConsentNotice.hash] is asynchronous and this is a const-capable factory.
  /// Callers pass `await notice.hash()`.
  factory ConsentRecord.of(
    ConsentNotice notice,
    DateTime shownAt,
    String contentHash,
  ) => ConsentRecord(
    version: notice.version,
    language: notice.language,
    shownAt: shownAt,
    contentHash: contentHash,
  );

  final int version;
  final String language;
  final DateTime shownAt;
  final String contentHash;
}

/// SHA-256 over a LENGTH-PREFIXED pre-image.
///
/// "Join the fields with a delimiter that cannot appear in the content" is not
/// a real guarantee — any byte can appear in a title or body, so a notice
/// containing the delimiter would collide with a different notice that splits
/// differently. Each field is therefore written as its UTF-8 BYTE length, a
/// colon, then its bytes, then a `|`. For
/// `version: 1, language: 'en', title: 'Notice', body: 'Body'` the pre-image is
/// exactly these 25 bytes:
///
///     1:1|2:en|6:Notice|4:Body|
///
/// Note the TRAILING `|`: the delimiter follows every field, the last one
/// included. There is no special case for the final field.
///
/// The `|` is decorative. The length prefixes are what carry the injectivity
/// guarantee — `1:1` `2:en` `6:Notice` `4:Body` is already unambiguous with no
/// separator at all. The pipes are retained only so that a human debugging a
/// digest mismatch can read the pre-image at a glance. Do not mistake them for
/// the thing making this safe; equally, do not remove them, because they are
/// part of the byte sequence that stored hashes were computed over.
///
/// Byte length, not rune count: a Bengali title is far longer in bytes than in
/// runes, and prefixing with runes would reintroduce the ambiguity.
///
/// THIS FORMAT IS A CONTRACT. Changing it — including dropping the trailing
/// delimiter — invalidates every previously written `contentHash`, which is why
/// a test pins a known input to a digest derived outside this function.
Future<String> consentContentHash({
  required int version,
  required String language,
  required String title,
  required String body,
}) async {
  final buffer = <int>[];
  for (final field in [version.toString(), language, title, body]) {
    final bytes = utf8.encode(field);
    buffer.addAll(utf8.encode('${bytes.length}:'));
    buffer.addAll(bytes);
    buffer.addAll(utf8.encode('|'));
  }

  final digest = await Sha256().hash(buffer);
  return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
