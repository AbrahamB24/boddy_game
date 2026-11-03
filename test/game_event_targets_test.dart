import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/common/events/game_events.dart';
import 'package:boddygame/features/common/events/notification_button.dart';

// A feed entry is a door (user 2026-09-28): it remembers WHAT it is about, and
// only offers to open something that is still there.
void main() {
  test('the reference survives the round trip through storage', () {
    final e = GameEvent(
      kind: GameEventKind.building,
      message: 'Hut is finished',
      at: DateTime(2026, 9, 28),
      ref: 'b1',
    );
    expect(GameEvent.fromJson(e.toJson())!.ref, 'b1');
  });

  test('an event stored before references existed still loads', () {
    final old = {'k': 'levelUp', 'm': 'x', 'a': 1, 'r': true};
    final e = GameEvent.fromJson(old)!;
    expect(e.ref, isNull);
  });

  test('a finished building that is gone (or unknown) opens nothing', () {
    final e = GameEvent(
      kind: GameEventKind.building,
      message: 'Hut is finished',
      at: DateTime(2026, 9, 28),
      ref: 'no-such-building',
    );
    expect(gameEventHasDestination(e), isFalse);
    // …and neither does one with no reference at all.
    expect(
      gameEventHasDestination(
        GameEvent(kind: GameEventKind.building, message: 'm', at: DateTime(1)),
      ),
      isFalse,
    );
  });

  test('kinds with their own screen keep it; research has none', () {
    bool goes(GameEventKind k) => gameEventHasDestination(
      GameEvent(kind: k, message: 'm', at: DateTime(1)),
    );
    expect(goes(GameEventKind.expedition), isTrue);
    expect(goes(GameEventKind.breeding), isTrue);
    expect(goes(GameEventKind.craft), isTrue);
    expect(goes(GameEventKind.levelUp), isTrue);
    expect(goes(GameEventKind.research), isFalse);
  });
}
