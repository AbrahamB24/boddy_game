import 'dart:math' as math;

/// One of the (up to five) legendaries of OTHER players speeding a lair up.
class LairTrainer {
  final String creatureId;
  final String userId;
  final int slot;
  final double effect;
  const LairTrainer({
    required this.creatureId,
    required this.userId,
    required this.slot,
    required this.effect,
  });

  factory LairTrainer.fromRow(Map<String, dynamic> r) => LairTrainer(
    creatureId: r['trainer_creature_id'] as String,
    userId: r['trainer_user_id'] as String,
    slot: (r['slot_order'] as num).toInt(),
    effect: (r['effect'] as num).toDouble(),
  );
}

/// The home of one legendary. Its [level] IS the monster's level.
///
/// The clock is "work": an upgrade needs [workTotal] seconds of work, and the
/// lair does [rate] seconds of it per real second (1 with nobody helping, more
/// with trainers). The server owns the numbers; this only reads them.
class LegendaryLair {
  final String id;
  final String userId;
  final String creatureId;
  final String speciesId;
  final int level;
  final bool upgrading;
  final double workTotal;
  final double workDone;
  final double rate;
  final DateTime lastUpdate;
  final String? paidGood;
  final double paidAmount;
  final double paidGold;
  final List<LairTrainer> trainers;

  const LegendaryLair({
    required this.id,
    required this.userId,
    required this.creatureId,
    required this.speciesId,
    required this.level,
    required this.upgrading,
    required this.workTotal,
    required this.workDone,
    required this.rate,
    required this.lastUpdate,
    this.paidGood,
    this.paidAmount = 0,
    this.paidGold = 0,
    this.trainers = const [],
  });

  factory LegendaryLair.fromRow(
    Map<String, dynamic> r, {
    List<LairTrainer> trainers = const [],
  }) => LegendaryLair(
    id: r['id'] as String,
    userId: r['user_id'] as String,
    creatureId: r['creature_id'] as String,
    speciesId: r['species_id'] as String,
    level: (r['level'] as num?)?.toInt() ?? 1,
    upgrading: r['upgrading'] as bool? ?? false,
    workTotal: (r['work_total'] as num?)?.toDouble() ?? 0,
    workDone: (r['work_done'] as num?)?.toDouble() ?? 0,
    rate: (r['rate'] as num?)?.toDouble() ?? 1,
    lastUpdate:
        DateTime.tryParse(r['last_update'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    paidGood: r['paid_good'] as String?,
    paidAmount: (r['paid_amount'] as num?)?.toDouble() ?? 0,
    paidGold: (r['paid_gold'] as num?)?.toDouble() ?? 0,
    trainers: trainers,
  );

  /// Work done as of right now (the server stamps [lastUpdate] at each change).
  double get doneNow => upgrading
      ? math.min(
          workTotal,
          workDone +
              DateTime.now().difference(lastUpdate).inMilliseconds /
                  1000 *
                  rate,
        )
      : 0;

  bool get isDone => upgrading && doneNow + 0.5 >= workTotal;

  double get progress => upgrading && workTotal > 0 ? doneNow / workTotal : 0;

  Duration get remaining => upgrading
      ? Duration(seconds: ((workTotal - doneNow) / math.max(rate, 1e-9)).ceil())
      : Duration.zero;

  int get freeSlots => 5 - trainers.length;
}

/// A row of the marketplace: somebody else's lair with room for a trainer.
class OpenLairSlot {
  final String lairId;
  final String ownerId;
  final String ownerName;
  final String speciesId;
  final int level;
  final int trainers;
  final double workTotal;
  final double workDone;
  final double rate;
  final DateTime lastUpdate;

  const OpenLairSlot({
    required this.lairId,
    required this.ownerId,
    required this.ownerName,
    required this.speciesId,
    required this.level,
    required this.trainers,
    required this.workTotal,
    required this.workDone,
    required this.rate,
    required this.lastUpdate,
  });

  factory OpenLairSlot.fromRow(Map<String, dynamic> r) => OpenLairSlot(
    lairId: r['lair_id'] as String,
    ownerId: r['owner_id'] as String,
    ownerName: (r['owner_name'] as String?) ?? '???',
    speciesId: r['species_id'] as String,
    level: (r['level'] as num).toInt(),
    trainers: (r['trainers'] as num).toInt(),
    workTotal: (r['work_total'] as num).toDouble(),
    workDone: (r['work_done'] as num).toDouble(),
    rate: (r['rate'] as num).toDouble(),
    lastUpdate: DateTime.parse(r['last_update'] as String).toLocal(),
  );

  Duration get remaining {
    final done = math.min(
      workTotal,
      workDone +
          DateTime.now().difference(lastUpdate).inMilliseconds / 1000 * rate,
    );
    return Duration(
      seconds: ((workTotal - done) / math.max(rate, 1e-9)).ceil(),
    );
  }

  /// The share of the reward the NEXT trainer would get (the 1st gets most).
  int get nextSlot => trainers + 1;
}
