import '../../../core/supabase/supabase_client.dart';
import '../models/placed_building.dart';
import '../models/settlement.dart';

/// Read-only loader for a FOREIGN user's settlement — the "visit a friend's
/// city" feature. Deliberately separate from [SettlementService]: that one
/// is written for the current player's own singleton [SettlementController]
/// (getOrCreate, savers, reset); this only ever reads, and takes an explicit
/// userId instead of assuming `auth.uid()`.
class SettlementReadService {
  Future<SettlementModel?> loadSettlement(String userId) async {
    final row = await supabase
        .from('settlements')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    return row == null ? null : SettlementModel.fromMap(row);
  }

  Future<List<PlacedBuilding>> loadBuildings(String settlementId) async {
    final rows = await supabase
        .from('placed_buildings')
        .select()
        .eq('settlement_id', settlementId);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PlacedBuilding.fromMap)
        .toList();
  }
}
