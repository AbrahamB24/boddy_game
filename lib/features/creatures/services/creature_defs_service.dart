import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/supabase/supabase_client.dart';
import '../models/ability_def.dart';
import '../models/species_def.dart';

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

  // Uploads one evolution stage's PNG to the public 'creature-images' bucket
  // at '{speciesId}_{stage}.png' (upsert overwrite, same convention as
  // building images) and returns the public URL for SpeciesStage.imageUrl.
  Future<String> uploadStageImage(
    String speciesId,
    int stage,
    Uint8List bytes,
  ) async {
    final path = '${speciesId}_$stage.png';
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
    return supabase.storage.from('creature-images').getPublicUrl(path);
  }
}
