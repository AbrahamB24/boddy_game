import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/creature_instance.dart';
import '../data/building_definitions.dart';
import '../data/resource_icons.dart' show resourceEmoji;
import '../data/workshop_role_effects.dart';
import '../models/placed_building.dart';

/// The numbers behind the Work page (user 2026-09-19, "Variante 6"): for every
/// workshop, who sits at which post, what each of them is worth, and what the
/// building makes in total — with the SAME formulas the economy and the building
/// dialog use, so the page never promises a figure the game does not bank.
///
/// Pure: everything it needs comes in as arguments, so the rules can be tested
/// without a settlement.

/// One post's seat: a monster in it, or nobody.
class WorkSeat {
  final WorkshopRole role;
  final CreatureInstance? creature;

  /// What this one monster is worth here, as the building dialog words it
  /// ("+2.3/h 🪵", "−12 % 🩹", "+8 XP/h") — null for an empty seat, and the
  /// reason instead ([absence]) while the monster is away.
  final String? figure;

  /// "away on a trip", "knocked out" … the post is held but yields nothing.
  final String? absence;

  /// A comparable size of the seat's output (per hour for stockpile posts,
  /// points for construction, 0 for the rest) — only for sorting.
  final double score;

  const WorkSeat({
    required this.role,
    required this.creature,
    this.figure,
    this.absence,
    this.score = 0,
  });

  bool get isEmpty => creature == null;
}

/// One workshop building and its crew.
class WorkSite {
  final PlacedBuilding building;
  final BuildingDef def;
  final List<WorkSeat> seats;

  /// The building's total by resource (base production + everyone working, times
  /// today's energy), construction included as points.
  final Map<String, double> resources;

  /// Work XP per hour for trainees.
  final double xpPerHour;

  /// System posts' summed power (breeding, healing, trips …), by role key.
  final Map<String, double> system;

  const WorkSite({
    required this.building,
    required this.def,
    required this.seats,
    required this.resources,
    required this.xpPerHour,
    required this.system,
  });

  int get cap => seats.length;
  int get staffed => seats.where((s) => !s.isEmpty).length;
  int get empty => cap - staffed;
  bool get paused => building.isPaused;

  /// The building's total, worded — "+9.3/h 🪵", "+4 points 🔨", "−25 % 🩹".
  List<String> get totalParts => [
    for (final e in resources.entries)
      if (e.value > 0)
        e.key == WorkshopRole.kConstruction
            ? '+${e.value.toStringAsFixed(0)} points 🔨'
            : '+${e.value.toStringAsFixed(1)}/h ${resourceEmoji(e.key)}',
    if (xpPerHour > 0) '+${xpPerHour.toStringAsFixed(0)} XP/h 🏋️',
    for (final e in system.entries)
      if (e.value != 0)
        '${workshopRoleEffect(e.key, e.value)} ${workshopRoleEmoji(e.key)}',
  ];

  /// The size of what it makes, for sorting: stockpile output per hour.
  double get outputScore => resources.entries
      .where((e) => e.key != WorkshopRole.kConstruction)
      .fold(0.0, (sum, e) => sum + e.value);

  /// The post kinds it offers, for sorting by post: the first role's output.
  String get postKey =>
      def.workshops.isEmpty ? '' : def.workshops.first.resource;
}

/// Everything at once, for the header.
class WorkSummary {
  final int staffed;
  final int cap;
  final Map<String, double> resources;

  const WorkSummary({
    required this.staffed,
    required this.cap,
    required this.resources,
  });

  int get empty => cap - staffed;

  factory WorkSummary.of(Iterable<WorkSite> sites) {
    var staffed = 0;
    var cap = 0;
    final res = <String, double>{};
    for (final s in sites) {
      staffed += s.staffed;
      cap += s.cap;
      for (final e in s.resources.entries) {
        if (e.key == WorkshopRole.kConstruction) continue;
        res[e.key] = (res[e.key] ?? 0) + e.value;
      }
    }
    return WorkSummary(staffed: staffed, cap: cap, resources: res);
  }
}

