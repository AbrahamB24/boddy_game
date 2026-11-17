import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_client.dart';
import '../creatures/models/breeding_job.dart';
import '../creatures/models/creature_enums.dart';
import '../creatures/models/creature_instance.dart';
import '../settlement/settlement_controller.dart';

/// The breeding board (migration 0073): a member lists up to 3 monsters, a
/// guild mate borrows a COPY of the genes for one mating. Nothing leaves its
/// owner.
const int kStudMaxListed = 3;

class StudListing {
  final String id;
  final String ownerId;
  final String ownerName;
  final String creatureId;
  final String speciesId;
  final String name;
  final CreatureGender gender;
  final int level;
  final CreatureRarity rarity;
  final Map<CreatureStat, double> base;
  final Map<CreatureStat, double> slope;
  final DateTime readyAt;
  final int fee;

  const StudListing({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.creatureId,
    required this.speciesId,
    required this.name,
    required this.gender,
    required this.level,
    required this.rarity,
    required this.base,
    required this.slope,
    required this.readyAt,
    required this.fee,
  });

  factory StudListing.fromRow(Map<String, dynamic> r) {
    final genes = (r['genes'] as Map?) ?? const {};
    return StudListing(
      id: r['id'] as String,
      ownerId: r['owner_id'] as String,
      ownerName: r['owner_name'] as String,
      creatureId: r['creature_id'] as String,
      speciesId: r['species_id'] as String,
      name: r['name'] as String,
      gender: CreatureGender.fromName(r['gender'] as String?),
      level: (r['level'] as num).toInt(),
      rarity: CreatureRarity.values.firstWhere(
        (x) => x.name == r['rarity'],
        orElse: () => CreatureRarity.common,
      ),
      base: BreedingJob.genesFromJson(genes['base']),
      slope: BreedingJob.genesFromJson(genes['slope']),
      readyAt: DateTime.parse(r['ready_at'] as String).toLocal(),
      fee: (r['fee'] as num).toInt(),
    );
  }

  bool get isResting => readyAt.isAfter(DateTime.now());
}

class GuildStuds extends ChangeNotifier {
  GuildStuds._();
  static final GuildStuds instance = GuildStuds._();

  String? get _myId {
    try {
      return supabase.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  List<StudListing> board = [];
  int used = 0;
  int limit = 1;

  List<StudListing> get mine =>
      [for (final s in board) if (s.ownerId == _myId) s];
  List<StudListing> get others =>
      [for (final s in board) if (s.ownerId != _myId) s];

  /// Whether this monster is on the board right now.
  bool isListed(String creatureId) => mine.any((s) => s.creatureId == creatureId);

  /// Can this monster go on the board? Legendaries never can.
  static bool canList(CreatureInstance c) {
    final r = c.species?.rarity;
    return r != null && r != CreatureRarity.legendary;
  }

  Future<void> refresh() async {
    try {
      final rows = await supabase.rpc('guild_stud_board') as List;
      board = [
        for (final r in rows.cast<Map<String, dynamic>>())
          StudListing.fromRow(r),
      ];
      final a = await supabase.rpc('guild_stud_allowance') as List;
      if (a.isNotEmpty) {
        final m = (a.first as Map).cast<String, dynamic>();
        used = (m['used'] as num).toInt();
        limit = (m['lim'] as num).toInt();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[GuildStuds] refresh failed: $e');
    }
  }

  /// Puts [c] on the board with its genes as they are NOW (listing again
  /// refreshes the snapshot).
  Future<void> list(CreatureInstance c) async {
    await supabase.rpc(
      'guild_stud_list',
      params: {
        'p_creature': c.id,
        'p_species': c.speciesId,
        'p_name': c.displayName,
        'p_gender': c.gender.name,
        'p_level': c.level,
        'p_rarity': c.species?.rarity.name ?? 'common',
        'p_genes': {
          'base': BreedingJob.genesToJson(c.statBase),
          'slope': BreedingJob.genesToJson(c.statSlope),
        },
      },
    );
    await refresh();
  }

  Future<void> unlist(String creatureId) async {
    await supabase.rpc('guild_stud_unlist', params: {'p_creature': creatureId});
    await refresh();
  }

  /// Records the loan on the server; returns the fee (the caller pays it).
  Future<int> borrow(String studId) async =>
      (await supabase.rpc('guild_stud_borrow', params: {'p_stud': studId})
              as num)
          .toInt();

  /// The owner's game collects the fees its monsters earned: gold, once.
  Future<void> takeFees() async {
    try {
      final n = (await supabase.rpc('guild_stud_take_fees') as num).toInt();
      if (n > 0) {
        await SettlementController().grantResources({'gold': n.toDouble()}, refund: true);
      }
    } catch (e) {
      debugPrint('[GuildStuds] fees failed: $e');
    }
  }
}
