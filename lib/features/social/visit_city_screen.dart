import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../settlement/models/placed_building.dart';
import '../settlement/services/settlement_read_service.dart';
import '../settlement/sheets/building_info_popup.dart';
import '../settlement/widgets/visit_settlement_map.dart';
import 'widgets/social_kit.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

/// A friend's city, read-only (user 2026-09-19, Holz palette): the real map
/// fills the screen with a dark name plate at the top left — who, and their
/// rating — Challenge and Message at the top right next to the close button,
/// and a line at the bottom saying you can only look. Tapping a building opens
/// [showBuildingInfoPopup].
///
/// Pops with `true` when Message is tapped, so whoever opened this can take you
/// to the chat.
class VisitCityScreen extends StatefulWidget {
  final String friendUserId;
  final String friendName;

  /// "1240 · 12W 5L" — shown on the name plate when known.
  final String? record;

  /// Sends a challenge to this friend. Null hides the button.
  final Future<void> Function()? onChallenge;

  const VisitCityScreen({
    super.key,
    required this.friendUserId,
    required this.friendName,
    this.record,
    this.onChallenge,
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
        setState(
          () =>
              _error = "${widget.friendName} hasn't started a settlement yet.",
        );
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
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: CreamPalette.groundBottom,
    body: Stack(
      children: [
        Positioned.fill(child: _body()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                if (_buildings != null) _hint(),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _topBar() => Row(
    children: [
      _namePlate(),
      const Spacer(),
      if (widget.onChallenge != null) ...[
        SocialTileButton(
          'Challenge',
          icon: Icons.sports_martial_arts,
          height: 36,
          fontSize: 13,
          onTap: widget.onChallenge,
        ),
        const SizedBox(width: 8),
      ],
      SocialTileButton(
        'Message',
        icon: Icons.chat_bubble_outline,
        height: 36,
        fontSize: 13,
        onTap: () => Navigator.pop(context, true),
      ),
      const SizedBox(width: 8),
      const KitCloseButton(),
    ],
  );

  Widget _namePlate() => Container(
    height: 46,
    padding: const EdgeInsets.fromLTRB(8, 0, 16, 0),
    decoration: BoxDecoration(
      borderRadius: vr(14),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CreamPalette.groundTop, CreamPalette.groundBottom],
      ),
      boxShadow: const [
        BoxShadow(color: Color(0x6B000000), offset: Offset(0, 3)),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SocialAvatar(widget.friendName, size: 32),
        const SizedBox(width: 10),
        Text(
          "${widget.friendName}'s city",
          style: FoE.title(size: 15).copyWith(color: kBoxInk),
        ),
        if (widget.record != null) ...[
          const SizedBox(width: 10),
          Text(
            'Rating ${widget.record}',
            style: FoE.dim(
              size: 11,
            ).copyWith(color: kBoxInk.withValues(alpha: 0.72)),
          ),
        ],
      ],
    ),
  );

  Widget _hint() => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xD12A1A0C),
        borderRadius: vr(12),
      ),
      child: Text(
        "Tap a building to look inside · visitors can't change anything",
        style: FoE.label(size: 11.5).copyWith(color: kBoxInk),
      ),
    ),
  );

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: FoE.label().copyWith(color: kBoxInk),
          ),
        ),
      );
    }
    final buildings = _buildings;
    if (buildings == null) {
      return const Center(
        child: CircularProgressIndicator(color: CreamPalette.gold),
      );
    }
    return VisitSettlementMap(
      buildings: buildings,
      onTapBuilding: (building, def) =>
          showBuildingInfoPopup(context, building, def),
    );
  }
}