/// What ONE monster is worth in [role] at building level [level] — the figure
/// and a sortable size. The building dialog's worker row, in one place.
({String? figure, double score}) seatFigure(
  BuildingDef def,
  WorkshopRole role,
  CreatureInstance c,
  int level,
) {
  final contribution = role.contribution(
    (s) => c.statValue(s).toDouble(),
    level,
  );
  final contrib = contribution[role.resource] ?? 0;
  if (role.resource == WorkshopRole.kLegendaryBoost) {
    final legendary = c.species?.rarity == CreatureRarity.legendary;
    return (
      figure: legendary
          ? '⭐ ×${(1 + role.mult).toStringAsFixed(1)}'
          : '⚠ not legendary',
      score: 0,
    );
  }
  if (role.resource == WorkshopRole.kTraining) {
    return (figure: '+${kTrainingXpPerHour.toStringAsFixed(0)} XP/h', score: 0);
  }
  if (role.resource == WorkshopRole.kConstruction) {
    return (figure: '+${contrib.toStringAsFixed(0)} points 🔨', score: contrib);
  }
  if (role.resource == WorkshopRole.kStorageRoom) {
    final keys = def.effectKeys('storage').toList();
    final room = keys.fold<double>(
      0,
      (sum, k) =>
          sum +
          role.storageRoomFor(k, c.statValue(role.stat).toDouble(), level),
    );
    return (figure: '+${room.round()} room', score: 0);
  }
  if (workshopRoleFeedsSystem(role.resource)) {
    return (
      figure: workshopPowerLabel(contribution, withGlyph: role.isCombined),
      score: 0,
    );
  }
  return (
    figure: '+${contrib.toStringAsFixed(1)}/h ${resourceEmoji(role.resource)}',
    score: contrib,
  );
}

/// Builds the sites for every complete, road-connected building that has posts.
///
/// [isWorking] is the economy's own predicate (posted AND able to be there);
/// [absenceOf] words why a posted monster is not (or null when it is).
List<WorkSite> buildWorkSites({
  required Iterable<PlacedBuilding> buildings,
  required Iterable<CreatureInstance> creatures,
  required Set<String> connectedIds,
  required bool Function(CreatureInstance) isWorking,
  required String? Function(CreatureInstance) absenceOf,
  required int era,
  required double energy,
  BuildingDef? Function(String typeId)? defOf,
}) {
  final lookup = defOf ?? (id) => kBuildingDefs[id];
  final sites = <WorkSite>[];
  for (final b in buildings) {
    if (!b.isComplete || !connectedIds.contains(b.id)) continue;
    final def = lookup(b.buildingTypeId);
    if (def == null || def.workshops.isEmpty) continue;

    final seats = <WorkSeat>[];
    final resources = <String, double>{};
    final system = <String, double>{};
    var trainees = 0;
    void add(String res, double v) =>
        resources[res] = (resources[res] ?? 0) + v;

    // What the building makes with nobody in it.
    for (final res in def.effectKeys('production')) {
      final v = def.effectAt('production', res, era, level: b.level);
      if (v != 0) add(res, v);
    }

    for (final role in def.workshops) {
      final posted = creatures
          .where(
            (c) => c.assignedBuildingId == b.id && c.assignedStat == role.stat,
          )
          .toList();
      final figures = {
        for (final c in posted) c: seatFigure(def, role, c, b.level),
      };
      // Highest producer first, the way the building dialog lists them.
      posted.sort((x, y) => figures[y]!.score.compareTo(figures[x]!.score));
      for (final c in posted) {
        final working = isWorking(c);
        seats.add(
          WorkSeat(
            role: role,
            creature: c,
            figure: figures[c]!.figure,
            absence: working ? null : absenceOf(c),
            score: working ? figures[c]!.score : 0,
          ),
        );
        if (!working) continue;
        final contribution = role.contribution(
          (s) => c.statValue(s).toDouble(),
          b.level,
        );
        if (role.resource == WorkshopRole.kTraining) {
          trainees++;
        } else if (role.resource == WorkshopRole.kLegendaryBoost ||
            role.resource == WorkshopRole.kStorageRoom) {
          // A multiplier and a ceiling: neither is an output line.
        } else if (workshopRoleFeedsSystem(role.resource)) {
          for (final e in contribution.entries) {
            system[e.key] = (system[e.key] ?? 0) + e.value;
          }
        } else {
          add(role.resource, contribution[role.resource] ?? 0);
        }
      }
      final cap = effectiveSlots(role, b.level);
      for (var i = posted.length; i < cap; i++) {
        seats.add(WorkSeat(role: role, creature: null));
      }
    }

    // Today's energy scales every rate, exactly as the building dialog's Total
    // and the header's own numbers do.
    if (energy != 1.0) {
      for (final k in resources.keys.toList()) {
        resources[k] = resources[k]! * energy;
      }
      for (final k in system.keys.toList()) {
        system[k] = system[k]! * energy;
      }
    }
    sites.add(
      WorkSite(
        building: b,
        def: def,
        seats: seats,
        resources: resources,
        xpPerHour: trainees * kTrainingXpPerHour * energy,
        system: system,
      ),
    );
  }
  return sites;
}

