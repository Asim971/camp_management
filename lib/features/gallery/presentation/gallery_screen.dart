import 'package:flutter/material.dart';

import '../../../app/theme/tokens.dart';
import '../../../core/design_system/bmd_button.dart';
import '../../../core/design_system/bmd_cards.dart';
import '../../../core/design_system/bmd_data_table.dart';
import '../../../core/design_system/bmd_feedback.dart';
import '../../../core/design_system/bmd_field.dart';
import '../../../core/design_system/lineage_rail.dart';
import '../../../core/design_system/status_chip.dart';
import '../../../domain/common/status.dart';

/// Gallery-only container sizes. These are not design tokens — there is no
/// [BmdSize] slot for "gallery card width" — just named constants so a reader
/// sees intent instead of a bare literal repeated across demos.
const double _kCardWidth = 300;
const double _kTableHeight = 200;
const double _kStateHeight = 260;

/// Stable keys for each gallery section, so a golden baseline can target one
/// section instead of the whole page.
abstract final class GallerySection {
  static const buttons = 'gallery_buttons';
  static const fields = 'gallery_fields';
  static const status = 'gallery_status';
  static const cards = 'gallery_cards';
  static const feedback = 'gallery_feedback';
  static const table = 'gallery_table';
  static const lineage = 'gallery_lineage';

  static const all = [buttons, fields, status, cards, feedback, table, lineage];
}

/// The seven gallery sections, as data.
///
/// Kept as a function returning a list — rather than inlined into
/// [GalleryScreen.build] — so a golden test can pump one section at a time
/// without routing through the whole screen, and so the screen and any test
/// enumerating [GallerySection.all] can never disagree about which sections
/// exist.
List<GallerySectionView> gallerySections() => const [
  GallerySectionView(
    id: GallerySection.buttons,
    title: 'Buttons',
    child: _ButtonsDemo(),
  ),
  GallerySectionView(
    id: GallerySection.fields,
    title: 'Form controls',
    child: _FieldsDemo(),
  ),
  GallerySectionView(
    id: GallerySection.status,
    title: 'Status chips',
    child: _StatusDemo(),
  ),
  GallerySectionView(
    id: GallerySection.cards,
    title: 'Cards',
    child: _CardsDemo(),
  ),
  GallerySectionView(
    id: GallerySection.feedback,
    title: 'Banners and designed states',
    child: _FeedbackDemo(),
  ),
  GallerySectionView(
    id: GallerySection.table,
    title: 'Operational table',
    child: _TableDemo(),
  ),
  GallerySectionView(
    id: GallerySection.lineage,
    title: 'Lineage rail',
    child: _LineageDemo(),
  ),
];

/// A Bengali-copy sample for the §13.2 wrapping baseline. Bengali conjuncts
/// and matras wrap differently from Latin text, and the placeholder test font
/// cannot show it — this is only meaningful once real Bengali glyphs shape,
/// which `test/flutter_test_config.dart` loads for every test under `test/`.
class BengaliCopySample extends StatelessWidget {
  const BengaliCopySample({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BmdField(
          label: 'ক্যাম্পেইনের নাম',
          required: true,
          helper: 'অংশগ্রহণকারীদের আমন্ত্রণে এই নামটি দেখানো হবে।',
        ),
        SizedBox(height: BmdSpace.s4),
        BmdBanner(
          title: 'অর্ডারের তথ্য ৪১ মিনিট পিছিয়ে আছে',
          tone: BannerTone.warning,
          body:
              'নিচের অবদানের হিসাব থেকে শেষ ৪১ মিনিটের তথ্য বাদ '
              'দেওয়া হয়েছে।',
        ),
        SizedBox(height: BmdSpace.s4),
        StatusChip(label: 'যাচাই সম্পন্ন', tone: StatusTone.success),
      ],
    );
  }
}

/// The component gallery (T-0.2.9). Every variant and state of every design
/// system component, rendered at once.
///
/// This exists to be the golden fixture, so a change to a component is a
/// visible diff in a baseline rather than a surprise in a feature screen. It is
/// registered only when [AppConfig.devRoutesEnabled].
class GalleryScreen extends StatelessWidget {
  const GalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Component gallery')),
      body: ListView(
        padding: const EdgeInsets.all(BmdSpace.s4),
        children: gallerySections(),
      ),
    );
  }
}

