import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../data/goods_definitions.dart';
import '../services/balance_simulator.dart';
import '../services/era_timeline_simulator.dart';
import '../widgets/building_icon.dart';

// Dev Mode's "Balance" tab — an editable stand-in for the user's own Excel
// balancing sheet (Balancing/Houses.xlsx from earlier this session): pick a
// count per building type, see the aggregate min/max production, population
// capacity, laborer surplus/deficit etc. recompute live. See
// services/balance_simulator.dart for the actual math (kept separate from
// this widget on purpose, so the formulas stay easy to eyeball against
// GameEngine.tick() without UI code in the way).
//
// Two modes, sharing the same building-count list as input:
// - Snapshot: instantaneous min/max hourly rates (services/balance_simulator.dart).
// - Simulation: time-axis companion — how many real days does a given
//   "player profile" (steps/day, workout BP/day, laborer staffing, reaction
//   delay) take to build up to that same loadout, and which resource
//   bottlenecks them along the way (services/era_timeline_simulator.dart).
enum _Mode { snapshot, simulation }

class BalanceSimulatorScreen extends StatefulWidget {
  const BalanceSimulatorScreen({super.key});

  @override
  State<BalanceSimulatorScreen> createState() => _BalanceSimulatorScreenState();
}

class _BalanceSimulatorScreenState extends State<BalanceSimulatorScreen> {
  final Map<String, int> _counts = {};
  final Map<String, TextEditingController> _controllers = {};
  _Mode _mode = _Mode.snapshot;
  PlayerProfile _profile = kPlayerProfilePresets[1];

  List<BuildingDef> get _buildings =>
      kBuildingDefs.values.where((d) => !d.isRoad).toList();

