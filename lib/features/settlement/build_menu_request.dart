import 'package:flutter/widgets.dart';

import 'data/building_definitions.dart' show BuildingCategory;

/// Lets a page that is NOT the map ask the map to open its build menu.
///
/// The build menu is a bottom strip on the settlement screen (2026-09-18), not a
/// screen to push, so a page like Work — "Build a house" — cannot open it
/// itself. [open] closes every page back to the map and asks it to show the
/// strip, optionally on one [BuildingCategory] (Housing, for that button).
class BuildMenuRequest {
  BuildMenuRequest._();

  /// Ticks once per request; the settlement screen listens.
  static final ValueNotifier<int> requests = ValueNotifier(0);

  /// The category the last request asked for, or null for "wherever it was".
  static BuildingCategory? category;

  static void open(BuildContext context, {BuildingCategory? category}) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    BuildMenuRequest.category = category;
    requests.value++;
  }
}
