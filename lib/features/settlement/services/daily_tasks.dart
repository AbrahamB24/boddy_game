import 'dart:math' as math;

// Daily tasks (user 2026-07-21): the loop had an era-sized goal (days) and a
// tick-sized one (seconds) and nothing in between — a session had no beginning
// and no end. Three rotating goals per day close that gap.
//
// v2 (user 2026-09-22: "Daily Tasks noch zu langweilig, mehr Anreiz und
// Abwechslung"): TEN kinds instead of four, so the three of a day differ more
// from day to day; a DAILY CHEST for finishing all three; and a STREAK that
// climbs with the days in a row you open it, with bigger chests on days 3, 5 and
// 7 of every week of it.
//
// Pure model + deterministic roll; persistence and progress hooks live on
// SettlementController. The gold in these rewards matters more than it used to:
// since 2026-09-22 selling resources pays next to nothing (gold_economy.dart),
// so tasks are one of the few honest sources of it.

/// What a task counts. Every kind has an existing hook (see
/// SettlementController.reportDailyProgress and its callers).
enum DailyTaskKind {
  gatherTrips('Complete gather trips', '⛏'),
  catchMonsters('Catch monsters', '🪤'),
  winBattles('Win battles', '⚔️'),
  haulWood('Haul wood home from trips', '🪵'),
  walkSteps('Walk steps', '👟'),
  hatchEggs('Hatch eggs', '🥚'),
  healMonsters('Heal monsters', '🩹'),
  craftItems('Craft items', '⚒️'),
  finishBuildings('Finish buildings', '🏗'),
  levelUpMonsters('Level up monsters', '⬆️');

  final String label;
  final String emoji;
  const DailyTaskKind(this.label, this.emoji);

  static DailyTaskKind fromName(String? name) =>
      DailyTaskKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => DailyTaskKind.gatherTrips,
      );
}

class DailyTask {
  final DailyTaskKind kind;
  final int target;
  int progress;
  bool claimed;

  /// Resource key → amount granted on claim.
  final Map<String, double> reward;

  DailyTask({
    required this.kind,
    required this.target,
    this.progress = 0,
    this.claimed = false,
    required this.reward,
  });

