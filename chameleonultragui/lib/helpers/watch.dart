import 'dart:io';

import 'package:flutter/material.dart';

/// Watch mode support for round Android smartwatch screens.
///
/// The rest of the app is designed for phones / desktops (roughly 360-400 dp
/// wide). A round watch reports a tiny logical size (e.g. 173-227 dp for a
/// 454 px @ 326 ppi display) and a roughly square aspect ratio. On such a
/// screen the existing phone UI would overflow badly, so we:
///
///   1. detect the round-watch form factor (small + near-square on Android),
///   2. lay *every* route (pages, dialogs, overlays) out against a virtual
///      reference viewport and scale the rendered output back down, so all
///      existing widgets keep working as designed and stay consistent with
///      each other,
///   3. clip the result to a circle and keep interactive chrome inside the
///      circular bezel, because the corners of a square screen simply do not
///      exist on a round display (they are neither visible nor tappable).
///
/// Only Android round/small-square screens trigger watch mode; all other
/// platforms and regular phones keep the original UI.

/// The logical (dp) reference shortest side the existing UI was designed for.
/// Watch content is laid out as if the screen were this large, then scaled
/// down to the real physical size.
const double kWatchDesignShortestSide = 400.0;

/// Fraction of the display that has to stay clear on every side so that a
/// centred rectangle still fits inside the round bezel.
///
/// A square inscribed in a circle of diameter `d` has a side of `d / sqrt(2)`,
/// so `(1 - 1 / sqrt(2)) / 2 ~= 14.6 %` of the diameter is lost on each side.
/// Rounding that up to 16 % leaves a little breathing room.
const double kWatchRoundInsetFactor = 0.16;

/// Safe inset, in watch design units, for content that has to stay completely
/// inside the round display (dialogs, snack bars, floating bars, ...).
const double kWatchRoundInset =
    kWatchDesignShortestSide * kWatchRoundInsetFactor;

/// Returns `true` when the current screen looks like a round Android
/// smartwatch: a small, roughly square display.
bool isRoundWatchScreen(BuildContext context) {
  if (!Platform.isAndroid) {
    return false;
  }

  return isRoundWatchSize(MediaQuery.of(context).size);
}

/// Size based variant of [isRoundWatchScreen].
bool isRoundWatchSize(Size size) {
  final shortest = size.shortestSide;
  if (shortest <= 0 || !shortest.isFinite) {
    return false;
  }

  final aspect = size.longestSide / shortest;
  // Small and near-square => round watch. Regular phones are much taller
  // (aspect well above 1.3) so they never match.
  return shortest <= 520 && aspect <= 1.35;
}

/// Scale factor that inflates the watch's logical size up to the reference
/// design size. Returns 1.0 (no scaling) on screens that are already large
/// enough, so we never make the UI larger than it was designed for.
double watchScaleFactor(Size real) {
  final shortest = real.shortestSide;
  if (shortest <= 0 || !shortest.isFinite) {
    return 1.0;
  }
  return shortest >= kWatchDesignShortestSide
      ? 1.0
      : kWatchDesignShortestSide / shortest;
}

/// The virtual viewport (in design units) a watch app is laid out against.
Size watchDesignSize(Size real) => real * watchScaleFactor(real);

/// Lays [child] out against the virtual watch design viewport and scales the
/// rendered result down to the physical round display.
///
/// [overlay] is painted on top of [child] *inside* the same scaled viewport,
/// so round-watch chrome keeps the same visual size as the rest of the UI.
///
/// The whole tree is clipped to a circle. Note that [ClipOval] also clips hit
/// testing, matching the physical display: anything in the corners of the
/// square viewport is unreachable, which is exactly what the round-screen
/// adaptations have to work around.
class WatchViewport extends StatelessWidget {
  const WatchViewport({super.key, required this.child, this.overlay});

  final Widget child;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final real = constraints.biggest;
        if (!real.isFinite || real.shortestSide <= 0) {
          return child;
        }

        final design = watchDesignSize(real);
        final scale = design.shortestSide / real.shortestSide;
        final media = MediaQuery.of(context);

        return ClipOval(
          child: Center(
            child: FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: design.width,
                height: design.height,
                child: MediaQuery(
                  // Scale the platform insets along with the viewport so that
                  // safe areas and the software keyboard line up with the
                  // scaled layout.
                  data: media.copyWith(
                    size: design,
                    padding: media.padding * scale,
                    viewPadding: media.viewPadding * scale,
                    viewInsets: media.viewInsets * scale,
                  ),
                  child: overlay == null
                      ? child
                      : Stack(
                          fit: StackFit.expand,
                          children: [child, overlay!],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Builds an `AppBar` whose titles and actions stay reachable on a round
/// display.
///
/// The top corners of the square watch viewport are outside the circular
/// bezel, so an `AppBar`'s leading widget and its actions can neither be seen
/// nor tapped there. On a watch the leading widget is dropped (the round watch
/// shell provides a floating back button instead) and the actions are moved
/// into a centred row directly below the title.
PreferredSizeWidget buildWatchAwareAppBar(
  BuildContext context, {
  required Widget title,
  List<Widget> actions = const <Widget>[],
  Widget? leading,
}) {
  if (!isRoundWatchScreen(context)) {
    return AppBar(
      title: title,
      actions: actions,
      leading: leading,
    );
  }

  return AppBar(
    title: title,
    automaticallyImplyLeading: false,
    bottom: actions.isEmpty
        ? null
        : PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: actions,
              ),
            ),
          ),
  );
}

/// Observes the app's navigator so the round watch shell can tell whether a
/// pushed page (rather than the root page or a dialog) is currently on screen.
class WatchRouteObserver extends NavigatorObserver {
  /// `true` while the top-most route is a pushed page route.
  final ValueNotifier<bool> canPop = ValueNotifier<bool>(false);

  final List<Route<dynamic>> _routes = <Route<dynamic>>[];

  void _sync() {
    final top = _routes.isEmpty ? null : _routes.last;
    // A popup route (dialog, menu, ...) on top brings its own actions, so we
    // hide the back affordance while one is open.
    final value = _routes.length > 1 && top is PageRoute;
    if (canPop.value != value) {
      canPop.value = value;
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute != null) {
        _routes[index] = newRoute;
      } else {
        _routes.removeAt(index);
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
    _sync();
  }
}

/// Round "back" affordance shown on top of pushed pages.
///
/// A pushed page's `AppBar` back button lives in the top-left corner of the
/// square viewport, which is outside the round display. This button sits on
/// the widest part of the circle instead, where it is always visible and
/// tappable.
class WatchBackButton extends StatelessWidget {
  const WatchBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      shape: const CircleBorder(),
      color: scheme.surfaceContainerHighest,
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.arrow_back, size: 24, color: scheme.onSurface),
        ),
      ),
    );
  }
}

/// A single entry in the round watch navigation menu.
class WatchDestination {
  final int index;
  final IconData icon;
  final String label;
  final bool disabled;

  const WatchDestination(
    this.index,
    this.icon,
    this.label, {
    this.disabled = false,
  });
}
