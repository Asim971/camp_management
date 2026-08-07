import 'package:flutter/material.dart';

import '../../app/shell/app_shell.dart';

/// Temporary scaffold for feature modules that are structured but not yet
/// implemented. Keeps routing and navigation wired end-to-end during P0 so the
/// shell is demonstrable before every screen exists. Replace per the phase plan
/// in TASK_BREAKDOWN.md.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({
    required this.title,
    required this.screenId,
    this.prdRefs = const [],
    super.key,
  });

  final String title;
  final String screenId; // e.g. "C-02"
  final List<String> prdRefs;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '$screenId · not yet implemented',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (prdRefs.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                prdRefs.join(', '),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
