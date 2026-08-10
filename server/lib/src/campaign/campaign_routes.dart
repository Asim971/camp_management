import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/error_envelope.dart';
import 'campaign_repo.dart';

/// `/campaigns` routes. Task 8 wires the two read routes below; Task 9 adds
/// the write routes (create/update/submit/decide) to this same router, each
/// behind its own `requirePermission` and, for the mutating ones,
/// `idempotency`.
///
/// [db] is unused by the read routes themselves — [repo] already wraps it —
/// but is threaded through so Task 9's write routes, which need it directly
/// for `idempotency(db: db)`, don't have to change this function's shape.
///
/// No permission gate on the read routes: reading the campaign list within
/// one's own organization is available to every authenticated role in
/// `permissionsByRole` (`auth/tokens.dart`) today — there is no
/// `campaign_view`-style permission to require. Both routes still run behind
/// `authenticate` wherever this router is mounted, so an unauthenticated
/// caller never reaches them.
///
/// Every query is scoped to `authOf(request).organizationId` inside
/// [CampaignRepo] itself, not as a check applied here after the fact (D7):
/// a campaign in another organization is simply never selected, so
/// `findById` returning `null` is the ONLY signal a missing-vs-foreign
/// campaign ever produces, and both become the ordinary 404 below — never a
/// 403, which would confirm the id exists.
Router campaignRouter({required Db db, required CampaignRepo repo}) {
  final router = Router();

  router.get('/campaigns', (Request request) async {
    final auth = authOf(request);
    final query = request.url.queryParameters;
    final statusValues = request.url.queryParametersAll['status'] ?? const [];

    final statuses = <CampaignStatus>[];
    for (final raw in statusValues) {
      final parsed = CampaignStatus.tryParseWire(raw);
      if (parsed == null) {
        // Silently dropping an unrecognised status would return a superset
        // of what was asked for, not the empty/narrower result the caller
        // expects when they typo a status.
        throw ApiException(
          ApiErrorCode.badRequest,
          message: 'Unknown status value "$raw".',
          details: {'status': raw},
        );
      }
      statuses.add(parsed);
    }

    final result = await repo.list(
      organizationId: auth.organizationId,
      search: query['q'],
      statuses: statuses,
      page: int.tryParse(query['page'] ?? '') ?? 1,
      pageSize: int.tryParse(query['pageSize'] ?? '') ?? 20,
    );

    return _jsonResponse({
      'items': [for (final c in result.items) c.toWireJson()],
      'total': result.total,
    });
  });

  router.get('/campaigns/<id>', (Request request, String id) async {
    final auth = authOf(request);
    final campaign = await repo.findById(
      id,
      organizationId: auth.organizationId,
    );
    if (campaign == null) {
      throw ApiException(ApiErrorCode.notFound);
    }
    return _jsonResponse(campaign.toWireJson());
  });

  return router;
}

Response _jsonResponse(Map<String, Object?> body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