/// One titled, keyed section. Public so the golden test can pump a section on
/// its own without routing through the whole page.
class GallerySectionView extends StatelessWidget {
  const GallerySectionView({
    required this.id,
    required this.title,
    required this.child,
    super.key,
  });

  final String id;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey(id),
      padding: const EdgeInsets.only(bottom: BmdSpace.s7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: BmdSpace.s4),
          child,
        ],
      ),
    );
  }
}

class _ButtonsDemo extends StatelessWidget {
  const _ButtonsDemo();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BmdSpace.s3,
      runSpacing: BmdSpace.s3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // One primary only — §5.1, asserted by expectSinglePrimaryAction.
        BmdButton(label: 'Submit for approval', onPressed: () {}),
        BmdButton(
          label: 'Save draft',
          variant: BmdButtonVariant.tonal,
          onPressed: () {},
        ),
        BmdButton(
          label: 'Cancel',
          variant: BmdButtonVariant.outlined,
          onPressed: () {},
        ),
        BmdButton(
          label: 'Learn more',
          variant: BmdButtonVariant.text,
          onPressed: () {},
        ),
        BmdButton(
          label: 'Cancel campaign',
          variant: BmdButtonVariant.danger,
          onPressed: () {},
        ),
        const BmdButton(
          label: 'Disabled',
          variant: BmdButtonVariant.tonal,
          onPressed: null,
        ),
        BmdButton(
          label: 'Loading',
          variant: BmdButtonVariant.tonal,
          loading: true,
          onPressed: () {},
        ),
        BmdButton(
          label: 'With icon',
          variant: BmdButtonVariant.tonal,
          icon: Icons.add,
          onPressed: () {},
        ),
        BmdIconButton(
          icon: Icons.filter_list,
          tooltip: 'Filter',
          onPressed: () {},
        ),
      ],
    );
  }
}

class _FieldsDemo extends StatelessWidget {
  const _FieldsDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BmdField(
          label: 'Campaign name',
          required: true,
          helper: 'Shown to participants in the invitation.',
        ),
        const SizedBox(height: BmdSpace.s4),
        const BmdField(
          label: 'Campaign code',
          errorText: 'A campaign with this code already exists',
        ),
        const SizedBox(height: BmdSpace.s4),
        const BmdField(label: 'Read-only', enabled: false),
        const SizedBox(height: BmdSpace.s4),
        const BmdField.multiline(
          label: 'Objective',
          helper: 'Recorded with the plan and shown to the approver.',
        ),
        const SizedBox(height: BmdSpace.s4),
        BmdField.masked(
          label: 'National ID',
          maskedValue: '•••••••••4821',
          helper: 'Revealing this is recorded against your name.',
          // A gallery is screenshotted and shared, so onReveal must never
          // stand in for a realistic national ID — it echoes back the same
          // masked string rather than "unmasking" to anything resembling
          // real personal data.
          onReveal: () async => '•••••••••4821',
        ),
        const SizedBox(height: BmdSpace.s4),
        const BmdField.masked(
          label: 'National ID (no permission)',
          maskedValue: '•••••••••4821',
        ),
        const SizedBox(height: BmdSpace.s4),
        BmdSearchField(
          scopeLabel: 'Searches name, carpenter ID and phone suffix',
          onQueryChanged: (_) {},
        ),
      ],
    );
  }
}

class _StatusDemo extends StatelessWidget {
  const _StatusDemo();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BmdSpace.s2,
      runSpacing: BmdSpace.s2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // The 28px variant, for use beside a page title (per its own doc
        // comment) — every other chip below is the 24px default.
        const StatusChip(label: 'active', tone: StatusTone.info, large: true),
        for (final s in CampaignStatus.values)
          StatusChip.campaign(s, label: s.name),
        for (final s in RegistrationStatus.values)
          StatusChip.registration(s, label: s.name),
        for (final s in AttendanceStatus.values)
          StatusChip.attendance(s, label: s.name),
        for (final s in ImportStatus.values)
          StatusChip.import(s, label: s.name),
        for (final f in IntegrityFlag.values)
          StatusChip.integrity(f, label: f.name),
      ],
    );
  }
}

