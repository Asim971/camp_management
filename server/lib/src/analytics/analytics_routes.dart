import 'dart:convert';

import 'package:campaign_contracts/campaign_contracts.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../auth/middleware.dart';
import '../db/pool.dart';
import '../infra/error_envelope.dart';
import 'analytics_repo.dart';

/// `/analytics/summary` — range-scoped, campaign-linked contribution
/// aggregates for the analytics dashboard (A-02, slice 3 RD3.D1). Requires
/// `export`.
///
/// RULING (binding — mirrored on [AnalyticsRepo.summary]): the range governs
/// the ATTENDANCE-DERIVED numbers (`captured`/`inReview`/`approved`/
/// `rejected`/`returned`, `verifiedPerDay`, `bandMix`, and each campaign
/// row's `verified`/`inReview`); `funnel.target`/`registered` are STRUCTURAL
/// denominators drawn from the campaign and registration tables, which carry
/// no ranged meaning of their own, and are therefore computed unranged by
/// design. This resolves the spec's two sentences ("every number shares one
/// range" and target/registered being properties of the campaign itself)
/// into one envelope.
Router analyticsRouter({required Db db}) {
  final router = Router();
  final repo = AnalyticsRepo(db);

  router.get(
    '/analytics/summary',
    const Pipeline().addMiddleware(requirePermission('export')).addHandler((
      Request request,
    ) async {
      final auth = authOf(request);
      final qp = request.url.queryParameters;
      final now = DateTime.now().toUtc();
      final to = qp['to'] == null ? now : DateTime.tryParse(qp['to']!);
      final from = qp['from'] == null
          ? (to ?? now).subtract(const Duration(days: 29))
          : DateTime.tryParse(qp['from']!);
      if (from == null || to == null || from.isAfter(to)) {
        throw ApiException(
          ApiErrorCode.badRequest,
          message: 'Invalid analytics range.',
        );
      }
      final result = await repo.summary(
        organizationId: auth.organizationId,
        campaignId: qp['campaignId'],
        from: from,
        to: to,
      );
      return _json(result);
    }),
  );

  return router;
}

Response _json(Object? body) => Response.ok(
  jsonEncode(body),
  headers: {'content-type': 'application/json'},
);
