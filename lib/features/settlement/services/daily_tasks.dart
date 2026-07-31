import 'dart:math' as math;

// Daily tasks (user 2026-07-21): the loop had an era-sized goal (days) and a
// tick-sized one (seconds) and nothing in between — a session had no beginning
// and no end. Three rotating goals per day close that gap.
//
// Pure model + deterministic roll; persistence and progress hooks live on
// SettlementController. Rewards are deliberately modest (a nudge, not an
// income source that would bend the 40/60 split).

/// What a task counts. Every kind has a cheap, existing hook:
/// gather resolve, captureWild, battle victory, gather hauls.
enum DailyTaskKind {
  gatherTrips('Complete gather trips', '⛏'),
  catchMonsters('Catch monsters', '🪤'),
  winBattles('Win battles', '⚔️'),
  haulWood('Haul wood home from trips', '🪵');

  final String label;
  final String emoji;
  const DailyTaskKind(this.label, this.emoji);

  static DailyTaskKind fromName(String? name) => DailyTaskKind.values
      .firstWhere((k) => k.name == name, orElse: () => DailyTaskKind.gatherTrips);
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

class DailyTasksState {
  /// 'yyyy-mm-dd' of the day these tasks belong to (UTC — same clock the rest
  /// of the persistence uses). A new day rolls a fresh set.
  final String dateKey;
  final List<DailyTask> tasks;

  const DailyTasksState({required this.dateKey, required this.tasks});

  int get claimableCount => tasks.where((t) => t.claimable).length;

  Map<String, dynamic> toJson() => {
    'date': dateKey,
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };

  factory DailyTasksState.fromJson(Map<String, dynamic> j) => DailyTasksState(
    dateKey: j['date'] as String? ?? '',
    tasks: ((j['tasks'] as List?) ?? const [])
        .map((t) => DailyTask.fromJson((t as Map).cast<String, dynamic>()))
        .toList(),
  );
}

String dateKeyFor(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The per-kind target/reward menu the roll picks from. Small targets on
/// purpose: a task is a session's shape, not a grind.
({int target, Map<String, double> reward}) _spec(
  DailyTaskKind kind,
  math.Random rng,
) => switch (kind) {
  DailyTaskKind.gatherTrips => (
    target: 2,
    reward: {'gold': 15},
  ),
  DailyTaskKind.catchMonsters => (
    target: 1 + rng.nextInt(2), // 1–2
    reward: {'gold': 20},
  ),
  DailyTaskKind.winBattles => (
    target: 2 + rng.nextInt(2), // 2–3
    reward: {'wood': 120, 'stone': 80},
  ),
  DailyTaskKind.haulWood => (
    target: 200,
    reward: {'stone': 100},
  ),
};

/// Three distinct tasks for [day], deterministic — every device rolls the same
/// set for the same date, so an offline/online pair can't disagree.
DailyTasksState rollDailyTasks(DateTime day) {
  final key = dateKeyFor(day);
  final rng = math.Random(key.hashCode);
  final kinds = List<DailyTaskKind>.from(DailyTaskKind.values)..shuffle(rng);
  return DailyTasksState(
    dateKey: key,
    tasks: [
      for (final kind in kinds.take(3))
        () {
          final s = _spec(kind, rng);
          return DailyTask(kind: kind, target: s.target, reward: s.reward);
        }(),
    ],
  );
}
