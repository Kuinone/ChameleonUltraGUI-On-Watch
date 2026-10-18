import 'package:chameleonultragui/generated/i18n/app_localizations.dart';
import 'package:chameleonultragui/helpers/watch.dart';
import 'package:flutter/material.dart';

/// Builds the list of top-level navigation destinations for the round watch
/// menu, mirroring the entries of the desktop NavigationRail.
List<WatchDestination> buildWatchDestinations(
  BuildContext context, {
  required bool connected,
  required bool devMode,
}) {
  final l = AppLocalizations.of(context)!;
  return [
    WatchDestination(0, Icons.home, l.home),
    WatchDestination(1, Icons.widgets, l.slot_manager, disabled: !connected),
    WatchDestination(2, Icons.auto_awesome_motion, l.saved_cards),
    WatchDestination(3, Icons.sensors, l.read_card, disabled: !connected),
    WatchDestination(4, Icons.system_update_alt, l.write_card,
        disabled: !connected),
    WatchDestination(5, Icons.handyman, l.tools),
    WatchDestination(6, Icons.settings, l.settings),
    if (devMode) WatchDestination(7, Icons.bug_report, '🐞 ${l.debug} 🐞'),
  ];
}

/// Full-screen round navigation menu used on round smartwatch screens.
///
/// Replaces the left `NavigationRail`: a grid of circular action buttons that
/// fits the round display and lets the user jump between top-level pages.
class WatchNavigationMenu extends StatelessWidget {
  final int selectedIndex;
  final bool connected;
  final bool devMode;
  final void Function(int) onDestinationSelected;

  const WatchNavigationMenu({
    super.key,
    required this.selectedIndex,
    required this.connected,
    required this.devMode,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destinations = buildWatchDestinations(
      context,
      connected: connected,
      devMode: devMode,
    );

    return Material(
      color: scheme.surface,
      child: SafeArea(
        // The grid is inset so that every entry stays inside the round bezel,
        // and padded at the bottom so it never hides behind the menu button.
        child: GridView.count(
          padding: const EdgeInsets.fromLTRB(64, 48, 64, 92),
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: destinations.map((d) {
            final selected = d.index == selectedIndex;
            return InkWell(
              onTap: d.disabled
                  ? null
                  : () => onDestinationSelected(d.index),
              customBorder: const CircleBorder(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: selected
                        ? scheme.primary
                        : d.disabled
                            ? scheme.surfaceContainerHighest
                            : scheme.primaryContainer,
                    child: Icon(
                      d.icon,
                      size: 24,
                      color: selected
                          ? scheme.onPrimary
                          : d.disabled
                              ? scheme.outline
                              : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    d.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: d.disabled ? scheme.outline : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// Small circular button (bottom-centre) that toggles the watch menu.
class WatchMenuButton extends StatelessWidget {
  final bool menuOpen;
  final VoidCallback onPressed;

  const WatchMenuButton({
    super.key,
    required this.menuOpen,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      shape: const CircleBorder(),
      color: Theme.of(context).colorScheme.primaryContainer,
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(
            menuOpen ? Icons.close : Icons.grid_view_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            size: 26,
          ),
        ),
      ),
    );
  }
}