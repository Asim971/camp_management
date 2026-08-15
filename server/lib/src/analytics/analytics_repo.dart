import '../db/pool.dart';

/// The four `MatchBand` wire values, in the fixed order the wire envelope
/// always presents them (client's `bandMix` map iterates whatever keys are
/// present, but a route/UI expecting all four to at least exist as zero
/// reads more simply than a partial map).
const List<String> _bandKeys = ['HIGH', 'MEDIUM', 'LOW', 'NO_REFERENCE'];

/// Range-scoped, campaign-linked contribution aggregates for the analytics
/// dashboard (A-02, slice 3 RD3.D1).
///
/// RULING (binding — see also the docstring on `analyticsRouter`):
/// `funnel.target`/`registered` are STRUCTURAL denominators drawn from the
/// `campaigns`/`registrations` tables, which carry no `captured_at` (or
/// equivalent) column of their own to range against — a campaign's
/// `target_audience` and its registration count are properties of the
/// campaign itself, not of any particular day. The spec's "every number
/// shares one range" governs the ATTENDANCE-DERIVED numbers only: `captured`,
/// `inReview`, `approved`, `rejected`, `returned`, `verifiedPerDay`,
/// `bandMix`, and each campaign row's `verified`/`inReview` counts. This
/// class's [summary] is the one place that reconciles those two sentences of
/// the spec into one envelope.
class AnalyticsRepo {
  AnalyticsRepo(this._db);
  final Db _db;

