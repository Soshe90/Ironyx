import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/l10n_extension.dart';
import '../widgets/responsive.dart';

/// Persistent shell around the five branch navigators.
///
/// On wide layouts the bottom bar is replaced by a [NavigationRail], because
/// a full-width bottom bar on a 1440px window looks like a stretched phone.
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Built per-locale rather than held in a `const` list: the labels come
  /// from `AppLocalizations`, which needs a context.
  static List<_Destination> _destinationsFor(AppLocalizations l10n) =>
      <_Destination>[
        _Destination(l10n.navHome, Icons.home_outlined, Icons.home),
        _Destination(l10n.navTracker, Icons.list_alt_outlined, Icons.list_alt),
        _Destination(
          l10n.navLibrary,
          Icons.fitness_center_outlined,
          Icons.fitness_center,
        ),
        _Destination(l10n.navTimer, Icons.timer_outlined, Icons.timer),
        _Destination(
          l10n.navProgress,
          Icons.insights_outlined,
          Icons.insights,
        ),
      ];

  void _onDestinationSelected(int index) {
    // `initialLocation: true` when re-tapping the current tab pops that
    // branch back to its root — the expected behaviour on both platforms.
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool useRail = context.isAtLeast(Breakpoint.medium);
    final List<_Destination> destinations = _destinationsFor(context.l10n);

    if (useRail) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: _onDestinationSelected,
              labelType: NavigationRailLabelType.all,
              destinations: <NavigationRailDestination>[
                for (final _Destination d in destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selectedIcon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: navigationShell),
          ],
        ),
      );
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: <Widget>[
          for (final _Destination d in destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
              tooltip: d.label,
            ),
        ],
      ),
    );
  }
}

@immutable
class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}
