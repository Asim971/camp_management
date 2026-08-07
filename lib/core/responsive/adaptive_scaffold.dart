import 'package:flutter/material.dart';

import '../../app/shell/nav_destinations.dart';
import 'breakpoints.dart';

/// Adapts the app shell to the viewport (Guideline §3.1, §3.2, §11):
///  * desktop  → NavigationDrawer (248–264px)
///  * tablet   → NavigationRail
///  * mobile   → NavigationBar (≤4 items)
///
/// Pure responsive layout only - session-aware concerns (which destinations a
/// user may see, the account menu, the breadcrumb) live in [AppShell], which
/// wraps this. Content is constrained to a 1440px max working width.
class AdaptiveScaffold extends StatelessWidget {
  const AdaptiveScaffold({
    required this.title,
    required this.body,
    this.actions = const [],
    this.destinations = const [],
    this.selectedIndex,
    this.onDestinationSelected,
    this.leadingAction,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final List<NavDestinationSpec> destinations;

  /// Null when the current location belongs to no destination (a detail screen
  /// reached from elsewhere). Material requires a valid index when it renders
  /// a selection, so the nav is omitted entirely rather than guessing.
  final int? selectedIndex;

  final ValueChanged<int>? onDestinationSelected;

  /// A slot ahead of [actions], e.g. the account menu.
  final Widget? leadingAction;

  @override
  Widget build(BuildContext context) {
    final bp = Breakpoint.of(context);

    // A single destination is not navigation, and Material throws if asked to
    // render a selection with a null or out-of-range index.
    final showNav = destinations.length >= 2 && selectedIndex != null;

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
        bottomNavigationBar: !showNav
            ? null
            : NavigationBar(
                selectedIndex: selectedIndex!,
                onDestinationSelected: onDestinationSelected,
                destinations: [
                  for (final d in destinations)
                    NavigationDestination(icon: Icon(d.icon), label: d.label),
                ],
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: Row(
        children: [
          if (showNav) ...[
            NavigationRail(
              extended: bp.isDesktopUp,
              minExtendedWidth: 248,
              selectedIndex: selectedIndex!,
              onDestinationSelected: onDestinationSelected,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(child: content),
        ],
      ),
    );
  }
}