  @override
  void initState() {
    super.initState();
    for (final def in _buildings) {
      _counts[def.id] = 0;
      _controllers[def.id] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _applyToAll(int Function(BuildingDef def) valueFor) {
    setState(() {
      for (final def in _buildings) {
        final v = valueFor(def);
        _counts[def.id] = v;
        _controllers[def.id]!.text = v.toString();
      }
    });
  }

  void _setCount(BuildingDef def, String raw) {
    final parsed = int.tryParse(raw);
    if (parsed == null) return;
    final clamped = def.maxCount > 0
        ? parsed.clamp(0, def.maxCount)
        : (parsed < 0 ? 0 : parsed);
    setState(() => _counts[def.id] = clamped);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = BalanceSimulator.compute(_counts);
    final timeline = _mode == _Mode.simulation
        ? EraTimelineSimulator.run(_profile, _counts)
        : null;
    return Column(
      children: [
        _modeToggleRow(),
        const Divider(height: 1, color: FoE.border),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    _quickFillRow(),
                    if (_mode == _Mode.simulation) _profileSection(),
                    const Divider(height: 1, color: FoE.border),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _buildings.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (_, i) => _buildingRow(_buildings[i]),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 280,
                decoration: const BoxDecoration(
                  gradient: FoE.panelGradient,
                  border: Border(left: BorderSide(color: FoE.border)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(14),
                  child: _mode == _Mode.snapshot
                      ? _resultsPanel(snapshot)
                      : _timelinePanel(timeline!),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Mode toggle ─────────────────────────────────────────────
  Widget _modeToggleRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(child: _modeBtn('Snapshot', _Mode.snapshot)),
          const SizedBox(width: 8),
          Expanded(child: _modeBtn('Simulation', _Mode.simulation)),
        ],
      ),
    );
  }

  Widget _modeBtn(String label, _Mode mode) {
    final active = _mode == mode;
    return GestureDetector(
      onTap: () => setState(() => _mode = mode),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: FoE.btn(active: active),
        alignment: Alignment.center,
        child: Text(
          label,
          style: FoE.label(
            size: 13,
          ).copyWith(color: active ? FoE.goldBright : null),
        ),
      ),
    );
  }

  Widget _quickFillRow() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: _quickFillBtn('Clear all', () => _applyToAll((_) => 0)),
          ),
          const SizedBox(width: 8),
          Expanded(child: _quickFillBtn('1 each', () => _applyToAll((_) => 1))),
          const SizedBox(width: 8),
          Expanded(
            child: _quickFillBtn(
              'Max each',
              () => _applyToAll(
                (def) =>
                    def.maxCount > 0 ? def.maxCount : (_counts[def.id] ?? 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickFillBtn(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: FoE.btn(),
      alignment: Alignment.center,
      child: Text(label, style: FoE.label(size: 13)),
    ),
  );

  // ── Player profile section (Simulation mode only) ──────────
  Widget _profileSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (final preset in kPlayerProfilePresets) ...[
                Expanded(child: _presetChip(preset)),
                if (preset != kPlayerProfilePresets.last)
                  const SizedBox(width: 6),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _sliderRow(
            'Steps/day',
            '${_profile.stepsPerDay}',
            _profile.stepsPerDay.toDouble(),
            0,
            20000,
            40,
            (v) => setState(
              () => _profile = _profile.copyWith(
                name: 'Custom',
                stepsPerDay: v.round(),
              ),
            ),
          ),
          _sliderRow(
            'Workout BP/day',
            '${_profile.bpPerDay}',
            _profile.bpPerDay.toDouble(),
            0,
            300,
            60,
            (v) => setState(
              () => _profile = _profile.copyWith(
                name: 'Custom',
                bpPerDay: v.round(),
              ),
            ),
          ),
          _sliderRow(
            'Laborer utilization',
            '${(_profile.laborerStaffing * 100).round()}%',
            _profile.laborerStaffing,
            0,
            1,
            20,
            (v) => setState(
              () => _profile = _profile.copyWith(
                name: 'Custom',
                laborerStaffing: v,
              ),
            ),
          ),
          _sliderRow(
            'Reaction time',
            '${_profile.reactionDelayHours.round()}h',
            _profile.reactionDelayHours,
            0,
            48,
            48,
            (v) => setState(
              () => _profile = _profile.copyWith(
                name: 'Custom',
                reactionDelayHours: v,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(PlayerProfile preset) {
    final active = _profile.name == preset.name;
    return GestureDetector(
      onTap: () => setState(() => _profile = preset),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: FoE.btn(active: active),
        alignment: Alignment.center,
        child: Text(
          preset.name,
          style: FoE.label(
            size: 12,
          ).copyWith(color: active ? FoE.goldBright : null),
        ),
      ),
    );
  }

  Widget _sliderRow(
    String label,
    String valueLabel,
    double value,
    double min,
    double max,
    int divisions,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(width: 108, child: Text(label, style: FoE.label(size: 11))),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: FoE.gold,
              inactiveTrackColor: FoE.panelDark,
              thumbColor: FoE.goldBright,
              overlayColor: FoE.gold.withValues(alpha: 0.2),
              trackHeight: 3,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: FoE.value(size: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildingRow(BuildingDef def) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          BuildingIcon(imageUrl: def.imageUrl, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.name,
                  style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                ),
                Text(
                  def.maxCount > 0 ? 'max ${def.maxCount}' : 'unlimited',
                  style: FoE.dim(size: 10),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: TextFormField(
              controller: _controllers[def.id],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: FoE.value(size: 14),
              decoration: const InputDecoration(isDense: true),
              onChanged: (v) => _setCount(def, v),
            ),
          ),
        ],
      ),
    );
  }

  // ── Snapshot results panel ──────────────────────────────────
  Widget _resultsPanel(BalanceSnapshot s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Results', style: FoE.title(size: 15)),
        const SizedBox(height: 10),
        _statRow('Population (max)', '${s.population}'),
        _statRow('Workers required', '${s.workerRequirement}'),
        _statRow('Assignable population', '${s.assignablePopulation}'),
        _statRow('Max laborer capacity', '${s.maxLaborerCapacity}'),
        _statRow(
          'Laborer balance',
          s.laborerBalance >= 0
              ? '+${s.laborerBalance}'
              : '${s.laborerBalance}',
          warn: s.laborerBalance < 0,
        ),
        FoE.divider(),
        _rangeRow('🪵 Wood/h', s.woodMin, s.woodMax),
        _rangeRow('🪨 Stone/h', s.stoneMin, s.stoneMax),
        for (final gDef in kGoodsDefs.values)
          _rangeRow(
            '${gDef.emoji} ${gDef.name}/h',
            s.goodsMin[gDef.id] ?? 0,
            s.goodsMax[gDef.id] ?? 0,
          ),
        _rangeRow('🪙 Gold/h', s.goldMin, s.goldMax),
        FoE.divider(),
        _rangeRow('🔨 Build-sec/h', s.buildSpeedMin, s.buildSpeedMax),
        _rangeRow(
          '🔬 Research speed bonus %',
          s.researchSpeedBonusMin * 100,
          s.researchSpeedBonusMax * 100,
        ),
        _statRow('Queue slots granted', '+${s.queueSlotsBonus}'),
        FoE.divider(),
        _statRow('Total tiles used', '${s.totalTiles}'),
        _statRow('Wood cost', s.woodCost.toStringAsFixed(0)),
        _statRow('Stone cost', s.stoneCost.toStringAsFixed(0)),
        if (s.goodsUpkeep.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Upkeep (flat, not laborer-dependent)',
            style: FoE.dim(size: 10),
          ),
          for (final e in s.goodsUpkeep.entries)
            _statRow(
              '${kGoodsDefs[e.key]?.emoji ?? ''} ${kGoodsDefs[e.key]?.name ?? e.key}/h',
              '-${e.value.toStringAsFixed(1)}',
            ),
        ],
      ],
    );
  }

  // ── Simulation results panel ─────────────────────────────────
  Widget _timelinePanel(TimelineResult r) {
    final fractions = r.starvedFractions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Time simulation', style: FoE.title(size: 15)),
        const SizedBox(height: 10),
        if (!r.completed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '⚠ Not completed after 365 simulated days',
              style: FoE.label(size: 12).copyWith(color: FoE.danger),
            ),
          ),
        _statRow(
          'Days until era completed',
          r.completed ? r.totalDays.toStringAsFixed(1) : '> 365',
          warn: !r.completed,
        ),
        FoE.divider(),
        Text('Bottlenecks (share of blocked time)', style: FoE.dim(size: 10)),
        const SizedBox(height: 6),
        _bottleneckRow('🪵 Wood', fractions['wood'] ?? 0),
        _bottleneckRow('🪨 Stone', fractions['stone'] ?? 0),
        _bottleneckRow('⭐ BP', fractions['bp'] ?? 0),
        _bottleneckRow('👥 Population', fractions['population'] ?? 0),
        FoE.divider(),
        _statRow('Population (final)', '${r.finalPopulation}'),
        _statRow('Wood (final)', r.finalWood.toStringAsFixed(0)),
        _statRow('Stone (final)', r.finalStone.toStringAsFixed(0)),
        for (final gDef in kGoodsDefs.values)
          _statRow(
            '${gDef.emoji} ${gDef.name} (final)',
            (r.finalGoods[gDef.id] ?? 0).toStringAsFixed(0),
          ),
        FoE.divider(),
        Text('History', style: FoE.dim(size: 10)),
        const SizedBox(height: 6),
        for (final e in r.events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              '${e.day.toStringAsFixed(1)}d — ${e.label}',
              style: FoE.label(size: 11).copyWith(color: FoE.textDim),
            ),
          ),
      ],
    );
  }

  Widget _bottleneckRow(String label, double fraction) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: FoE.label(size: 12).copyWith(color: FoE.textDim),
            ),
            Text(
              '${(fraction * 100).toStringAsFixed(0)}%',
              style: FoE.value(
                size: 12,
              ).copyWith(color: fraction > 0.15 ? Colors.redAccent : FoE.gold),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: fraction.clamp(0.0, 1.0),
            minHeight: 5,
            color: fraction > 0.15 ? Colors.redAccent : FoE.gold,
            backgroundColor: FoE.panelDark,
          ),
        ),
      ],
    ),
  );

  Widget _statRow(String label, String value, {bool warn = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: FoE.label(size: 12).copyWith(color: FoE.textDim),
          ),
        ),
        Text(
          value,
          style: FoE.value(
            size: 13,
          ).copyWith(color: warn ? Colors.redAccent : FoE.gold),
        ),
      ],
    ),
  );

  Widget _rangeRow(String label, double min, double max) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: FoE.label(size: 12).copyWith(color: FoE.textDim),
          ),
        ),
        Text(
          '${min.toStringAsFixed(1)} – ${max.toStringAsFixed(1)}',
          style: FoE.value(size: 13).copyWith(color: FoE.gold),
        ),
      ],
    ),
  );
}
