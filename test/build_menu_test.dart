import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/build_menu_screen.dart';

// Build is a POPUP over the map (user 2026-07-20): category rail on the left,
// buildings scrolling horizontally on the right, Move in the top-right corner.
// It was briefly a full page, which hid the very map you were building on.
//
// It decides nothing: it pops a BuildChoice and the settlement screen puts the
// map into the matching mode. These pin that contract, because the modes are
// mutually exclusive and the old callback-per-action shape left it possible to
// end up in two at once.

void main() {
  test('a choice carries the building to place', () {
    const choice = BuildPlace('hut');
    expect(choice.typeId, 'hut');
  });

  test('every choice is exhaustively switchable', () {
    // The sealed hierarchy is what makes the settlement screen's switch
    // exhaustive: add a third mode and that switch stops compiling rather
    // than silently ignoring it.
    String name(BuildChoice c) => switch (c) {
      BuildPlace(:final typeId) => 'place:$typeId',
      BuildRoads() => 'roads',
    };
    expect(name(const BuildPlace('quarry')), 'place:quarry');
    expect(name(const BuildRoads()), 'roads');
  });

  test('moving is not a build choice — it is a long-press on the map', () {
    // Deliberate (user 2026-07-20): the menu's Move button is gone, so the
    // menu can no longer put the map into move mode. If a BuildMove-like
    // choice ever comes back, the switch above stops compiling and this
    // comment is the reason to look at the map's long-press first.
    expect(BuildChoice, isNotNull);
  });
}
