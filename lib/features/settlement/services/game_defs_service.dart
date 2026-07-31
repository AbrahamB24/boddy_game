import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import '../../../core/supabase/supabase_client.dart';
import '../../creatures/models/area.dart';
import '../../creatures/models/path_node.dart';
import '../data/building_definitions.dart';
import '../data/era_definitions.dart';
import '../data/gather_defs.dart';
import '../data/item_definitions.dart';

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

  Future<List<Map<String, dynamic>>> loadEraDefRows() async {
    final rows = await supabase.from('era_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadAreaDefRows() async {
    final rows = await supabase.from('area_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadPathNodeRows() async {
    final rows = await supabase.from('path_nodes').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadItemDefRows() async {
    final rows = await supabase.from('item_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> loadGatherDefRows() async {
    final rows = await supabase.from('gather_defs').select();
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> upsertGatherDef(ResourceGatherDef def) async {
    await supabase.from('gather_defs').upsert(def.toDefRow());
  }

  Future<void> upsertBuildingDef(BuildingDef def) async {
    await supabase.from('building_defs').upsert(def.toDefRow());
  }

  Future<void> upsertEraDef(EraDef def) async {
    await supabase.from('era_defs').upsert(def.toDefRow());
  }

  Future<void> upsertAreaDef(AreaDef def) async {
    await supabase.from('area_defs').upsert(def.toDefRow());
  }

  Future<void> upsertPathNode(PathNode node) async {
    await supabase.from('path_nodes').upsert(node.toDefRow());
  }

  Future<void> upsertItemDef(ItemDef def) async {
    await supabase.from('item_defs').upsert(def.toDefRow());
  }

  /// Writes [def] back as a TOMBSTONE: the whole row, plus `retired`.
  ///
  /// The full row rather than a bare `{id, retired}` because the table's columns
  /// are NOT NULL — and because un-retiring it should give back the def as it
  /// was, not an empty husk.
  Future<void> retireBuildingDef(BuildingDef def) async {
    await supabase
        .from('building_defs')
        .upsert({...def.toDefRow(), 'retired': true});
  }

  Future<void> deleteBuildingDef(String id) async {
    await supabase.from('building_defs').delete().eq('id', id);
  }

  Future<void> deleteEraDef(String id) async {
    await supabase.from('era_defs').delete().eq('id', id);
  }

  Future<void> deleteAreaDef(String id) async {
    await supabase.from('area_defs').delete().eq('id', id);
  }

  Future<void> deletePathNode(String id) async {
    await supabase.from('path_nodes').delete().eq('id', id);
  }

  Future<void> deleteItemDef(String id) async {
    await supabase.from('item_defs').delete().eq('id', id);
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
    // Cache-buster: the storage path is stable per building (upsert), so a
    // REPLACED png would come back under the exact same URL — and both
    // Flutter's image cache and the browser (web build) would keep serving
    // the old bytes forever, making "Replace PNG" look dead. The version
    // query makes every upload a fresh URL (persisted on the def row) while
    // the file itself stays at one path, so nothing is orphaned.
    final url = supabase.storage.from('building-images').getPublicUrl(path);
    return '$url?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}
