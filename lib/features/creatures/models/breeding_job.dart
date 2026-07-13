// One running mating job (a row in breeding_jobs): two parents of the same
// species, blocked from battles until the egg hatches or the job is
// cancelled. `readyAt` passing turns the countdown into a hatchable egg —
// time-based like ARK (decided design), computed from the species' rarity
// (CreatureRarity.breedHours) at start time.
class BreedingJob {
  final String id;
  final String userId;
  final String parentAId;
  final String parentBId;
  final String speciesId;
  final DateTime startedAt;
  final DateTime readyAt;

  const BreedingJob({
    required this.id,
    required this.userId,
    required this.parentAId,
    required this.parentBId,
    required this.speciesId,
    required this.startedAt,
    required this.readyAt,
  });

  bool get isReady => !DateTime.now().isBefore(readyAt);

  Duration get remaining {
    final d = readyAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  factory BreedingJob.fromRow(Map<String, dynamic> row) => BreedingJob(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    parentAId: row['parent_a'] as String,
    parentBId: row['parent_b'] as String,
    speciesId: row['species_id'] as String,
    startedAt: DateTime.parse(row['started_at'] as String).toLocal(),
    readyAt: DateTime.parse(row['ready_at'] as String).toLocal(),
  );
}