class _CardsDemo extends StatelessWidget {
  const _CardsDemo();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: BmdSpace.s4,
      runSpacing: BmdSpace.s4,
      children: [
        const SizedBox(
          width: _kCardWidth,
          child: KpiCard(
            label: 'Verified attendance',
            value: '1,107',
            denominator: 'of 1,184 registered · 93.5%',
            definition: 'Distinct carpenters with a CRM-approved record.',
            source: 'verification facts',
            freshness: 'refreshed 09:42',
            delta: '+2.1pp',
            deltaDirection: KpiDelta.up,
            deltaContext: 'vs last week',
          ),
        ),
        const SizedBox(
          width: _kCardWidth,
          child: KpiCard(
            label: 'Median time to decision',
            value: '6.4h',
            definition: 'Median hours from capture to CRM verdict.',
            source: 'verification facts',
            freshness: 'refreshed 09:42',
            delta: '+1.2h',
            // A rising median time to decision is a down-toned fact even
            // though the number itself went up — direction of movement,
            // not "is this good", per KpiDelta's own doc comment.
            deltaDirection: KpiDelta.down,
            deltaContext: 'vs last week',
          ),
        ),
        const SizedBox(
          width: _kCardWidth,
          child: KpiCard(
            label: 'Active campaigns',
            value: '42',
            definition: 'Campaigns currently in the Active status.',
            source: 'campaign facts',
            freshness: 'refreshed 09:42',
            delta: '0',
            // Flat: no meaningful movement week over week — distinct from
            // omitting delta entirely, which reads as "not tracked".
            deltaContext: 'vs last week',
            footer: Text('Excludes paused and draft campaigns.'),
          ),
        ),
        SizedBox(
          width: _kCardWidth,
          child: ExceptionCard(
            label: 'Captures awaiting sync',
            count: '34',
            tone: ExceptionTone.warning,
            detail: '34 devices, oldest queued in Chattogram.',
            oldest: '2h 14m',
            agePressure: 0.62,
            actionLabel: 'Open queue',
            onAction: () {},
          ),
        ),
        const SizedBox(
          width: _kCardWidth,
          child: ExceptionCard(
            label: 'Rejected this week',
            count: '6',
            tone: ExceptionTone.error,
            detail: '6 unassigned, no action pending.',
          ),
        ),
        SizedBox(
          width: _kCardWidth,
          child: ExceptionCard(
            label: 'No-reference captures',
            count: '11',
            tone: ExceptionTone.info,
            detail: '11 devices · 3 sessions.',
            oldest: '41m',
            agePressure: 0.18,
            actionLabel: 'Review',
            onAction: () {},
          ),
        ),
      ],
    );
  }
}

class _FeedbackDemo extends StatelessWidget {
  const _FeedbackDemo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final tone in BannerTone.values) ...[
          BmdBanner(
            title: 'Order data is 41 minutes behind',
            tone: tone,
            body: 'Contribution figures below exclude the last 41 minutes.',
          ),
          const SizedBox(height: BmdSpace.s3),
        ],
        // The optional trailing action slot, on its own banner rather than
        // folded into the tone loop above — one instance is enough to show
        // the slot exists without implying every tone needs one.
        BmdBanner(
          title: 'A newer version of this campaign was just approved',
          tone: BannerTone.warning,
          body: 'Reload to see the latest plan before you continue editing.',
          action: BmdButton(
            label: 'Reload',
            variant: BmdButtonVariant.tonal,
            onPressed: () {},
          ),
        ),
        const SizedBox(height: BmdSpace.s3),
        const OfflineBar(pendingCount: 3, lastSyncLabel: '14m ago'),
        const SizedBox(height: BmdSpace.s2),
        // The connected state: a different icon and tone from the default
        // (disconnected/queued) bar above, plus the "View queue" action,
        // which only renders when onViewQueue is non-null.
        OfflineBar(
          pendingCount: 0,
          lastSyncLabel: 'just now',
          connected: true,
          onViewQueue: () {},
        ),
        const SizedBox(height: BmdSpace.s4),
        const SizedBox(
          height: _kStateHeight,
          child: BmdState.empty(
            title: 'No campaigns match these filters',
            body: 'Try widening the date range or clearing the region filter.',
          ),
        ),
        const SizedBox(height: BmdSpace.s4),
        const SizedBox(
          height: _kStateHeight,
          child: BmdState.error(
            title: 'Could not load the campaign list',
            body:
                'The request timed out. Check your connection and try '
                'again.',
            reference: 'Reference ERR-504',
          ),
        ),
        const SizedBox(height: BmdSpace.s4),
        const SizedBox(
          height: _kStateHeight,
          child: BmdState.denied(
            title: "You don't have access to campaign approval",
            body:
                'Approval is limited to the Campaign Approver role, and an '
                'approver cannot approve a campaign they created.',
            reference: 'Reference SEC-403',
          ),
        ),
        const SizedBox(height: BmdSpace.s4),
        const Row(
          children: [
            BmdSkeleton(width: 120),
            SizedBox(width: BmdSpace.s3),
            Expanded(child: BmdSkeleton.block()),
          ],
        ),
      ],
    );
  }
}

