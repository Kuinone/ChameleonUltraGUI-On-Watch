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
///   2. scale the layout to a comfortable reference size and scale the rendered
///      output back down so every existing widget keeps working as designed,
///   3. clip the result to a circle and replace the left sidebar navigation
///      with a round watch menu.
///
/// Only Android round/small-square screens trigger watch mode; all other
/// platforms and regular phones keep the original UI.

/// The logical (dp) reference shortest side the existing UI was designed for.
/// Watch content is laid out as if the screen were this large, then scaled
/// down to the real physical size.
const double kWatchDesignShortestSide = 400.0;

/// Returns `true` when the current screen looks like a round Android
/// smartwatch: a small, roughly square display.
bool isRoundWatchScreen(BuildContext context) {
  if (!Platform.isAndroid) {
    return false;
  }
  final size = MediaQuery.of(context).size;
  final shortest = size.shortestSide;
  final aspect = size.longestSide / size.shortestSide;
  // Small and near-square => round watch. Regular phones are much taller
  // (aspect well above 1.3) so they never match.
  return shortest <= 520 && aspect <= 1.35;
}

/// Scale factor that inflates the watch's logical size up to the reference
/// design size. Returns 1.0 (no scaling) on screens that are already large
/// enough, so we never make the UI larger than it was designed for.
double watchScaleFactor(Size real) {
  final shortest = real.shortestSide;
  if (shortest <= 0) {
    return 1.0;
  }
  return shortest >= kWatchDesignShortestSide
      ? 1.0
      : kWatchDesignShortestSide / shortest;
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