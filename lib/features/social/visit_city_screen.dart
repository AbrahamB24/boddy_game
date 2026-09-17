import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/models/placed_building.dart';
import '../settlement/services/settlement_read_service.dart';
import '../settlement/sheets/building_info_popup.dart';
import '../settlement/widgets/visit_settlement_map.dart';

/// View-only visit of a friend's settlement (user 2026-09-15: "Stadt des
/// Freundes besuchen ... nur Ansicht"). Loads the friend's buildings via
/// [SettlementReadService] (a foreign userId, not the local singleton
/// SettlementController) and renders them with [VisitSettlementMap], which
/// has no drag/placement/road interactions at all — tapping a building only
/// ever opens the read-only [showBuildingInfoPopup].
class VisitCityScreen extends StatefulWidget {
  final String friendUserId;
  final String friendName;

  const VisitCityScreen({
    super.key,
    required this.friendUserId,
    required this.friendName,
  });

  @override
  State<VisitCityScreen> createState() => _VisitCityScreenState();
}

class _VisitCityScreenState extends State<VisitCityScreen> {
  final _svc = SettlementReadService();
  List<PlacedBuilding>? _buildings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settlement = await _svc.loadSettlement(widget.friendUserId);
      if (settlement == null) {
        if (!mounted) return;
        setState(() => _error = "${widget.friendName} hasn't started a settlement yet.");
        return;
      }
      final buildings = await _svc.loadBuildings(settlement.id);
      if (!mounted) return;
      setState(() => _buildings = buildings);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: "${widget.friendName}'s city",
    bands: false,
    child: _body(),
  );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: FoE.label().copyWith(color: FoE.textDim),
          ),
        ),
      );
    }
    final buildings = _buildings;
    if (buildings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return VisitSettlementMap(
      buildings: buildings,
      onTapBuilding: (building, def) =>
          showBuildingInfoPopup(context, building, def),
    );
  }
}