typedef _GalleryRow = ({String code, String name, String status, String age});

class _TableDemo extends StatelessWidget {
  const _TableDemo();

  static const _rows = <_GalleryRow>[
    (
      code: 'CMP-1042',
      name: 'Dhaka North roadshow',
      status: 'Active',
      age: '3d',
    ),
    (code: 'CMP-1043', name: 'Sylhet seminar', status: 'Draft', age: '11d'),
    (
      code: 'CMP-1044',
      name: 'Chattogram workshop',
      status: 'Pending approval',
      age: '1d',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kTableHeight,
      child: BmdDataTable<_GalleryRow>(
        rows: _rows,
        rowId: (r) => r.code,
        rowDetailTitle: (r) => r.name,
        // Required whenever a column can be dropped for width (Guideline
        // §5.5) — the narrow golden baseline is expected to drop columns,
        // and this is how that data stays reachable rather than tripping
        // the widget's own assert.
        rowDetailBuilder: (r) => Text('${r.code} · ${r.status} · ${r.age}'),
        columns: [
          BmdColumn(
            id: 'code',
            label: 'Code',
            priority: BmdColumnPriority.identity,
            minWidth: 120,
            flex: 0,
            cell: (r) => Text(r.code),
          ),
          BmdColumn(
            id: 'name',
            label: 'Campaign',
            priority: BmdColumnPriority.primary,
            minWidth: 200,
            flex: 3,
            cell: (r) => Text(r.name),
          ),
          BmdColumn(
            id: 'status',
            label: 'Status',
            minWidth: 160,
            cell: (r) => Text(r.status),
          ),
          BmdColumn(
            id: 'age',
            label: 'Age',
            minWidth: 100,
            numeric: true,
            cell: (r) => Text(r.age),
          ),
        ],
      ),
    );
  }
}

class _LineageDemo extends StatelessWidget {
  const _LineageDemo();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The happy path: done, current (dashed, in progress) and pending
        // (dashed, not yet started) — the future-versus-failed distinction
        // the component exists to make.
        LineageRail(
          nodes: [
            LineageNode(
              label: 'Captured',
              state: LineageState.done,
              meta: '10:24',
            ),
            LineageNode(
              label: 'Queued',
              state: LineageState.current,
              meta: 'waiting for network',
            ),
            LineageNode(label: 'Uploaded', state: LineageState.pending),
            LineageNode(label: 'CRM decision', state: LineageState.pending),
            LineageNode(label: 'Counted', state: LineageState.pending),
          ],
        ),
        SizedBox(height: BmdSpace.s6),
        // The two remaining states: a recoverable failure and a blocked
        // step that needs a different route entirely.
        LineageRail(
          nodes: [
            LineageNode(
              label: 'Captured',
              state: LineageState.done,
              meta: '09:02',
            ),
            LineageNode(
              label: 'Uploaded',
              state: LineageState.failed,
              meta: 'retry 2 of 3',
            ),
            LineageNode(
              label: 'CRM decision',
              state: LineageState.blocked,
              meta: 'needs manual review',
            ),
            LineageNode(label: 'Counted', state: LineageState.pending),
          ],
        ),
        SizedBox(height: BmdSpace.s6),
        // Same semantics in the vertical orientation used on narrow surfaces.
        LineageRail.vertical(
          nodes: [
            LineageNode(
              label: 'Captured',
              state: LineageState.done,
              meta: '10:24',
            ),
            LineageNode(
              label: 'Queued',
              state: LineageState.current,
              meta: 'waiting for network',
            ),
            LineageNode(label: 'Uploaded', state: LineageState.pending),
          ],
        ),
      ],
    );
  }
}
