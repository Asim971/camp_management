import 'dart:typed_data';

import '../db/pool.dart';

/// Stores evidence blobs as Postgres BYTEA (sub-project 4a.D2). Already-encrypted
/// by the client, so opaque here. Object storage + encryption-at-rest + retention
/// are sub-project 4b.
class MediaRepo {
  MediaRepo(this._db);
  final Db _db;

  /// Idempotent: a re-uploaded id overwrites (the id is the attendance key, so a
  /// sync retry that re-PUTs is harmless).
  Future<void> put(
    String id, {
    required String contentType,
    required List<int> bytes,
  }) async {
    await _db.execute(
      'INSERT INTO media_objects (id, content_type, bytes) '
      'VALUES (@id, @ct, @b) '
      'ON CONFLICT (id) DO UPDATE SET content_type = @ct, bytes = @b',
      params: {'id': id, 'ct': contentType, 'b': Uint8List.fromList(bytes)},
    );
  }

  Future<({String contentType, List<int> bytes})?> get(String id) async {
    final res = await _db.execute(
      'SELECT content_type, bytes FROM media_objects WHERE id = @id',
      params: {'id': id},
    );
    if (res.isEmpty) return null;
    final r = row(res.single);
    return (
      contentType: r['content_type']! as String,
      bytes: r['bytes']! as List<int>,
    );
  }
}
