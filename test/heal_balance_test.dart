import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/models/species_balance.dart';
import 'package:boddygame/features/creatures/models/species_def.dart';
import 'package:boddygame/features/creatures/services/creatures_controller.dart';
import 'package:boddygame/features/creatures/services/healing_cost.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';

// Healing is dev-authored since 2026-07-26 (Species-Budget → 🩹 Heilung):
// treatment time and goods PER RARITY, plus one global K.O. factor. And the
// bill is paid in the goods of the MONSTER's era, not the settlement's.
//
// What matters is that every reader goes through the config — a constant left
// behind would let the screen and the game disagree.
SpeciesDef _species({
  required String id,
  required CreatureRarity rarity,
  int tier = 1,
}) => SpeciesDef(
  id: id,
  name: id,
  element: CreatureElement.fire,
  rarity: rarity,
  tier: tier,
  stats: const {},
  stages: const [],
);

CreatureInstance _monster({
  required int maxHp,
  required int hp,
  String species = 'common_t1',
}) {
  final c = CreatureInstance(
    id: 'c-$species-$hp',
    userId: 'u',
    speciesId: species,
    gender: CreatureGender.male,
    level: 1,
    statBase: {for (final s in CreatureStat.values) s: 10.0},
    statSlope: {for (final s in CreatureStat.values) s: 1.0},
  );
  c.statBase[CreatureStat.hp] = maxHp.toDouble();
  c.currentHp = hp;
  return c;
}