  bool get done => progress >= target;
  bool get claimable => done && !claimed;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'target': target,
    'progress': progress,
    'claimed': claimed,
    'reward': reward,
  };

  factory DailyTask.fromJson(Map<String, dynamic> j) => DailyTask(
    kind: DailyTaskKind.fromName(j['kind'] as String?),
    target: (j['target'] as num?)?.toInt() ?? 1,
    progress: (j['progress'] as num?)?.toInt() ?? 0,
    claimed: j['claimed'] as bool? ?? false,
    reward: {
      for (final e in ((j['reward'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

/// What the daily chest holds: gold, and items for the bag (item id → count).
class DailyChest {
  final int gold;
  final Map<String, int> items;

  /// A word for the chest — "Small chest", "Big chest".
  final String name;

  const DailyChest({
    required this.gold,
    this.items = const {},
    required this.name,
  });
}

/// Days in one streak cycle: day 7 is the big chest, then it starts over at 1
/// (the streak itself keeps counting).
const int kStreakCycle = 7;

/// The chest for streak day [day] (1, 2, 3 …). It grows across a week of days in a
/// row: plain on days 1, 2, 4 and 6, richer on 3 and 5, big on 7 — and starts
/// over at day 1 of the next week, so a long streak never outgrows the loop.
DailyChest chestForStreakDay(int day) {
  final d = ((math.max(1, day) - 1) % kStreakCycle) + 1;
  return switch (d) {
    3 => const DailyChest(name: 'Good chest', gold: 40, items: {'potion': 2}),
    5 => const DailyChest(
      name: 'Good chest',
      gold: 60,
      items: {'catch_lure': 1, 'potion': 1},
    ),
    7 => const DailyChest(
      name: 'Big chest',
      gold: 150,
      items: {'revive_charm': 1, 'potion': 2, 'catch_lure': 2},
    ),
    _ => DailyChest(
      name: 'Chest',
      gold: 25,
      items: d.isEven ? const {'minor_potion': 2} : const {'minor_potion': 1},
    ),
  };
}

class DailyTasksState {
  /// 'yyyy-mm-dd' of the day these tasks belong to (UTC — same clock the rest
  /// of the persistence uses). A new day rolls a fresh set.
  final String dateKey;
  final List<DailyTask> tasks;

  /// Days in a row the chest was opened, as of [lastChestKey]. Only meaningful
  /// through [streakOn] — a streak that was not kept up is gone by then.
  int streak;

  /// The date the chest was last opened ('' = never).
  String lastChestKey;

  DailyTasksState({
    required this.dateKey,
    required this.tasks,
    this.streak = 0,
    this.lastChestKey = '',
  });

  int get claimableCount =>
      tasks.where((t) => t.claimable).length + (chestReady ? 1 : 0);

  /// Every task of today done AND its reward taken — the chest opens.
  bool get allClaimed => tasks.isNotEmpty && tasks.every((t) => t.claimed);

  bool get chestOpened => lastChestKey == dateKey;

  /// The chest is there to open: all three claimed, and not opened yet today.
  bool get chestReady => allClaimed && !chestOpened;

  /// The streak as it stands on [day]: what it is if you opened the chest today or
  /// yesterday, and gone (0) if a day was missed.
  int streakOn(DateTime day) {
    final today = dateKeyFor(day);
    final yesterday = dateKeyFor(day.subtract(const Duration(days: 1)));
    return lastChestKey == today || lastChestKey == yesterday ? streak : 0;
  }

  /// The streak day the chest opened NEXT would be — 1 if the streak is broken,
  /// else one more than it is. (Once today's chest is open, the next is tomorrow's.)
  int nextChestDay(DateTime day) => streakOn(day) + 1;

  Map<String, dynamic> toJson() => {
    'date': dateKey,
    'tasks': tasks.map((t) => t.toJson()).toList(),
    'streak': streak,
    'last_chest': lastChestKey,
  };

  factory DailyTasksState.fromJson(Map<String, dynamic> j) => DailyTasksState(
    dateKey: j['date'] as String? ?? '',
    tasks: ((j['tasks'] as List?) ?? const [])
        .map((t) => DailyTask.fromJson((t as Map).cast<String, dynamic>()))
        .toList(),
    streak: (j['streak'] as num?)?.toInt() ?? 0,
    lastChestKey: j['last_chest'] as String? ?? '',
  );
}

String dateKeyFor(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The per-kind target/reward menu the roll picks from. Small targets on
/// purpose: a task is a session's shape, not a grind. Rewards are gold for the
/// tasks that ask for something you have to go and DO (gold is earned, not sold),
/// and resources for the ones that are a by-product of playing anyway.
({int target, Map<String, double> reward}) _spec(
  DailyTaskKind kind,
  math.Random rng,
) => switch (kind) {
  DailyTaskKind.gatherTrips => (target: 2, reward: {'gold': 15}),
  DailyTaskKind.catchMonsters => (
    target: 1 + rng.nextInt(2), // 1–2
    reward: {'gold': 20},
  ),
  DailyTaskKind.winBattles => (
    target: 2 + rng.nextInt(2), // 2–3
    reward: {'wood': 120, 'stone': 80},
  ),
  DailyTaskKind.haulWood => (target: 200, reward: {'stone': 100}),
  DailyTaskKind.walkSteps => (
    target: 2000 + 1000 * rng.nextInt(3), // 2 000 – 4 000
    reward: {'gold': 25},
  ),
  DailyTaskKind.hatchEggs => (target: 1, reward: {'gold': 30}),
  DailyTaskKind.healMonsters => (
    target: 2 + rng.nextInt(2), // 2–3
    reward: {'gold': 12},
  ),
  DailyTaskKind.craftItems => (
    target: 2 + rng.nextInt(2), // 2–3
    reward: {'gold': 12},
  ),
  DailyTaskKind.finishBuildings => (target: 1, reward: {'gold': 20}),
  DailyTaskKind.levelUpMonsters => (
    target: 2 + rng.nextInt(3), // 2–4
    reward: {'gold': 15},
  ),
};

/// Three distinct tasks for [day], deterministic — every device rolls the same
/// set for the same date, so an offline/online pair can't disagree.
///
/// [carry] is the state the new day replaces: its streak and the date of its last
/// chest live on, the tasks do not.
///
/// [exclude] names kinds the player cannot make progress on yet (no Hatchery,
/// no Healing Hut, no workshop) — a task that can only fail used to cost the
/// whole day's chest AND the streak. The full list is still shuffled with the
/// same seed before filtering, so two devices with the same buildings agree.
DailyTasksState rollDailyTasks(
  DateTime day, {
  DailyTasksState? carry,
  Set<DailyTaskKind> exclude = const {},
}) {
  final key = dateKeyFor(day);
  final rng = math.Random(key.hashCode);
  final kinds = List<DailyTaskKind>.from(DailyTaskKind.values)..shuffle(rng);
  return DailyTasksState(
    dateKey: key,
    tasks: [
      for (final kind in kinds.where((k) => !exclude.contains(k)).take(3))
        () {
          final s = _spec(kind, rng);
          return DailyTask(kind: kind, target: s.target, reward: s.reward);
        }(),
    ],
    streak: carry?.streak ?? 0,
    lastChestKey: carry?.lastChestKey ?? '',
  );
}
