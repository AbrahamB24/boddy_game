import 'creature_enums.dart';

/// The three lifecycle stages of a breeding_jobs row (user 2026-07-24). A job
/// walks breeding → egg → hatching → (hatched, row deleted).
enum BreedingStatus {
  /// Parents locked, incubating in the Breeding Hut. `readyAt` = when the egg
  /// is laid.
  breeding,

  /// Egg laid, parents freed, sitting idle in the BAG until the player drops
  /// it into a Hatchery slot. No live timer.
  ///
  /// From this point the egg is self-contained: the child's genes were rolled
  /// and frozen onto the row when it was laid (see [childBase]), so neither
  /// parent has to exist any more.
  egg,

  /// Placed in the Hatchery, incubating a second time. `readyAt` = hatch time.
  hatching;

  static BreedingStatus parse(String? s) => switch (s) {
    'egg' => BreedingStatus.egg,
    'hatching' => BreedingStatus.hatching,
    _ => BreedingStatus.breeding,
  };
}

// One breeding_jobs row across its whole lifecycle: two parents of the same
// species mate in the Breeding Hut (`breeding`), lay an egg that waits free
// (`egg`), then incubate in the Hatchery (`hatching`) before the child is
// rolled. `readyAt` is the deadline of the CURRENT timed stage (breeding or
// hatching) — an `egg` has no running timer. Both stages are time-based like
// ARK (decided design): the rarity base hours cut down by the stationed
// breeders' `breeding` stat in the relevant building.
class BreedingJob {
  final String id;
  final String userId;
  final String parentAId;
  final String parentBId;
  final String speciesId;
  final DateTime startedAt;
  final DateTime readyAt;
  final BreedingStatus status;

  /// The CHILD's genes, frozen when the egg was laid (user 2026-07-26).
  ///
  /// Empty on a `breeding` row (no egg yet) and on any egg laid before
  /// migration 0027 — [BreedingController.hatch] falls back to reading the
  /// parents for those, so nothing in flight is lost.
  ///
  /// Freezing is what makes an egg an ITEM rather than a promise about two
  /// other creatures: it survives the parents being released, evolved or
  /// re-levelled, and two eggs of the same species are genuinely different
  /// objects rather than two of a kind.
  final Map<CreatureStat, double> childBase;
  final Map<CreatureStat, double> childSlope;

  /// Whether this row already carries its child. False for a pre-0027 egg.
  bool get hasChildGenes => childBase.isNotEmpty;

  const BreedingJob({
    required this.id,
    required this.userId,
    required this.parentAId,
    required this.parentBId,
    required this.speciesId,
    required this.startedAt,
    required this.readyAt,
    this.status = BreedingStatus.breeding,
    this.childBase = const {},
    this.childSlope = const {},
  });

  /// True once the CURRENT timed stage has elapsed. Meaningless for [egg]
  /// (which has no timer) — callers gate on [status] first.
  bool get isReady => !DateTime.now().isBefore(readyAt);

  /// A finished mating whose egg is ready to collect: still flagged `breeding`
  /// but past its lay time (promoted to [egg] on the next sync).
  bool get isLaidEgg => status == BreedingStatus.egg ||
      (status == BreedingStatus.breeding && isReady);

  /// A `hatching` job whose incubation has finished — ready to hatch.
  bool get isHatchable => status == BreedingStatus.hatching && isReady;

  Duration get remaining {
    final d = readyAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  BreedingJob copyWith({
    BreedingStatus? status,
    DateTime? readyAt,
    Map<CreatureStat, double>? childBase,
    Map<CreatureStat, double>? childSlope,
  }) =>
      BreedingJob(
        id: id,
        userId: userId,
        parentAId: parentAId,
        parentBId: parentBId,
        speciesId: speciesId,
        startedAt: startedAt,
        readyAt: readyAt ?? this.readyAt,
        status: status ?? this.status,
        childBase: childBase ?? this.childBase,
        childSlope: childSlope ?? this.childSlope,
      );

  /// Reads a stat→value jsonb map, tolerating a missing column (pre-0027) and
  /// a stat that has since been retired.
  static Map<CreatureStat, double> genesFromJson(Object? json) {
    if (json is! Map) return const {};
    return {
      for (final stat in CreatureStat.values)
        if (stat.readJson(json) != null) stat: stat.readJson(json)!.toDouble(),
    };
  }

  /// The inverse — always the CURRENT stat names, so a row heals itself.
  static Map<String, double> genesToJson(Map<CreatureStat, double> genes) =>
      {for (final e in genes.entries) e.key.name: e.value};

  factory BreedingJob.fromRow(Map<String, dynamic> row) => BreedingJob(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    parentAId: row['parent_a'] as String,
    parentBId: row['parent_b'] as String,
    speciesId: row['species_id'] as String,
    startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
    readyAt: DateTime.parse(row['ready_at'] as String).toLocal(),
    status: BreedingStatus.parse(row['status'] as String?),
    childBase: genesFromJson(row['child_base']),
    childSlope: genesFromJson(row['child_slope']),
  );
}