void main() {
  setUp(() {
    kSpeciesDefs
      ..clear()
      ..addAll({
        'common_t1': _species(id: 'common_t1', rarity: CreatureRarity.common),
        'rare_t1': _species(id: 'rare_t1', rarity: CreatureRarity.rare),
        // Same rarity as common_t1, but a region-3 native.
        'common_t3': _species(
          id: 'common_t3',
          rarity: CreatureRarity.common,
          tier: 3,
        ),
      });
  });
  tearDown(() {
    kSpeciesBalance = defaultSpeciesBalance();
    kHealBalance = const HealConfig();
    kSpeciesDefs.clear();
  });

  group('per-rarity durations (user 2026-07-26)', () {
    test('the defaults rise with rarity, seeded from the old flat 25', () {
      expect(healSecondsPerHp(CreatureRarity.common), 25);
      expect(
        healSecondsPerHp(CreatureRarity.legendary),
        greaterThan(healSecondsPerHp(CreatureRarity.common)),
      );
      for (var i = 1; i < CreatureRarity.values.length; i++) {
        expect(
          healSecondsPerHp(CreatureRarity.values[i]),
          greaterThanOrEqualTo(healSecondsPerHp(CreatureRarity.values[i - 1])),
          reason: 'rarer must never heal faster',
        );
      }
    });

    test('a rare really takes longer than a common with the same wound', () {
      final common = _monster(maxHp: 60, hp: 30, species: 'common_t1');
      final rare = _monster(maxHp: 60, hp: 30, species: 'rare_t1');
      expect(healDuration(common).inSeconds, 30 * 25);
      expect(healDuration(rare).inSeconds, 30 * 40);
    });

    test('an edited rate drives the real duration and bill', () {
      kSpeciesBalance = kSpeciesBalance.copyWith({
        CreatureRarity.common: kSpeciesBalance
            .of(CreatureRarity.common)
            .copyWith(healSecondsPerHp: 2, healGoodsPerHp: 1),
      });
      final hurt = _monster(maxHp: 60, hp: 30);
      expect(healDuration(hurt).inSeconds, 60);
      expect(healGoodsFor(hurt), closeTo(30, 1e-9));
    });

    test('the price rises with rarity too', () {
      // It was a flat 0.1/HP for everyone until 2026-07-29 — a legendary was
      // slow to heal but no dearer, so rarity cost only patience.
      expect(healGoodsPerHp(CreatureRarity.common), 0.2);
      for (var i = 1; i < CreatureRarity.values.length; i++) {
        expect(
          healGoodsPerHp(CreatureRarity.values[i]),
          greaterThan(healGoodsPerHp(CreatureRarity.values[i - 1])),
          reason: 'rarer must never be cheaper to treat',
        );
      }
    });
  });

  group('the K.O. factor stays global', () {
    test('it doubles BOTH prices, and 1.0 removes the penalty', () {
      final ko = _monster(maxHp: 60, hp: 0);
      expect(ko.isKo, isTrue);
      expect(healDuration(ko).inSeconds, 60 * 25 * 2);
      expect(healGoodsFor(ko), closeTo(60 * 0.2 * 2, 1e-9));

      kHealBalance = const HealConfig(koMultiplier: 1);
      expect(healDuration(ko).inSeconds, 60 * 25);
      expect(healGoodsFor(ko), closeTo(60 * 0.2, 1e-9));
    });

    test('it round-trips through JSON', () {
      expect(
        HealConfig.fromJson(const HealConfig(koMultiplier: 3).toJson())
            .koMultiplier,
        3,
      );
      expect(HealConfig.fromJson(const {}).koMultiplier, 2.0);
    });
  });

  group('the bill is paid in the MONSTER era\'s goods', () {
    // These are about WHICH goods pay, not about the price. Pin the rate at
    // the historical 0.1/HP so the sums in the comments below stay readable
    // and a retuned default can never turn an allocation bug into a passing
    // test (or the reverse).
    setUp(() {
      kSpeciesBalance = kSpeciesBalance.copyWith({
        for (final r in CreatureRarity.values)
          r: kSpeciesBalance.of(r).copyWith(healGoodsPerHp: 0.1),
      });
    });
    test('a region-1 monster can only be billed in era-1 supplies', () {
      final c = _monster(maxHp: 100, hp: 0, species: 'common_t1');
      expect(creatureHealEra(c), 1);
      final bill = healCost([c], {'fish': 999, 'honey': 999});
      // honey is era 2 — off limits for this monster however much you have.
      expect(bill.keys, everyElement(anyOf('fish', 'fur')));
    });

    test('a region-3 monster reaches for the later goods', () {
      final c = _monster(maxHp: 100, hp: 0, species: 'common_t3');
      expect(creatureHealEra(c), 3);
      final bill = healCost([c], {'fish': 1, 'wine': 999});
      expect(bill.containsKey('wine'), isTrue); // era 3 supply
    });

    test('the scarce early goods go to the monster that has no choice', () {
      // 20 fish is exactly what the era-1 monster needs; the era-3 one could
      // take fish too, so billing it first would strand the other.
      final early = _monster(maxHp: 100, hp: 80, species: 'common_t1'); // 2
      final late = _monster(maxHp: 100, hp: 0, species: 'common_t3'); // 20
      final bill = healCost([late, early], {'fish': 2, 'wine': 999});
      expect(bill['fish'], 2);
      expect(bill['wine'], greaterThan(0));
    });

    test('no double-spend: two eras cannot both claim the same fish', () {
      final a = _monster(maxHp: 100, hp: 0, species: 'common_t1'); // 20 goods
      final b = _monster(maxHp: 100, hp: 0, species: 'common_t3'); // 20 goods
      final bill = healCost([a, b], {'fish': 20, 'wine': 20});
      expect(bill['fish'], lessThanOrEqualTo(20));
      // The whole 40 is still charged, just spread over what exists.
      expect(bill.values.fold<double>(0, (s, v) => s + v), 40);
    });

    test('a healthy creature is free, and an empty list bills nothing', () {
      final fine = _monster(maxHp: 60, hp: 60);
      expect(healGoodsFor(fine), 0);
      expect(healDuration(fine), Duration.zero);
      expect(healCost([fine], {'fish': 10}), isEmpty);
      expect(healCost([], {'fish': 10}), isEmpty);
    });

    test('an unknown species heals as a common of era 1 — never unhealable', () {
      final orphan = _monster(maxHp: 60, hp: 30, species: 'no_such_species');
      expect(creatureHealEra(orphan), 1);
      expect(healDuration(orphan).inSeconds, 30 * 25);
    });
  });

  // ── The queue (user 2026-07-27, migration 0029) ─────────────────────────
  // "Treat all sollte nicht funktionieren, da ich aktuell keine Warteschlange
  // habe. Diese soll direkt eingebaut werden."
  //
  // The controller needs a database and a settlement to run a real heal, so
  // what is pinned here is the QUEUE ITSELF: the state that decides who is in
  // line, in what order, and that the two states are exclusive.
  group('the heal queue', () {
    test('queued and in-treatment are exclusive states', () {
      final c = _monster(maxHp: 100, hp: 20);
      expect(c.isQueuedForHealing, isFalse);

      c.healQueuedAt = DateTime.now();
      expect(c.isQueuedForHealing, isTrue,
          reason: 'in line, not yet in the hut');

      // Its slot comes up: the hut takes it OUT of the line.
      c.healingUntil = DateTime.now().add(const Duration(minutes: 5));
      c.healQueuedAt = null;
      expect(c.isQueuedForHealing, isFalse);
      expect(c.isHealing, isTrue);
    });

    test('a stale queue stamp never shows a monster in two places at once', () {
      // Belt and braces: the controller clears the stamp when treatment starts,
      // but a row written by an older build could carry both. The screen must
      // still list it once — under treatment, not in the line.
      final c = _monster(maxHp: 100, hp: 20)
        ..healQueuedAt = DateTime.now()
        ..healingUntil = DateTime.now().add(const Duration(minutes: 5));
      expect(c.isHealing, isTrue);
      expect(c.isQueuedForHealing, isFalse);
    });

    test('the queue survives a save — it is a column, not a session', () {
      final at = DateTime.now().subtract(const Duration(minutes: 3));
      final c = _monster(maxHp: 100, hp: 20)..healQueuedAt = at;
      final row = c.toRow();
      expect(row['heal_queued_at'], isNotNull);
      final back = CreatureInstance.fromRow({
        ...row,
        'stat_base': const <String, dynamic>{},
        'stat_slope': const <String, dynamic>{},
      });
      expect(back.isQueuedForHealing, isTrue);
      expect(
        back.healQueuedAt!.difference(at).inSeconds.abs(),
        lessThanOrEqualTo(1),
      );
    });

    test('a pre-0029 row is simply not queued', () {
      final back = CreatureInstance.fromRow({
        'id': 'x',
        'user_id': 'u',
        'species_id': 'common_t1',
        'gender': 'male',
        'stat_base': const <String, dynamic>{},
        'stat_slope': const <String, dynamic>{},
      });
      expect(back.healQueuedAt, isNull);
      expect(back.isQueuedForHealing, isFalse);
    });
  });

  // The waiting room is a building effect of its own (user 2026-07-27: "fuege
  // den effekt fuer die heal queu hinzu"), so the Healing Hut has to author it
  // and the two caps have to stay separate.
  group('the healQueue effect', () {
    final hut = kBuildingDefs['healing_hut']!;

    test('the Healing Hut authors both caps, and they are not the same one', () {
      expect(hut.hasEffect('healSlots', 1), isTrue);
      expect(hut.hasEffect('healQueue', 1), isTrue);
      // Both must GROW; their relative size is a pacing choice (the live
      // config starts the queue at 0 and opens it a level later).
      expect(hut.healQueueAt(24), greaterThan(hut.healQueueAt(1)));
    });

    test('both grow with the level, on their own ladders', () {
      // Two independent ladders, each rising — the numbers themselves are
      // tuned in Dev Mode and deliberately not pinned here.
      for (final at in [(1, 3), (3, 6), (6, 12)]) {
        expect(hut.healSlotsAt(at.$2), greaterThan(hut.healSlotsAt(at.$1)));
        expect(hut.healQueueAt(at.$2), greaterThan(hut.healQueueAt(at.$1)));
      }
    });

    test('it survives a DB round-trip', () {
      // The exact failure the effects test exists for: a type the parser does
      // not know is dropped silently on load, and only the bundled code def
      // keeps working.
      final def = BuildingDef.fromDefRow({
        'id': 'x',
        'name': 'X',
        'color': 'FF000000',
        'grid_w': 1,
        'grid_h': 1,
        'effects': [
          {'type': 'healQueue', 'value': 5.0, 'era': 1, 'levelSteps': {'2': 3}},
        ],
      });
      expect(def.healQueueAt(1), 5);
      expect(def.healQueueAt(2), 8);
    });
  });

  // A line longer than the room it stands in (user 2026-07-27: "in line 3/0
  // sollte nicht moeglich sein") is trimmed from the BACK, which only means
  // anything if the order is the one below.
  group('the line has an order, and the trim takes its tail', () {
    final ctrl = CreaturesController();
    tearDown(ctrl.creatures.clear);

    CreatureInstance queued(String id, {required int minutesAgo, int hp = 50}) {
      final c = CreatureInstance(
        id: id,
        userId: 'u',
        speciesId: 'common_t1',
        gender: CreatureGender.male,
        level: 1,
        statBase: {for (final s in CreatureStat.values) s: 10.0},
        statSlope: {for (final s in CreatureStat.values) s: 1.0},
        currentHp: hp,
      );
      c.healQueuedAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
      return c;
    }

    test('oldest first — waiting longer keeps your place', () {
      ctrl.creatures
        ..clear()
        ..addAll([
          queued('late', minutesAgo: 1),
          queued('first', minutesAgo: 9),
          queued('middle', minutesAgo: 5),
        ]);
      expect(ctrl.healQueue.map((c) => c.id), ['first', 'middle', 'late']);
      // Trimming to a cap of 2 therefore drops 'late', the newest joiner.
      expect(ctrl.healQueue.skip(2).map((c) => c.id), ['late']);
    });

    test('a tie breaks towards the one that needs it most', () {
      // "Treat all" stamps everybody in the same instant, so the tiebreak is
      // what actually orders that line.
      final at = DateTime.now().subtract(const Duration(minutes: 2));
      final scratched = queued('scratched', minutesAgo: 2, hp: 90);
      final mauled = queued('mauled', minutesAgo: 2, hp: 5);
      scratched.healQueuedAt = at;
      mauled.healQueuedAt = at;
      ctrl.creatures
        ..clear()
        ..addAll([scratched, mauled]);
      expect(ctrl.healQueue.first.id, 'mauled');
    });

    test('somebody under treatment is not in the line', () {
      final c = queued('treating', minutesAgo: 3)
        ..healingUntil = DateTime.now().add(const Duration(minutes: 5));
      ctrl.creatures
        ..clear()
        ..add(c);
      expect(ctrl.healQueue, isEmpty);
    });
  });
}
