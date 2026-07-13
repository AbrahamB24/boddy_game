import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/supabase/supabase_client.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/tech_definitions.dart';

// Plain service class, same house style as SettlementService — direct
// supabase.from(...) calls, no repository abstraction. Unlike
// SettlementService, writes here skip the pre-migration try/catch fallback
// cascade convention: building_defs/tech_defs are new tables deployed in
// lockstep with this feature, so there's no legacy-schema-mismatch risk to
// guard against.
class GameDefsService {
  Future<List<Map<String, dynamic>>> loadBuildingDefRows() async {
    final rows = await supabase.from('building_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadTechDefRows() async {
    final rows = await supabase.from('tech_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadEraDefRows() async {
    final rows = await supabase.from('era_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> upsertBuildingDef(BuildingDef def) async {
    await supabase.from('building_defs').upsert(def.toDefRow());
  }

  Future<void> upsertTechDef(TechDef def) async {
    await supabase.from('tech_defs').upsert(def.toDefRow());
  }

  Future<void> upsertEraDef(EraDef def) async {
    await supabase.from('era_defs').upsert(def.toDefRow());
  }

  Future<void> deleteBuildingDef(String id) async {
    await supabase.from('building_defs').delete().eq('id', id);
  }

  Future<void> deleteTechDef(String id) async {
    await supabase.from('tech_defs').delete().eq('id', id);
  }

  Future<void> deleteEraDef(String id) async {
    await supabase.from('era_defs').delete().eq('id', id);
  }

  // Uploads a building's PNG to the public 'building-images' bucket at
  // '{buildingId}.png' (upsert: true, so re-uploading for the same building
  // just overwrites the old file — never an orphaned file to clean up) and
  // returns its public URL for BuildingDef.imageUrl. See supabase_schema.sql
  // for the bucket + its is_dev-gated write policy.
  Future<String> uploadBuildingImage(String buildingId, Uint8List bytes) async {
    final path = '$buildingId.png';
    await supabase.storage
        .from('building-images')
        .uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/png',
          ),
        );
    return supabase.storage.from('building-images').getPublicUrl(path);
  }
}
