import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/orientation_lock.dart';
import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import 'data/building_definitions.dart';
import 'data/goods_definitions.dart';
import 'dev/dev_mode_screen.dart';
import 'models/resource_model.dart';
import 'research_screen.dart';
import 'services/game_engine.dart';
import 'settlement_controller.dart';
import 'sheets/build_menu_sheet.dart';
import 'sheets/energy_sheet.dart';
import 'sheets/population_overview_sheet.dart';
import 'sheets/resource_breakdown_sheet.dart';
import 'widgets/building_icon.dart';
import 'widgets/settlement_map.dart';
import '../creatures/collection_screen.dart';
import '../creatures/dungeon_map_screen.dart';

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with OrientationLock<SettlementScreen> {
  final _ctrl = SettlementController();
  String? _pendingTypeId;
  bool _editMode = false;
  bool _roadMode = false;

  @override
  List<DeviceOrientation> get lockedOrientations => const [
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _ctrl.addListener(_rebuild);
    _ctrl.load();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _ctrl.removeListener(_rebuild);
    _ctrl.stopTicker();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  // ── Navigation ────────────────────────────────────────────
  void _goToResearch() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => ResearchScreen(ctrl: _ctrl)),
  );

  void _showCreatures() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const CollectionScreen()),
  );

  // Dungeon entry — will move onto a placeable portal building once that
  // def exists; the quick-menu button is the interim entrance.
  void _showDungeon() => showDungeonEntrySheet(context);

  void _showDevMode() => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const DevModeScreen()),
  );

  // ── Bottom sheets ─────────────────────────────────────────
  void _showBuildMenu() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BuildMenuSheet(
      ctrl: _ctrl,
      onSelect: (id) => setState(() => _pendingTypeId = id),
      onEnterMoveMode: () => setState(() {
        _editMode = true;
        _roadMode = false;
      }),
      onPaintRoads: _enterRoadMode,
    ),
  );

  void _enterRoadMode() => setState(() {
    _roadMode = true;
    _editMode = false;
    _pendingTypeId = null;
  });

  void _showEnergyOverview() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EnergySheet(ctrl: _ctrl),
  );

  void _showPopulationOverview() => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PopulationOverviewSheet(ctrl: _ctrl),
  );

  void _showResourceBreakdown({
    required String emoji,
    required String title,
    required double total,
    required String unit,
    required List<ProductionSource> sources,
  }) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ResourceBreakdownSheet(
      emoji: emoji,
      title: title,
      total: total,
      unit: unit,
      sources: sources,
    ),
  );

  // ── Build ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoE.bg,
      body: _ctrl.isLoading
          ? _loading()
          : _ctrl.error != null
          ? _error()
          : _layout(),
    );
  }

  Widget _loading() =>
      Center(child: CircularProgressIndicator(color: FoE.gold));

  Widget _error() => Center(
    child: Text(_ctrl.error!, style: const TextStyle(color: Colors.redAccent)),
  );

  Widget _layout() => Stack(
    children: [
      Positioned.fill(
        child: SettlementMap(
          ctrl: _ctrl,
          pendingTypeId: _pendingTypeId,
          editMode: _editMode,
          roadMode: _roadMode,
          onPlacementDone: () => setState(() => _pendingTypeId = null),
          onExitEditMode: () => setState(() => _editMode = false),
          onExitRoadMode: () => setState(() => _roadMode = false),
        ),
      ),
      Positioned(top: 0, left: 0, right: 0, child: _topBar()),
      Positioned(top: 50, left: 8, child: _debugRow()),
      Positioned(bottom: 16, right: 12, child: _quickMenu()),
      if (_pendingTypeId != null)
        Positioned(bottom: 10, left: 10, right: 70, child: _placementBanner()),
    ],
  );

  // ── Top bar ───────────────────────────────────────────────
  Widget _topBar() {
    final res = _ctrl.resources;
    final rates = _ctrl.hourlyRates;
    final settlement = _ctrl.settlement;

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEE2A1E0C), Color(0xCC180E06)],
        ),
        border: Border(bottom: BorderSide(color: FoE.border, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Back to the app shell (this screen is now pushed from the Profile
          // tab, so there's always a route to pop).
          WorkoutBackButton(
            color: FoE.parchment,
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 4),
          // Name + era
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settlement?.name ?? 'My Settlement',
                style: FoE.title(size: 12),
              ),
              Text(
                _ctrl.currentEra != null
                    ? '${_ctrl.currentEra!.emoji} ${_ctrl.currentEra!.name}'
                    : 'Era ${settlement?.eraIndex ?? 1}',
                style: FoE.dim(),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 26,
            color: FoE.border,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          // Bauressourcen — horizontally scrollable so it never overflows on
          // narrow phones; name/era and the BP chip stay pinned either side.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (res != null) ...[
                    _resCell(
                      '🪵',
                      'Wood',
                      'wood',
                      res.wood,
                      rates['wood'] ?? 0,
                    ),
                    _resDivider(),
                    _resCell(
                      '🪨',
                      'Stone',
                      'stone',
                      res.stone,
                      rates['stone'] ?? 0,
                    ),
                    _resDivider(),
                    _resCell(
                      '🪙',
                      'Gold',
                      'gold',
                      res.gold,
                      rates['gold'] ?? 0,
                    ),
                    _resDivider(),
                    // Population
                    _popCell(),
                    _resDivider(),
                    // Goods
                    ..._goodsCells(res, rates),
                  ],
                  if (_ctrl.energy != null) ...[_resDivider(), _energyCell()],
                ],
              ),
            ),
          ),
          // BP chip
          GestureDetector(
            onTap: () => _ctrl.addBp(100),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2E2212), Color(0xFF1C1408)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: FoE.borderGold, width: 1),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome,
                    color: FoE.goldBright,
                    size: _kHeaderIconSize,
                  ),
                  const SizedBox(width: 4),
                  Text('${_ctrl.bp} BP', style: FoE.value(size: 12)),
                  const SizedBox(width: 4),
                  Text(
                    '+100',
                    style: FoE.dim(
                      size: _kHeaderSubSize,
                    ).copyWith(color: FoE.gold),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  // Shared sizing for every header cell so icons and text lines all match up.
  static const _kHeaderIconSize = 13.0;
  static const _kHeaderSubSize = 9.0;

  Widget _resCell(
    String emoji,
    String title,
    String resourceId,
    double amount,
    double rate,
  ) => GestureDetector(
    onTap: () => _showResourceBreakdown(
      emoji: emoji,
      title: title,
      total: rate,
      unit: '/h',
      sources: _ctrl.productionSources(resourceId),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: _kHeaderIconSize)),
              const SizedBox(width: 4),
              Text(amount.toStringAsFixed(0), style: FoE.value(size: 12)),
            ],
          ),
          Text(
            '+${rate.toStringAsFixed(1)}/h',
            style: FoE.dim(size: _kHeaderSubSize),
          ),
        ],
      ),
    ),
  );

  Widget _popCell() {
    final used = _ctrl.housingUsed;
    final cap = _ctrl.housingCapacity;
    return GestureDetector(
      onTap: _showPopulationOverview,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🏠', style: TextStyle(fontSize: _kHeaderIconSize)),
                const SizedBox(width: 3),
                Text(
                  '$used/$cap',
                  style: FoE.value(size: 12).copyWith(
                    color: used >= cap ? Colors.redAccent : null,
                  ),
                ),
              ],
            ),
            Text('housing', style: FoE.dim(size: _kHeaderSubSize)),
          ],
        ),
      ),
    );
  }

  List<Widget> _goodsCells(ResourceModel res, Map<String, double> rates) {
    final cells = <Widget>[];
    for (final gDef in kGoodsDefs.values) {
      final amount = res.goods[gDef.id] ?? 0;
      final rate = rates[gDef.id] ?? 0;
      cells.add(_resDivider());
      cells.add(
        GestureDetector(
          onTap: () => _showResourceBreakdown(
            emoji: gDef.emoji,
            title: gDef.name,
            total: rate,
            unit: '/h',
            sources: _ctrl.productionSources(gDef.id),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      gDef.emoji,
                      style: const TextStyle(fontSize: _kHeaderIconSize),
                    ),
                    const SizedBox(width: 3),
                    Text(amount.toStringAsFixed(0), style: FoE.value(size: 12)),
                  ],
                ),
                Text(
                  '+${rate.toStringAsFixed(1)}/h',
                  style: FoE.dim(size: _kHeaderSubSize),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return cells;
  }

  Widget _energyCell() {
    final energy = _ctrl.energy!;
    final pct = energy.currentEnergy;
    final isEmpty = pct <= 0;
    // Remaining-time estimate at the current tick's snapshot — no dedicated
    // 1s ticker needed here (unlike EnergySheet's live countdown): at this
    // drain rate (kMaxEnergy/kDrainPerHour ≈ 30h), fmtDuration only shows
    // minute resolution, so the screen's normal 5s-tick rebuild is already
    // more than fine-grained enough for it to read as live.
    final hoursLeft = GameEngine.hoursUntilEmpty(pct);
    return GestureDetector(
      onTap: _showEnergyOverview,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('⚡', style: TextStyle(fontSize: _kHeaderIconSize)),
                const SizedBox(width: 4),
                Text(
                  pct.toStringAsFixed(0),
                  style: FoE.value(
                    size: 12,
                  ).copyWith(color: isEmpty ? Colors.redAccent : Colors.white),
                ),
              ],
            ),
            Text(
              isEmpty ? 'empty' : fmtDuration(hoursLeft * 3600),
              style: FoE.dim(
                size: _kHeaderSubSize,
              ).copyWith(color: isEmpty ? Colors.redAccent : FoE.textDim),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resDivider() => Container(
    width: 1,
    height: 22,
    color: FoE.border,
    margin: const EdgeInsets.symmetric(horizontal: 2),
  );

  Widget _placementBanner() {
    final def = kBuildingDefs[_pendingTypeId!]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: FoE.panel(
        radius: 8,
        overrideBorder: Colors.greenAccent.shade400,
      ),
      child: Row(
        children: [
          BuildingIcon(imageUrl: def.imageUrl, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tap the map to place ${def.name}',
              style: FoE.label().copyWith(color: Colors.greenAccent),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _pendingTypeId = null),
            child: const Icon(Icons.close, color: FoE.textDim, size: 16),
          ),
        ],
      ),
    );
  }

  // ── Debug row (under header, under settlement name) ────────
  Widget _debugRow() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _debugBtn('⭐ +BP', () => _ctrl.addBp(500)),
      const SizedBox(width: 6),
      _debugBtn('⚡ +E', () => _ctrl.addSteps(5000)),
      const SizedBox(width: 6),
      _debugBtn('🔄 Reset', _confirmReset),
      // Gated on the account flag (profiles.is_dev), not kDebugMode —
      // this is meant to work in real builds too, only for the flagged
      // dev account.
      if (_ctrl.isDev) ...[
        const SizedBox(width: 6),
        _debugBtn('🛠 Dev Mode', _showDevMode),
      ],
    ],
  );

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 260,
          decoration: FoE.panel(radius: 12),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🔄  Reset Settlement?', style: FoE.title(size: 14)),
              const SizedBox(height: 10),
              Text(
                'Deletes all buildings, resources, energy allocation and '
                'research. BP/level are kept. This cannot be undone.',
                textAlign: TextAlign.center,
                style: FoE.label().copyWith(color: FoE.textDim),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: FoE.btn(),
                      child: Text(
                        'Cancel',
                        style: FoE.label().copyWith(color: FoE.textDim),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.shade900.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.red.shade700),
                      ),
                      child: Text(
                        'Reset',
                        style: FoE.label().copyWith(color: Colors.red.shade300),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) await _ctrl.resetSettlement();
  }

  Widget _debugBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1206),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: FoE.border),
      ),
      child: Text(label, style: FoE.dim(size: 9).copyWith(color: FoE.gold)),
    ),
  );

  // ── Quick menu (bottom-right, icon only) ────────────────────
  // Columns of up to 2 buttons stacked, anchored to the bottom edge.
  Widget _quickMenu() => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      _quickCol([_quickBtn('🔬', 'Research', _goToResearch)]),
      const SizedBox(width: 6),
      _quickCol([
        _quickBtn('🏰', 'Dungeon', _showDungeon),
        _quickBtn('🐾', 'Kreaturen', _showCreatures),
      ]),
      const SizedBox(width: 6),
      _quickCol([
        _quickBtn('🔨', 'Build', _showBuildMenu),
      ]),
    ],
  );

  Widget _quickCol(List<Widget> buttons) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (int i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: 6),
        buttons[i],
      ],
    ],
  );

  Widget _quickBtn(
    String emoji,
    String label,
    VoidCallback onTap, {
    bool selected = false,
  }) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: selected
              ? FoE.btn(active: true).copyWith(
                  border: Border.all(
                    color: Colors.greenAccent.shade400,
                    width: 2,
                  ),
                )
              : FoE.btn(active: true),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
