import 'package:flutter/material.dart';

import 'breakpoints.dart';

/// Adapts the app shell to the viewport (Guideline §3.1, §3.2, §11):
///  * desktop  → NavigationDrawer (248–264px)
///  * tablet   → NavigationRail
///  * mobile   → NavigationBar (≤4 items)
///
/// This is the P0 skeleton (Task T-0.3.5/T-0.4.4); destinations are wired to
/// the router. Content is constrained to a 1440px max working width.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.selectedIndex = 0,
    this.onDestinationSelected,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Dashboard'),
    (icon: Icons.campaign_outlined, label: 'Campaigns'),
    (icon: Icons.how_to_reg_outlined, label: 'Verification'),
    (icon: Icons.insights_outlined, label: 'Analytics'),
  ];

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);

    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ContentConstraints.maxWorkingWidth,
        ),
        child: Padding(
          padding: EdgeInsets.all(ContentConstraints.gutter(bp)),
          child: body,
        ),
      ),
    );

    if (bp.isMobile) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: content,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Row(
        children: [
          NavigationRail(
            extended: bp.isDesktopUp,
            minExtendedWidth: 248,
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: content),
        ],
      ),
    );
  }
}
