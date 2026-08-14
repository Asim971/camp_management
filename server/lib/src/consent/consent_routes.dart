import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../db/pool.dart';

/// `GET /consent/notices` — authenticate-only (any org member). A background
/// refresh off the capture path; capture uses the client's bundled notice.
Router consentRouter({required Db db}) {
  final router = Router();

  router.get('/consent/notices', (Request request) async {
    final res = await db.execute(
      'SELECT version, language, title, body, content_hash '
      'FROM consent_notices ORDER BY version DESC, language',
    );
    final notices = [
      for (final raw in res)
        () {
          final r = row(raw);
          return {
            'version': r['version'],
            'language': r['language'],
            'title': r['title'],
            'body': r['body'],
            'contentHash': r['content_hash'],
          };
        }(),
    ];
    return Response.ok(
      jsonEncode({'notices': notices}),
      headers: {'content-type': 'application/json'},
    );
  });

  return router;
}
