import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/supabase/supabase_client.dart';
import '../creatures/battle_prep_screen.dart';
import '../creatures/battle_screen.dart';
import '../creatures/models/combatant.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/models/species_def.dart';
import '../creatures/services/overworld_path.dart' show kMaxPartySize;
import '../settlement/settlement_controller.dart';
import 'guild_crest.dart';
import 'guild_service.dart';

/// The weekly guild boss (migration 0074): one health bar for the whole guild,
/// every member's damage counts. A fight is an ordinary battle against a strong
/// monster; the damage is the share of ITS health taken, as 0..100 points.
const int kBossAttemptsPerDay = 3;

/// How much stronger than a wild boss the guild boss is — the tuning dial for
/// how long a team lasts against it.
const double kGuildBossStatScale = 1.6;

class GuildBossState {
  final String speciesId;
  final int level;
  final int maxHp;
  final int damage;
  final bool defeated;
  final int myDamage;
  final int attemptsLeft;
  final DateTime endsAt;

  const GuildBossState({
    required this.speciesId,
    required this.level,
    required this.maxHp,
    required this.damage,
    required this.defeated,
    required this.myDamage,
    required this.attemptsLeft,
    required this.endsAt,
  });

  double get fraction => maxHp <= 0 ? 0 : (damage / maxHp).clamp(0.0, 1.0);
  String get name => kSpeciesDefs[speciesId]?.name ?? speciesId;
}

class BossDamageRow {
  final String name;
  final int damage;
  const BossDamageRow(this.name, this.damage);
}

class RankedGuild {
  final int rank;
  final String id;
  final String name;
  final GuildCrest crest;
  final int level;
  final int points;
  final int members;

  const RankedGuild({
    required this.rank,
    required this.id,
    required this.name,
    required this.crest,
    required this.level,
    required this.points,
    required this.members,
  });
}

class GuildBoss {
  GuildBoss._();

  /// The week's species and level, the same on every device: the species walks
  /// round the roster by the week number, the level follows the guild level.
  static ({String species, int level}) pick(int guildLevel, {DateTime? now}) {
    final pool =
        kSpeciesDefs.values
            .where((s) => s.rarity != CreatureRarity.legendary)
            .map((s) => s.id)
            .toList()
          ..sort();
    final d = (now ?? DateTime.now()).toUtc();
    final week = d.difference(DateTime.utc(2024, 1, 1)).inDays ~/ 7;
    return (
      species: pool.isEmpty ? 'unknown' : pool[week % pool.length],
      level: 8 + 4 * guildLevel.clamp(1, 10),
    );
  }

  static Future<GuildBossState?> current() async {
    try {
      final p = pick(GuildMembership.instance.level);
      final rows =
          await supabase.rpc(
                'guild_boss_current',
                params: {'p_species': p.species, 'p_level': p.level},
              )
              as List;
      if (rows.isEmpty) return null;
      final r = (rows.first as Map).cast<String, dynamic>();
      return GuildBossState(
        speciesId: r['species_id'] as String,
        level: (r['level'] as num).toInt(),
        maxHp: (r['max_hp'] as num).toInt(),
        damage: (r['damage'] as num).toInt(),
        defeated: r['defeated'] as bool,
        myDamage: (r['my_damage'] as num).toInt(),
        attemptsLeft: (r['attempts_left'] as num).toInt(),
        endsAt: DateTime.parse(r['ends_at'] as String).toLocal(),
      );
    } catch (e) {
      debugPrint('[GuildBoss] load failed: $e');
      return null;
    }
  }

  static Future<List<BossDamageRow>> board() async {
    try {
      final rows = await supabase.rpc('guild_boss_board') as List;
      return [
        for (final r in rows.cast<Map<String, dynamic>>())
          BossDamageRow(r['name'] as String, (r['damage'] as num).toInt()),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<List<RankedGuild>> ranking() async {
    try {
      final rows = await supabase.rpc('guild_ranking') as List;
      return [
        for (final r in rows.cast<Map<String, dynamic>>())
          RankedGuild(
            rank: (r['rank'] as num).toInt(),
            id: r['id'] as String,
            name: r['name'] as String,
            crest: GuildCrest.fromJson(r['crest'], r['name'] as String),
            level: (r['level'] as num).toInt(),
            points: (r['points'] as num).toInt(),
            members: (r['members'] as num).toInt(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Gold for the weeks that are ready (0 when none), paid out once.
  static Future<int> claim() async {
    try {
      final n = (await supabase.rpc('guild_boss_claim') as num).toInt();
      if (n > 0) {
        await SettlementController().grantResources({
          'gold': n.toDouble(),
        }, refund: true);
      }
      return n;
    } catch (e) {
      debugPrint('[GuildBoss] claim failed: $e');
      return 0;
    }
  }

  /// The whole attempt: pick a team, use the attempt up, fight, report the
  /// damage. Returns a short result line, or null when the player backed out
  /// before the fight began.
  static Future<String?> fight(
    BuildContext context,
    GuildBossState boss,
  ) async {
    final species = kSpeciesDefs[boss.speciesId];
    if (species == null) return 'That boss is not in this version of the game.';
    final foe = Combatant.fromSpecies(
      species,
      level: boss.level,
      id: 'guild_boss',
      isBoss: true,
      statScale: kGuildBossStatScale,
      rng: math.Random(boss.speciesId.hashCode),
    );
    final team = await Navigator.push<List<CreatureInstance>>(
      context,
      MaterialPageRoute(
        builder: (_) => BattlePrepScreen(
          title: 'Guild boss — ${boss.name}',
          enemies: [foe],
          partySize: kMaxPartySize,
          rewards: const [],
          isBoss: true,
          confirmLabel: 'Fight',
        ),
      ),
    );
    if (team == null || team.isEmpty || !context.mounted) return null;

    try {
      await supabase.rpc('guild_boss_begin');
    } catch (e) {
      final s = e.toString();
      if (s.contains('no_attempts')) return 'No attempts left today.';
      if (s.contains('boss_defeated')) return 'The boss has already fallen.';
      return guildErrorText(e);
    }

    final startHp = foe.hp;
    if (!context.mounted) return null;
    await Navigator.push<Object>(
      context,
      MaterialPageRoute(
        builder: (_) => BattleScreen(
          team: team,
          enemies: [foe],
          title: 'Guild boss — ${boss.name}',
        ),
      ),
    );
    // The engine works on this very Combatant, so what is left of its health
    // is what the team did not take.
    final taken = (startHp - foe.hp).clamp(0, startHp);
    final points = startHp <= 0 ? 0 : (taken * 100 / startHp).round();
    try {
      await supabase.rpc('guild_boss_hit', params: {'p_points': points});
    } catch (e) {
      debugPrint('[GuildBoss] hit failed: $e');
      return 'The result could not be sent — this attempt is lost.';
    }
    return 'You took $points points off the boss.';
  }
}
