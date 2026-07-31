import 'package:flutter/material.dart';

import '../../app/theme/tokens.dart';

/// Banners and designed states.
///
/// The rule that shapes this whole file: an error explains the required
/// correction and preserves the user's work (§2.1, §9.4). A field user who
/// loses a capture to a network failure stops trusting the app; a campaign
/// admin who loses a half-built wizard rebuilds it in a spreadsheet.

enum BannerTone { info, warning, error, neutral }

/// An inline banner. Used for delayed data, degraded services, offline queues,
/// concurrent decisions and schedule conflicts — anywhere the page needs to say
/// something true about its own state before the user acts on it.
class BmdBanner extends StatelessWidget {
  const BmdBanner({
    required this.title,
    required this.tone,
    this.body,
    this.icon,
    this.action,
    super.key,
  });

  /// States the fact, not an apology. "Order data is 41 minutes behind".
  final String title;

  /// What it means for what the user is about to do, and what happens next.
  final String? body;

  final BannerTone tone;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final (fg, bg) = switch (tone) {
      BannerTone.info => (bmd.info, bmd.tintInfo),
      BannerTone.warning => (bmd.warning, bmd.tintWarning),
      BannerTone.error => (bmd.error, bmd.tintError),
      BannerTone.neutral => (bmd.textSecondary, bmd.tintNeutral),
    };
    final resolvedIcon = icon ??
        switch (tone) {
          BannerTone.info => Icons.info_outline,
          BannerTone.warning => Icons.warning_amber_outlined,
          BannerTone.error => Icons.error_outline,
          BannerTone.neutral => Icons.settings_outlined,
        };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: BmdSpace.s4,
          vertical: BmdSpace.s3,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(BmdRadius.field),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(resolvedIcon, size: 18, color: fg),
            const SizedBox(width: BmdSpace.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: bmd.textPrimary),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 2),
                    Text(body!, style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: BmdSpace.s3),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The persistent offline indicator for the field app (§3.2, §8.11).
///
/// Compact but always present: queue count, last successful sync, and a direct
/// route to the queue. It never suggests recapturing — capture success and
/// upload success are different facts, and this bar reports only the second.
class OfflineBar extends StatelessWidget {
  const OfflineBar({
    required this.pendingCount,
    required this.lastSyncLabel,
    this.onViewQueue,
    this.connected = false,
    super.key,
  });

  final int pendingCount;
  final String lastSyncLabel;
  final VoidCallback? onViewQueue;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final fg = connected ? bmd.info : bmd.warning;
    final bg = connected ? bmd.tintInfo : bmd.tintWarning;

    return Semantics(
      liveRegion: true,
      label: '$pendingCount captures waiting to upload. '
          'Last successful sync $lastSyncLabel.',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(
          horizontal: BmdSpace.s4,
          vertical: BmdSpace.s2,
        ),
        color: bg,
        child: Row(
          children: [
            Icon(
              connected ? Icons.sync : Icons.cloud_upload_outlined,
              size: 16,
              color: fg,
            ),
            const SizedBox(width: BmdSpace.s2),
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: fg,
                borderRadius: BorderRadius.circular(BmdRadius.pill),
              ),
              child: Text(
                '$pendingCount',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: BmdSpace.s2),
            Expanded(
              child: Text(
                'waiting · last sync $lastSyncLabel',
                style: theme.textTheme.labelMedium?.copyWith(color: fg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onViewQueue != null)
              TextButton(
                onPressed: onViewQueue,
                style: TextButton.styleFrom(
                  foregroundColor: fg,
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: BmdSpace.s2),
                ),
                child: const Text('View queue'),
              ),
          ],
        ),
      ),
    );
  }
}

/// A designed empty, error or permission-denied state.
///
/// Never a bare spinner and never "No results". Each state names the situation,
/// gives the number that puts it in context, and offers the single most likely
/// next action. A permission-denied state names the *rule*, not just the
/// refusal, so the user knows whether to escalate or ask a colleague.
class BmdState extends StatelessWidget {
  const BmdState({
    required this.title,
    required this.body,
    this.icon,
    this.tone = BmdStateTone.neutral,
    this.action,
    this.reference,
    super.key,
  });

  const BmdState.empty({
    required String title,
    required String body,
    IconData? icon,
    Widget? action,
    Key? key,
  }) : this(
          title: title,
          body: body,
          icon: icon ?? Icons.inbox_outlined,
          action: action,
          key: key,
        );

  const BmdState.error({
    required String title,
    required String body,
    Widget? action,
    String? reference,
    Key? key,
  }) : this(
          title: title,
          body: body,
          icon: Icons.error_outline,
          tone: BmdStateTone.error,
          action: action,
          reference: reference,
          key: key,
        );

  /// Names the rule that blocked the user, plus a reference that keeps the
  /// resulting support ticket short.
  const BmdState.denied({
    required String title,
    required String body,
    Widget? action,
    String? reference,
    Key? key,
  }) : this(
          title: title,
          body: body,
          icon: Icons.lock_outline,
          tone: BmdStateTone.denied,
          action: action,
          reference: reference,
          key: key,
        );

  final String title;
  final String body;
  final IconData? icon;
  final BmdStateTone tone;
  final Widget? action;
  final String? reference;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bmd = theme.bmd;
    final (fg, bg) = switch (tone) {
      BmdStateTone.error => (bmd.error, bmd.tintError),
      BmdStateTone.denied => (bmd.warning, bmd.tintWarning),
      BmdStateTone.neutral => (bmd.textFaint, bmd.tintNeutral),
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: BmdSpace.s6,
          vertical: BmdSpace.s9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(height: BmdSpace.s3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: BmdSpace.s2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: BmdSpace.s4),
              action!,
            ],
            if (reference != null) ...[
              const SizedBox(height: BmdSpace.s3),
              Text(reference!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

enum BmdStateTone { neutral, error, denied }

/// A skeleton shaped like the content it is standing in for, so the layout does
/// not jump when data lands. A bare spinner is acceptable only inside a button
/// that already carries the action's label.
class BmdSkeleton extends StatelessWidget {
  const BmdSkeleton({this.width, this.height = 12, super.key});

  const BmdSkeleton.block({Key? key}) : this(height: 72, key: key);

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).bmd.surfaceSunken,
        borderRadius: BorderRadius.circular(BmdRadius.chip),
      ),
    );
  }
}