  /// Aggregates everything the `/analytics/summary` envelope needs in five
  /// small, indexed queries, all scoped by [organizationId] and narrowed by
  /// [campaignId] when given. [from]/[to] are inclusive UTC calendar dates —
  /// the caller (the route) has already resolved defaults and validated
  /// `from <= to` before this is ever called, so this method trusts them.
  ///
  /// A [campaignId] outside [organizationId] is not an error here: every
  /// query below is scoped by `organization_id` (or, for the structural
  /// queries, joined through a campaign that is), so a foreign or
  /// non-existent id simply yields empty aggregates everywhere — consistent
  /// with the org-scoped list-read behavior elsewhere in this service (a
  /// cross-org id is indistinguishable from one that doesn't exist).
  Future<Map<String, Object?>> summary({
    required String organizationId,
    String? campaignId,
    required DateTime from,
    required DateTime to,
  }) async {
    final fromUtc = DateTime.utc(from.year, from.month, from.day);
    // The resolved inclusive `to` DATE, day-only — deliberately built from
    // [to]'s year/month/day fields directly rather than via `.toUtc()`:
    // [to] may arrive as a local-time DateTime (`DateTime.tryParse` on a
    // bare "yyyy-MM-dd" query param produces one), and `.toUtc()` on a local
    // DateTime shifts by the process's UTC offset — which could silently
    // roll the calendar date itself. Reading the fields directly is
    // timezone-inert.
    final toDateOnly = DateTime.utc(to.year, to.month, to.day);
    final toExclusive = toDateOnly.add(const Duration(days: 1));

    // Shared WHERE fragments, built as conditional string fragments (not a
    // bound `@camp::text IS NULL OR ...` clause) so a query that never
    // references `@camp` never has an unbound parameter passed to it —
    // mirrors VerificationRepo.queue's `filterClause` convention, for the
    // same reason: the postgres driver rejects a parameter the query text
    // doesn't mention.
    final campaignStructuralFilter = campaignId == null
        ? ''
        : 'AND c.id = @camp ';
    final campaignRegFilter = campaignId == null
        ? ''
        : 'AND r.campaign_id = @camp ';
    final campaignRangedFilter = campaignId == null
        ? ''
        : 'AND a.campaign_id = @camp ';
    final campaignDrillFilter = campaignId == null ? '' : 'AND c.id = @camp ';

    final structuralParams = {
      'org': organizationId,
      if (campaignId != null) 'camp': campaignId,
    };
    final rangedParams = {
      'org': organizationId,
      'from': fromUtc,
      'to': toExclusive,
      if (campaignId != null) 'camp': campaignId,
    };

    // q1: structural denominators — campaigns.target_audience and
    // registrations count, unranged (see the class doc above).
    final structuralRes = await _db.execute(
      'SELECT COALESCE(SUM(c.target_audience), 0) AS target, '
      '  (SELECT COUNT(*) FROM registrations r '
      '     JOIN campaigns c2 ON c2.id = r.campaign_id '
      '     WHERE c2.organization_id = @org $campaignRegFilter) '
      '    AS registered '
      'FROM campaigns c '
      'WHERE c.organization_id = @org $campaignStructuralFilter',
      params: structuralParams,
    );
    final structuralRow = row(structuralRes.single);
    final target = (structuralRow['target']! as num).toInt();
    final registered = (structuralRow['registered']! as num).toInt();

    // q2: attendance counts by status, ranged.
    final statusRes = await _db.execute(
      'SELECT a.status, COUNT(*) AS n FROM attendance a '
      'WHERE a.organization_id = @org '
      '  AND a.captured_at >= @from AND a.captured_at < @to '
      '  $campaignRangedFilter'
      'GROUP BY a.status',
      params: rangedParams,
    );
    final statusCounts = <String, int>{
      for (final r in statusRes)
        row(r)['status']! as String: (row(r)['n']! as num).toInt(),
    };
    final captured = statusCounts.values.fold<int>(0, (a, b) => a + b);
    final approved = statusCounts['APPROVED'] ?? 0;
    final inReview = statusCounts['CRM_REVIEW'] ?? 0;
    final rejected = statusCounts['REJECTED'] ?? 0;
    final returned = statusCounts['RETURNED'] ?? 0;

    // q3: APPROVED attendance grouped by captured_at's UTC calendar day.
    final perDayRes = await _db.execute(
      "SELECT date_trunc('day', a.captured_at AT TIME ZONE 'UTC') AS d, "
      '  COUNT(*) AS n '
      'FROM attendance a '
      "WHERE a.organization_id = @org AND a.status = 'APPROVED' "
      '  AND a.captured_at >= @from AND a.captured_at < @to '
      '  $campaignRangedFilter'
      'GROUP BY d ORDER BY d',
      params: rangedParams,
    );
    final verifiedPerDay = [
      for (final r in perDayRes)
        {
          'date': (row(r)['d']! as DateTime).toIso8601String().substring(0, 10),
          'count': (row(r)['n']! as num).toInt(),
        },
    ];

    // q4: attendance counts by machine_band, ranged, NULL bands skipped.
    final bandRes = await _db.execute(
      'SELECT a.machine_band, COUNT(*) AS n FROM attendance a '
      'WHERE a.organization_id = @org '
      '  AND a.captured_at >= @from AND a.captured_at < @to '
      '  AND a.machine_band IS NOT NULL '
      '  $campaignRangedFilter'
      'GROUP BY a.machine_band',
      params: rangedParams,
    );
    final bandCounts = <String, int>{
      for (final r in bandRes)
        row(r)['machine_band']! as String: (row(r)['n']! as num).toInt(),
    };
    final bandMix = {for (final key in _bandKeys) key: bandCounts[key] ?? 0};

    // q5: one row per campaign in scope, with ranged APPROVED/CRM_REVIEW
    // counts joined in (LEFT JOIN so a campaign with zero in-range
    // attendance still gets its row, with zero counts).
    final drillRes = await _db.execute(
      'SELECT c.id, c.name, c.status, c.target_audience, '
      "  COUNT(*) FILTER (WHERE a.status = 'APPROVED') AS verified, "
      "  COUNT(*) FILTER (WHERE a.status = 'CRM_REVIEW') AS in_review "
      'FROM campaigns c '
      'LEFT JOIN attendance a ON a.campaign_id = c.id '
      '  AND a.captured_at >= @from AND a.captured_at < @to '
      'WHERE c.organization_id = @org $campaignDrillFilter'
      'GROUP BY c.id, c.name, c.status, c.target_audience '
      'ORDER BY c.name',
      params: rangedParams,
    );
    final campaigns = [
      for (final r in drillRes)
        {
          'id': row(r)['id'],
          'name': row(r)['name'],
          'status': row(r)['status'],
          'target': (row(r)['target_audience']! as num).toInt(),
          'verified': (row(r)['verified']! as num).toInt(),
          'inReview': (row(r)['in_review']! as num).toInt(),
        },
    ];

    return {
      'funnel': {
        'target': target,
        'registered': registered,
        'captured': captured,
        'inReview': inReview,
        'approved': approved,
        'rejected': rejected,
        'returned': returned,
      },
      'verifiedPerDay': verifiedPerDay,
      'bandMix': bandMix,
      'campaigns': campaigns,
      'sample': {'totalAttendance': captured, 'small': captured < 30},
      'range': {'from': _dateOnly(fromUtc), 'to': _dateOnly(toDateOnly)},
      'generatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}

String _dateOnly(DateTime d) => d.toIso8601String().substring(0, 10);
