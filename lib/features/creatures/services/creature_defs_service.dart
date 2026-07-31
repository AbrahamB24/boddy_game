import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/supabase/supabase_client.dart';
import '../models/ability_def.dart';
import '../models/heal_balance.dart';
import '../models/species_balance.dart';
import '../models/species_def.dart';
import '../models/xp_balance.dart';

// Same house style as GameDefsService: plain service, direct supabase calls,
// no pre-migration fallbacks (species/ability defs deploy in lockstep with
// this feature).
class CreatureDefsService {
  Future<List<Map<String, dynamic>>> loadSpeciesDefRows() async {
    final rows = await supabase.from('species_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadAbilityDefRows() async {
    final rows = await supabase.from('ability_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> upsertSpeciesDef(SpeciesDef def) async {
    await supabase.from('species_defs').upsert(def.toDefRow());
  }

  Future<void> upsertAbilityDef(AbilityDef def) async {
    await supabase.from('ability_defs').upsert(def.toDefRow());
  }

  Future<void> deleteSpeciesDef(String id) async {
    await supabase.from('species_defs').delete().eq('id', id);
  }

  Future<void> deleteAbilityDef(String id) async {
    await supabase.from('ability_defs').delete().eq('id', id);
  }

  // ── Global species-balance config (game_config, key 'species_balance') ──
  static const _balanceKey = 'species_balance';

  Future<SpeciesBalance?> loadSpeciesBalance() async {
    final rows = await supabase
        .from('game_config')
        .select('value')
        .eq('key', _balanceKey);
    final list = (rows as List);
    if (list.isEmpty) return null;
    final v = (list.first as Map)['value'];
    return v is Map
        ? SpeciesBalance.fromJson(Map<String, dynamic>.from(v))
        : null;
  }

  Future<void> saveSpeciesBalance(SpeciesBalance balance) async {
    await supabase.from('game_config').upsert({
      'key': _balanceKey,
      'value': balance.toJson(),
    });
  }

  // ── Global XP config (game_config, key 'xp_balance') ──────────────────
  // Its own row rather than a section of 'species_balance': these are global
  // rates, not per-rarity budgets, and keeping them apart means an older client
  // reading only one of the two still gets a valid config.
  static const _xpKey = 'xp_balance';

  Future<XpConfig?> loadXpBalance() async {
    final rows = await supabase
        .from('game_config')
        .select('value')
        .eq('key', _xpKey);
    final list = (rows as List);
    if (list.isEmpty) return null;
    final v = (list.first as Map)['value'];
    return v is Map ? XpConfig.fromJson(Map<String, dynamic>.from(v)) : null;
  }

  Future<void> saveXpBalance(XpConfig xp) async {
    await supabase.from('game_config').upsert({
      'key': _xpKey,
      'value': xp.toJson(),
    });
  }

  // ── Global healing config (game_config, key 'heal_balance') ───────────
  static const _healKey = 'heal_balance';

  Future<HealConfig?> loadHealBalance() async {
    final rows = await supabase
        .from('game_config')
        .select('value')
        .eq('key', _healKey);
    final list = (rows as List);
    if (list.isEmpty) return null;
    final v = (list.first as Map)['value'];
    return v is Map ? HealConfig.fromJson(Map<String, dynamic>.from(v)) : null;
  }

  Future<void> saveHealBalance(HealConfig heal) async {
    await supabase.from('game_config').upsert({
      'key': _healKey,
      'value': heal.toJson(),
    });
  }

  // Uploads one evolution stage's PNG to the public 'creature-images' bucket
  // (upsert overwrite, same convention as building images) and returns the
  // public URL for SpeciesStage.imageUrl. The FRONT view lives at
  // '{speciesId}_{stage}.png'; the optional BACK view (shown for the player's
  // own monster in battle) at '{speciesId}_{stage}_back.png'.
  Future<String> uploadStageImage(
    String speciesId,
    int stage,
    Uint8List bytes, {
    bool back = false,
  }) async {
    final path = '${speciesId}_$stage${back ? '_back' : ''}.png';
    await supabase.storage
        .from('creature-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );
    // Cache-buster — same reasoning as uploadBuildingImage: the path is
    // stable per species+stage, so a replaced png keeps its URL and every
    // image cache serves the stale bytes. The version query mints a fresh
    // URL per upload without moving the file.
    final url = supabase.storage.from('creature-images').getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
