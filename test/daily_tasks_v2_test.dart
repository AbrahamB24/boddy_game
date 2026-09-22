import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/item_definitions.dart';
import 'package:boddygame/features/settlement/services/daily_tasks.dart';

// Daily tasks v2 (user 2026-09-22): ten kinds, a chest for finishing all three,
// and a streak of chests on consecutive days.
void main() {
  group('the roll', () {
    test(
      'there are ten kinds, and every day still gets three distinct ones',
      () {
        expect(DailyTaskKind.values, hasLength(10));
        for (var d = 1; d <= 28; d++) {
          final s = rollDailyTasks(DateTime.utc(2026, 9, d));
          expect(
            s.tasks.map((t) => t.kind).toSet(),
            hasLength(3),
            reason: '$d',
          );
        }
      },
    );

    test('over a month the kinds vary widely', () {
      final seen = <DailyTaskKind>{};
      for (var d = 1; d <= 30; d++) {
        seen.addAll(
          rollDailyTasks(DateTime.utc(2026, 9, d)).tasks.map((t) => t.kind),
        );
      }
      expect(seen.length, greaterThanOrEqualTo(8));
    });

    test('a step goal is thousands of steps and pays gold', () {
      DailyTask? steps;
      for (var d = 1; d <= 90 && steps == null; d++) {
        for (final t in rollDailyTasks(
          DateTime.utc(2026, 1, 1).add(Duration(days: d)),
        ).tasks) {
          if (t.kind == DailyTaskKind.walkSteps) steps = t;
        }
      }
      expect(steps, isNotNull);
      expect(steps!.target, inInclusiveRange(2000, 4000));
      expect(steps.reward.keys, contains('gold'));
    });
  });

  group('the chest', () {
    test('it opens only when all three goals are claimed, once a day', () {
      final s = rollDailyTasks(DateTime.utc(2026, 9, 21));
      expect(s.chestReady, isFalse);
      for (final t in s.tasks) {
        t.progress = t.target;
      }
      expect(s.chestReady, isFalse, reason: 'done is not claimed');
      for (final t in s.tasks) {
        t.claimed = true;
      }
      expect(s.chestReady, isTrue);
      // The chest counts on the badge next to any unclaimed goal.
      expect(s.claimableCount, 1);
      s.lastChestKey = s.dateKey;
      expect(s.chestReady, isFalse);
      expect(s.chestOpened, isTrue);
    });

    test('day 7 is the big chest, then the week starts over', () {
      expect(chestForStreakDay(1).name, 'Chest');
      expect(chestForStreakDay(3).gold, greaterThan(chestForStreakDay(2).gold));
      expect(chestForStreakDay(5).gold, greaterThan(chestForStreakDay(3).gold));
      expect(chestForStreakDay(7).name, 'Big chest');
      expect(chestForStreakDay(7).gold, greaterThan(chestForStreakDay(5).gold));
      expect(chestForStreakDay(8).gold, chestForStreakDay(1).gold);
      expect(chestForStreakDay(14).gold, chestForStreakDay(7).gold);
    });

    test('every item in a chest exists in the game', () {
      for (var d = 1; d <= kStreakCycle; d++) {
        for (final id in chestForStreakDay(d).items.keys) {
          expect(kItemDefs.containsKey(id), isTrue, reason: 'day $d: $id');
        }
      }
    });
  });

  group('the streak', () {
    DailyTasksState opened(DateTime day, int streak) {
      final s = rollDailyTasks(day);
      s.streak = streak;
      s.lastChestKey = s.dateKey;
      return s;
    }

    test('it carries into the next day when the chest was opened', () {
      final day1 = opened(DateTime.utc(2026, 9, 21), 3);
      final day2 = rollDailyTasks(DateTime.utc(2026, 9, 22), carry: day1);
      expect(day2.streakOn(DateTime.utc(2026, 9, 22)), 3);
      expect(day2.nextChestDay(DateTime.utc(2026, 9, 22)), 4);
      expect(
        day2.tasks.every((t) => !t.claimed),
        isTrue,
        reason: 'fresh goals',
      );
    });

    test('a missed day breaks it: the next chest is day 1 again', () {
      final day1 = opened(DateTime.utc(2026, 9, 21), 5);
      final day3 = rollDailyTasks(DateTime.utc(2026, 9, 23), carry: day1);
      expect(day3.streakOn(DateTime.utc(2026, 9, 23)), 0);
      expect(day3.nextChestDay(DateTime.utc(2026, 9, 23)), 1);
    });

    test('it survives a save and a load, and old saves still load', () {
      final s = opened(DateTime.utc(2026, 9, 21), 4);
      final back = DailyTasksState.fromJson(s.toJson());
      expect(back.streak, 4);
      expect(back.lastChestKey, s.dateKey);
      // A save from before the streak existed has neither field.
      final old = DailyTasksState.fromJson({
        'date': '2026-07-21',
        'tasks': const [],
      });
      expect(old.streak, 0);
      expect(old.lastChestKey, '');
    });
  });
}