/// Complete workshops no road reaches — nobody can work there, so they are not
/// in the list; the page says so instead of letting them silently go missing.
List<({PlacedBuilding building, BuildingDef def})> disconnectedWorkshops({
  required Iterable<PlacedBuilding> buildings,
  required Set<String> connectedIds,
  BuildingDef? Function(String typeId)? defOf,
}) {
  final lookup = defOf ?? (id) => kBuildingDefs[id];
  return [
    for (final b in buildings)
      if (b.isComplete && !connectedIds.contains(b.id))
        if (lookup(b.buildingTypeId) case final def?)
          if (def.workshops.isNotEmpty) (building: b, def: def),
  ];
}

/// How the list can be ordered.
enum WorkSort {
  need('Need'),
  output('Output'),
  level('Level'),
  name('Name'),
  post('Post');

  final String label;
  const WorkSort(this.label);

  /// The order that reads as "first" for each field: most empty seats, biggest
  /// output, highest level, A–Z, by post kind.
  int compare(WorkSite a, WorkSite b) => switch (this) {
    WorkSort.need =>
      b.empty.compareTo(a.empty) != 0
          ? b.empty.compareTo(a.empty)
          : (a.staffed / a.cap).compareTo(b.staffed / b.cap),
    WorkSort.output => b.outputScore.compareTo(a.outputScore),
    WorkSort.level => b.building.level.compareTo(a.building.level),
    WorkSort.name => a.def.name.toLowerCase().compareTo(
      b.def.name.toLowerCase(),
    ),
    WorkSort.post =>
      a.postKey.compareTo(b.postKey) != 0
          ? a.postKey.compareTo(b.postKey)
          : a.def.name.compareTo(b.def.name),
  };
}

/// [sites] ordered by [sort]; [reversed] flips it. Ties fall back to the name so
/// the list never shuffles between rebuilds.
List<WorkSite> sortedSites(
  Iterable<WorkSite> sites,
  WorkSort sort, {
  bool reversed = false,
}) {
  final list = sites.toList()
    ..sort((a, b) {
      final c = sort.compare(a, b);
      return c != 0 ? c : a.def.name.compareTo(b.def.name);
    });
  return reversed ? list.reversed.toList() : list;
}

/// One planned placement of the "fill empty seats" button.
class PlannedSeat {
  final CreatureInstance creature;
  final PlacedBuilding building;
  final WorkshopRole role;
  final double value;

  const PlannedSeat(this.creature, this.building, this.role, this.value);
}

/// Which free monster should sit in which empty seat: the best pairing first,
/// then the next, until seats or monsters run out. "Best" is what the monster is
/// worth at that post; posts with no output of their own (training, storage)
/// come after the ones that make something, and the legendary-boost post only
/// takes a legendary.
List<PlannedSeat> planFill({
  required List<WorkSite> sites,
  required Iterable<CreatureInstance> free,
}) {
  final open = <(PlacedBuilding, BuildingDef, WorkshopRole), int>{};
  for (final s in sites) {
    for (final role in s.def.workshops) {
      final empty = s.seats.where((x) => x.isEmpty && x.role == role).length;
      if (empty > 0) open[(s.building, s.def, role)] = empty;
    }
  }
  final pool = [...free];
  final plan = <PlannedSeat>[];
  while (open.isNotEmpty && pool.isNotEmpty) {
    PlannedSeat? best;
    (PlacedBuilding, BuildingDef, WorkshopRole)? bestKey;
    for (final e in open.entries) {
      final (b, def, role) = e.key;
      for (final c in pool) {
        if (role.resource == WorkshopRole.kLegendaryBoost &&
            c.species?.rarity != CreatureRarity.legendary) {
          continue;
        }
        final fig = seatFigure(def, role, c, b.level);
        // A tiny bias so a post that makes something beats one that does not.
        final value = fig.score > 0
            ? fig.score + 1000
            : c.statValue(role.stat) / 1000;
        if (best == null || value > best.value) {
          best = PlannedSeat(c, b, role, value);
          bestKey = e.key;
        }
      }
    }
    if (best == null || bestKey == null) break;
    plan.add(best);
    pool.remove(best.creature);
    final left = open[bestKey]! - 1;
    if (left <= 0) {
      open.remove(bestKey);
    } else {
      open[bestKey] = left;
    }
  }
  return plan;
}
