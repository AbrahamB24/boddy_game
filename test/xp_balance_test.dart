import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';

// The XP config is dev-authored (Species-Budget → XP). Since 2026-07-26 it
// holds three things: the requirement curve, the Training-Grounds rate, and
// what a DEFEATED monster is worth at its level. The passive "every stationed
// monster earns a floor" rate and the per-era catch-up multiplier were deleted
// on request — the tests that pinned them are gone with them.
//
// What matters is that every reader goes through the config: a constant left
// behind would let the Dev-Mode screen and the game disagree.
CreatureInstance _monster() => CreatureInstance(
  id: 'c',
  userId: 'u',
  speciesId: 'emberfox',
  gender: CreatureGender.male,
  level: 1,
  statBase: {for (final s in CreatureStat.values) s: 20.0},
  statSlope: {for (final s in CreatureStat.values) s: 2.0},
);

void main() {
  tearDown(() => kXpBalance = const XpConfig());

  test('the default reproduces the historical curves', () {
    expect(xpToNextLevel(1), 6); // 6 · L^2.5
    expect(xpToNextLevel(10), (6 * 316.227766).round());
    expect(kTrainingXpPerHour, 250);
    // Kill XP: 9 · L^1.3, a boss ×3 (the author's config, taken over as the
    // default on 2026-07-29 — it was 9 · L^2.3 with a ×6 boss).
    expect(kXpBalance.killXp(1).round(), 9);
    expect(kXpBalance.killXp(10).round(), (9 * 19.9526231).round());
    expect(
      kXpBalance.killXp(10, boss: true),
      closeTo(kXpBalance.killXp(10) * 3, 1e-9),
    );
  });

  test('the config round-trips through JSON', () {
    const custom = XpConfig(
      curveFactor: 10,
      curveExponent: 2,
      trainingPerHour: 60,
      killFactor: 4,
      killExponent: 1.5,
      bossMultiplier: 3,
    );
    final back = XpConfig.fromJson(custom.toJson());
    expect(back.curveFactor, 10);
    expect(back.curveExponent, 2);
    expect(back.trainingPerHour, 60);
    expect(back.killFactor, 4);
    expect(back.killExponent, 1.5);
    expect(back.bossMultiplier, 3);
  });

  test('a partial row falls back to the defaults per field', () {
    final back = XpConfig.fromJson({'killFactor': 42.0});
    expect(back.killFactor, 42);
    expect(back.curveFactor, 6);
    expect(back.bossMultiplier, 3);
  });

  test('a row saved before the deletion ignores the dead keys', () {
    // passivePerHour / eraMultiplier no longer exist; an old row must still
    // parse rather than throw.
    final back = XpConfig.fromJson({
      'passivePerHour': 20.0,
      'eraMultiplier': 1.6,
      'trainingPerHour': 99.0,
    });
    expect(back.trainingPerHour, 99);
    expect(back.curveFactor, 6);
  });

  test('an edited curve drives xpToNextLevel and the level-ups', () {
    kXpBalance = const XpConfig(curveFactor: 10, curveExponent: 2);
    expect(xpToNextLevel(1), 10); // 10 · 1²
    expect(xpToNextLevel(3), 90); // 10 · 3²

    final c = _monster();
    // 10 (→ Lv2) + 40 (→ Lv3) = 50 exactly.
    expect(c.gainXp(50), 2);
    expect(c.level, 3);
    expect(c.xp, 0);
  });

  test('an edited kill reward changes what a defeat is worth', () {
    kXpBalance = const XpConfig(killFactor: 2, killExponent: 1);
    expect(kXpBalance.killXp(10), 20); // 2 × 10
    expect(kXpBalance.killXp(10, boss: true), 60); // ×3 default
    kXpBalance = const XpConfig(killFactor: 2, killExponent: 1, bossMultiplier: 1);
    expect(kXpBalance.killXp(10, boss: true), 20); // bosses made ordinary
  });

  test('kill XP rises with the enemy level and never underflows', () {
    expect(kXpBalance.killXp(20), greaterThan(kXpBalance.killXp(10)));
    // Level 0 / negative can't pay more than level 1 or go negative.
    expect(kXpBalance.killXp(0), kXpBalance.killXp(1));
  });

  test('an edited training rate drives the getter', () {
    kXpBalance = const XpConfig(trainingPerHour: 7);
    expect(kTrainingXpPerHour, 7);
  });

  test('a curve authored down to nothing cannot loop level-ups forever', () {
    // 0 XP per level would make `while (xp >= needed)` unbounded.
    kXpBalance = const XpConfig(curveFactor: 0);
    expect(xpToNextLevel(5), 1);
    final c = _monster();
    expect(c.gainXp(3), 3);
  });

  test('hoursToNextLevel makes a bare rate legible', () {
    const cfg = XpConfig();
    expect(cfg.hoursToNextLevel(1, 6), 1);
    expect(cfg.hoursToNextLevel(1, 0), double.infinity);
  });
}
