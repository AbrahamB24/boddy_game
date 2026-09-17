import '../models/ability_def.dart';
import '../models/combatant.dart';
import '../models/creature_enums.dart';
import '../models/creature_instance.dart';

/// Serializes a [Combatant] to/from the plain JSON stored in
/// `pvp_matches.team_a`/`team_b` (supabase/migrations/0050_social_pvp.sql).
///
/// Each side snapshots ONLY its own team, into a row both players can already
/// read/write (see PvpService.createChallenge/acceptChallenge) — this is
/// deliberate: RLS on the `creatures` table is owner-only, so there is no
/// other way for the OPPONENT's device to learn what species/stats/abilities
/// your monsters have without you handing it over yourself, once, at
/// challenge time. A snapshot is frozen for the match: changes to your
/// collection afterwards (levelling, re-equipping) don't retroactively
/// change a match already in progress.
Map<String, dynamic> combatantSnapshot(Combatant c) => {
  'id': c.id,
  'instanceId': c.instanceId,
  'speciesId': c.speciesId,
  'gender': c.gender.name,
  'stage': c.stage,
  'name': c.name,
  'imageUrl': c.imageUrl,
  'backImageUrl': c.backImageUrl,
  'element': c.element.name,
  'rarity': c.rarity.name,
  'level': c.level,
  'stats': {for (final e in c.stats.entries) e.key.name: e.value},
  'abilityIds': [for (final a in c.abilities) a.id],
  'hp': c.hp,
};

/// The inverse of [combatantSnapshot]. [isPlayerSide] is supplied by the
/// caller rather than round-tripped through JSON: which side a snapshot
/// lands on depends on which local engine is building it (my team on
/// `players`, the opponent's on `enemies`), not on anything inherent to the
/// data itself — see battle_screen.dart's `isPvp` mode.
Combatant combatantFromSnapshot(
  Map<String, dynamic> json, {
  required bool isPlayerSide,
}) {
  final statsJson = (json['stats'] as Map).cast<String, dynamic>();
  return Combatant(
    id: json['id'] as String,
    instanceId: json['instanceId'] as String?,
    speciesId: json['speciesId'] as String?,
    gender: CreatureGender.values.byName(json['gender'] as String),
    stage: json['stage'] as int,
    name: json['name'] as String,
    imageUrl: json['imageUrl'] as String?,
    backImageUrl: json['backImageUrl'] as String?,
    element: CreatureElement.values.byName(json['element'] as String),
    rarity: CreatureRarity.values.byName(json['rarity'] as String),
    isPlayerSide: isPlayerSide,
    level: json['level'] as int,
    stats: {
      for (final e in statsJson.entries)
        CreatureStat.values.byName(e.key): (e.value as num).toInt(),
    },
    abilities: [
      for (final id in (json['abilityIds'] as List).cast<String>())
        if (kAbilityDefs[id] != null) kAbilityDefs[id]!,
    ],
    hp: (json['hp'] as num).toInt(),
  );
}

/// Snapshots the team the Lobby's [BattlePrepScreen] picker popped — my own
/// [CreatureInstance]s, so no cross-user RLS concern on this side at all
/// (only the OPPONENT's device needs a snapshot to reconstruct my
/// Combatants from; see [combatantSnapshot]'s own doc).
List<Map<String, dynamic>> snapshotTeam(List<CreatureInstance> team) => [
  for (final creature in team)
    combatantSnapshot(Combatant.fromInstance(creature, isPlayerSide: true)),
];
