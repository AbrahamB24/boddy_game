import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/common/events/game_events.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/creatures/models/creature_instance.dart';
import 'package:boddygame/features/creatures/services/creature_power.dart';
import 'package:boddygame/features/creatures/services/stat_budget.dart';

CreatureInstance _mob(Map<CreatureStat, double> base) => CreatureInstance(
  id: 'c',
  userId: 'u',
  speciesId: 's',
  gender: CreatureGender.male,
  statBase: base,
  statSlope: const {},
);

void main() {
  group('power', () {
    test('total is combat + civil — the split IS the information', () {
      // A single number says how good; the split says what AT. That's the
      // whole point of the stat system (same budget, different distribution).
      final c = _mob({CreatureStat.hp: 60, CreatureStat.carry: 40});
      expect(totalPower(c), combatPower(c) + civilPower(c));
    });

    test('every stat lands on exactly one side', () {
      // If a stat were counted twice (or not at all), total would drift from
      // the budget targets and the numbers would stop meaning anything.
      final c = _mob({for (final s in CreatureStat.values) s: 7});
      final manual = CreatureStat.values.fold(0, (sum, s) => sum + c.statValue(s));
      expect(totalPower(c), manual);
    });

    test('the level-1 reading is the genes, not the levelling', () {
      // What the breeding screen leads with (user 2026-07-27): a parent passes
      // on its genes, so a levelled monster must not read as a better parent
      // than an identical unlevelled one.
      final genes = {for (final s in CreatureStat.values) s: 7.0};
      final fresh = CreatureInstance(
        id: 'a',
        userId: 'u',
        speciesId: 's',
        gender: CreatureGender.male,
        statBase: genes,
        statSlope: {for (final s in CreatureStat.values) s: 3},
      );
      final levelled = CreatureInstance(
        id: 'b',
        userId: 'u',
        speciesId: 's',
        gender: CreatureGender.male,
        level: 30,
        statBase: genes,
        statSlope: {for (final s in CreatureStat.values) s: 3},
      );
      expect(levelOnePower(levelled), levelOnePower(fresh));
      expect(totalPower(levelled), greaterThan(totalPower(fresh)));
      // At level 1 the two readings are the same number.
      expect(levelOnePower(fresh), totalPower(fresh));
    });

    test('a fighter and a worker are told apart by the split, not the total',
        () {
      final fighter = _mob({
        CreatureStat.hp: 90,
        CreatureStat.attack: 70,
        CreatureStat.defense: 60,
      });
      final worker = _mob({
        CreatureStat.carry: 90,
        CreatureStat.production: 70,
        CreatureStat.gathering: 60,
      });
      expect(combatPower(fighter), greaterThan(combatPower(worker)));
      expect(civilPower(worker), greaterThan(civilPower(fighter)));
      expect(combatShare(fighter), greaterThan(combatShare(worker)));
    });

    test('combatShare is bounded, and a blank creature reads as balanced', () {
      for (final c in [
        _mob({CreatureStat.hp: 200}),
        _mob({CreatureStat.carry: 200}),
        _mob(const {}),
      ]) {
        expect(combatShare(c), inInclusiveRange(0.0, 1.0));
      }
    });

    test('an on-budget common reads close to the framework targets', () {
      // Power is the raw stat sum by construction, so a card's number is
      // comparable to the budget a species was authored against. A weighted
      // "effectiveness" score would drift from stat_budget the moment either
      // side moved.
      final curves = buildArchetypeCurves(
        combat: CombatArchetype.allrounder,
        civil: CivilArchetype.generalist,
        rarity: CreatureRarity.common,
      );
      final c = CreatureInstance(
        id: 'c',
        userId: 'u',
        speciesId: 's',
        gender: CreatureGender.male,
        level: 1,
        statBase: {
          for (final e in curves.entries) e.key: e.value.baseAt(0),
        },
        statSlope: const {},
      );
      final b = defaultBudget(rarity: CreatureRarity.common);
      expect(combatPower(c), closeTo(b.combatBase, 8));
      expect(civilPower(c), closeTo(b.workBase, 8));
    });
  });

  group('topStats', () {
    test('ignores the free floor — not everyone is a generalist', () {
      // statValue defaults a MISSING stat to 10, so without the floor every
      // creature would list three "strengths" it does not have.
      final c = _mob({CreatureStat.carry: 44, CreatureStat.hp: 60});
      final top = topStats(c);
      expect(top, contains(CreatureStat.hp));
      expect(top, contains(CreatureStat.carry));
      expect(top.length, 2);
    });

    test('a creature with nothing above the floor claims nothing', () {
      expect(topStats(_mob(const {})), isEmpty);
    });

    test('ranks by value and is stable between equal stats', () {
      final c = _mob({CreatureStat.hp: 99, CreatureStat.attack: 50});
      expect(topStats(c, count: 1), [CreatureStat.hp]);
      expect(topStats(c), topStats(c));
    });
  });

  // The blanket passive XP floor was deleted on 2026-07-26 ("das braucht es
  // nicht") — a building pays XP only through its own `xp` effect now. What
  // survives is the Training Grounds' rate, and the bound that matters is the
  // same one the floor had: waiting must never beat fighting.
  group('training xp rate', () {
    test('is a slow path, not a shortcut past fighting', () {
      // If sitting in the Training Grounds ever became THE way to level, the
      // trial-level recommendations (docs/balancing.md §7) would stop meaning
      // anything, since you could out-wait every fight.
      expect(kTrainingXpPerHour, greaterThan(0));
      final hoursPerLevelAt20 = xpToNextLevel(20) / kTrainingXpPerHour;
      expect(hoursPerLevelAt20, greaterThan(4), reason: 'a level in minutes');
    });

    test('it slows down as a creature grows, never speeds up', () {
      expect(
        xpToNextLevel(10) / kTrainingXpPerHour,
        greaterThan(xpToNextLevel(5) / kTrainingXpPerHour),
      );
    });

    test('hoursToNextLevel is the honest version of the rate', () {
      // "+250 XP/h" is meaningless against a 6·L^2.5 curve without doing the
      // arithmetic — this is what the UI shows instead.
      expect(
        kXpBalance.hoursToNextLevel(5, kTrainingXpPerHour),
        xpToNextLevel(5) / kTrainingXpPerHour,
      );
      // A post that pays nothing must not advertise a finite wait.
      expect(kXpBalance.hoursToNextLevel(5, 0), double.infinity);
    });
  });

  group('battle xp', () {
    test('a defeated monster pays more the higher its level', () {
      expect(kXpBalance.killXp(20), greaterThan(kXpBalance.killXp(10)));
      expect(kXpBalance.killXp(10), greaterThan(kXpBalance.killXp(5)));
    });

    test('fighting overtakes training, but only past the early levels', () {
      // XP comes from fights — that was the point of deleting the passive
      // floor. With the 2026-07-29 curve (9 · L^1.3 against 250 XP/h of
      // training) that is no longer true at EVERY level: a same-level kill
      // at Lv 10 is worth ~180 and an hour of training 250, and the two
      // cross at about Lv 13. Pinned as a crossover rather than a blanket
      // 'fights always win', because the blanket claim is now false and a
      // test that asserts it would just be wrong about the game.
      expect(kXpBalance.killXp(10), lessThan(kTrainingXpPerHour));
      expect(kXpBalance.killXp(20), greaterThan(kTrainingXpPerHour));
    });

    test('a boss is worth a multiple of an ordinary kill', () {
      expect(
        kXpBalance.killXp(10, boss: true),
        greaterThan(kXpBalance.killXp(10)),
      );
    });
  });

  group('event log', () {
    setUp(GameEventLog().clear);

    test('newest first, and unread counts what you have not opened', () {
      final log = GameEventLog()
        ..add(GameEventKind.expedition, 'first')
        ..add(GameEventKind.levelUp, 'second');
      expect(log.events.first.message, 'second');
      expect(log.unread, 2);
      log.markAllRead();
      expect(log.unread, 0);
      expect(log.events, hasLength(2), reason: 'reading is not deleting');
    });

    test('addAll keeps order and counts every entry', () {
      final log = GameEventLog()
        ..addAll(GameEventKind.levelUp, ['a', 'b', 'c']);
      expect(log.events.map((e) => e.message), ['a', 'b', 'c']);
      expect(log.unread, 3);
    });

    test('addAll of nothing is a no-op — no phantom badge', () {
      final log = GameEventLog()..addAll(GameEventKind.levelUp, const []);
      expect(log.unread, 0);
      expect(log.events, isEmpty);
    });

    // The welcome-back digest and the bell report the SAME set (user
    // 2026-07-27: "alles was bei den notifications angezeigt wird, soll auch
    // beim while you were away screen sein"), so the log has to be able to say
    // WHICH events are new — not just how many.
    test('unreadEvents is exactly what the badge counts', () {
      final log = GameEventLog()
        ..add(GameEventKind.expedition, 'old')
        ..markAllRead();
      log.add(GameEventKind.levelUp, 'new');
      expect(log.unreadEvents.map((e) => e.message), ['new']);
      expect(log.unread, log.unreadEvents.length);
    });

    test('an unread event survives being read on a DIFFERENT screen', () {
      // The digest used to select by time window, so an event left unread in an
      // earlier session fell outside it and was never reported there — while
      // the bell went on counting it.
      final log = GameEventLog()
        ..add(
          GameEventKind.caught,
          'from yesterday',
          at: DateTime.now().subtract(const Duration(days: 1)),
        )
        ..add(GameEventKind.expedition, 'from tonight');
      expect(
        log.unreadEvents.map((e) => e.message),
        ['from tonight', 'from yesterday'],
        reason: 'age does not decide what is new — being read does',
      );
      log.markAllRead();
      expect(log.unreadEvents, isEmpty);
    });

    test('it is capped — a singleton feed must not grow forever', () {
      final log = GameEventLog();
      for (var i = 0; i < 200; i++) {
        log.add(GameEventKind.expedition, 'e$i');
      }
      expect(log.events.length, lessThanOrEqualTo(100));
      expect(log.events.first.message, 'e199', reason: 'newest survives');
    });
  });
}
