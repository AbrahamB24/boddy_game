import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import 'data/era_definitions.dart';
import 'data/tech_definitions.dart';
import 'settlement_controller.dart';
import 'sheets/build_menu_sheet.dart' show fmtDuration;

// ── Canvas layout ──────────────────────────────────────────
// Column/row spacing is fixed, but the number of columns/rows is derived
// from the CURRENT ERA's tech subset's actual col/row values (computed by
// GameDefsController's per-era tech-tree auto-layout) rather than a
// hardcoded 3x3 grid — the tree can grow arbitrarily once dev-mode editing
// exists, and this must never index out of bounds. Every layout helper here
// takes the already-era-filtered tech list as a parameter rather than
// reading kTechDefs globally, so nothing accidentally renders/sizes from
// another era's tech.
const _kNodeW = 118.0;
const _kNodeH = 80.0;
const _kColSpacing = 205.0;
const _kRowSpacing = 120.0;
const _kColX0 = 70.0;
const _kRowY0 = 70.0;
const _kCanvasMarginX = 90.0;
const _kCanvasMarginY = 70.0;

double _colX(int col) => _kColX0 + col * _kColSpacing;
double _rowY(int row) => _kRowY0 + row * _kRowSpacing;

int _maxTechCol(Iterable<TechDef> techs) =>
    techs.isEmpty ? 0 : techs.map((d) => d.col).reduce((a, b) => a > b ? a : b);
int _maxTechRow(Iterable<TechDef> techs) =>
    techs.isEmpty ? 0 : techs.map((d) => d.row).reduce((a, b) => a > b ? a : b);

// Pseudo tech id for the "advance to next era" capstone node — it always
// sits one column past the last tech of the current era, vertically
// centered among the rows in use. Deliberately not a real building/tech id
// (avoids any confusion with the 'main_hall' building).
const _kEraCapstoneNodeId = 'era_capstone';
int _hallCol(Iterable<TechDef> techs) => _maxTechCol(techs) + 1;
int _hallRow(Iterable<TechDef> techs) => (_maxTechRow(techs) / 2).round();

Offset _center(TechDef d) => Offset(_colX(d.col), _rowY(d.row));

// ── Screen ───────────────────────────────────────────────
class ResearchScreen extends StatefulWidget {
  final SettlementController ctrl;
  const ResearchScreen({super.key, required this.ctrl});

  @override
  State<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends State<ResearchScreen> {
  String? _sel;
  // researchSecondsBuilt only advances on the controller's 5s-authoritative
  // tick, which would make the on-screen countdown visibly jump in 5s steps.
  // This ticker forces a repaint every 1s so _researchBuiltNowSeconds can
  // extrapolate from the last tick's anchor using wall-clock time — same
  // technique as _BuildCountdown in settlement_map.dart.
  Timer? _liveTicker;

  @override
  void initState() {
    super.initState();
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _ctrl.settlement?.activeResearchId != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    super.dispose();
  }

  SettlementController get _ctrl => widget.ctrl;

  // Only the settlement's current era's tech is ever shown/researchable —
  // this is what makes "advance once this era's tree is done" well-defined
  // (see EraDef/SettlementController.advanceEra). Tech from other eras is
  // never reachable/visible here (past-era tech is, by construction, always
  // fully researched by the time you've advanced past it).
  List<TechDef> get _currentEraTechs {
    final eraId = _ctrl.currentEra?.id;
    return kTechDefs.values.where((t) => t.eraId == eraId).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctrl,
      builder: (context, _) => Scaffold(
        backgroundColor: FoE.bg,
        body: Column(
          children: [
            _topBar(),
            Expanded(
              child: Row(
                children: [
                  // Tech tree (scrollable)
                  Expanded(
                    child: InteractiveViewer(
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(24),
                      minScale: 0.55,
                      maxScale: 2.5,
                      child: _canvas(),
                    ),
                  ),
                  // Detail panel (fixed right column)
                  _detailColumn(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────
  Widget _topBar() => Container(
    height: 44,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        WorkoutBackButton(
          color: FoE.gold,
          onTap: () => Navigator.pop(context),
        ),
        const SizedBox(width: 4),
        Text('Research', style: FoE.title(size: 15)),
        const Spacer(),
        // State legend — collapsed into one icon so the bar never
        // overflows on narrow phones (node colours already convey this).
        PopupMenuButton<void>(
          tooltip: 'Node colours',
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.info_outline, color: FoE.gold, size: 18),
          color: FoE.panelDark,
          itemBuilder: (context) => [
            PopupMenuItem<void>(
              enabled: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _legend('▪ Locked', FoE.border),
                  const SizedBox(height: 6),
                  _legend('▪ Available', FoE.gold),
                  const SizedBox(height: 6),
                  _legend('▪ Researched', FoE.goldBright),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        // BP display
        Container(
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
              const Icon(Icons.auto_awesome, color: FoE.goldBright, size: 12),
              const SizedBox(width: 4),
              Text('${_ctrl.bp} BP', style: FoE.value(size: 12)),
            ],
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
  );

  Widget _legend(String text, Color color) =>
      Text(text, style: FoE.dim(size: 10).copyWith(color: color));

  // ── Tech tree canvas ──────────────────────────────────────
  Widget _canvas() {
    final unlocked = _ctrl.unlockedTechs;
    final techs = _currentEraTechs;
    return SizedBox(
      width: _colX(_hallCol(techs)) + _kCanvasMarginX,
      height: _rowY(_maxTechRow(techs)) + _kCanvasMarginY,
      child: Stack(
        children: [
          // Background parchment
          Positioned.fill(child: CustomPaint(painter: _CanvasBgPainter())),
          // Connection lines
          Positioned.fill(
            child: CustomPaint(
              painter: _LinePainter(
                techs: techs,
                unlocked: unlocked,
                selected: _sel,
              ),
            ),
          ),
          // Nodes
          ...techs.map((d) => _node(d, unlocked)),
          // Era capstone — advance to the next era, once it exists and this
          // era's tech is fully researched.
          _nextEraNode(techs, unlocked),
        ],
      ),
    );
  }

  Widget _node(TechDef def, Set<String> unlocked) {
    final c = _center(def);
    final researched = unlocked.contains(def.id);
    final inProgress = _ctrl.settlement?.activeResearchId == def.id;
    final available =
        !researched &&
        !inProgress &&
        def.prerequisites.every(unlocked.contains);
    final canAfford = available && _ctrl.bp >= def.bpCost;
    final selected = _sel == def.id;
    final effectiveSeconds = _ctrl.effectiveResearchSeconds(def);
    final progress = inProgress
        ? (effectiveSeconds <= 0
              ? 1.0
              : (_researchBuiltNowSeconds(def) / effectiveSeconds).clamp(
                  0.0,
                  1.0,
                ))
        : 0.0;

    return Positioned(
      left: c.dx - _kNodeW / 2,
      top: c.dy - _kNodeH / 2,
      child: GestureDetector(
        onTap: () => setState(() => _sel = selected ? null : def.id),
        child: _NodeWidget(
          emoji: def.emoji,
          name: def.name,
          researched: researched,
          available: available,
          canAfford: canAfford,
          selected: selected,
          inProgress: inProgress,
          progress: progress,
          costLabel: inProgress ? _progressLabel(def) : '${def.bpCost} BP',
        ),
      ),
    );
  }

  // Mirrors GameEngine.tick()'s research math exactly: progress is literal
  // elapsed real time while currentEnergy > 0, a hard stop at 0 — never a
  // fractional slowdown, so `energy.fraction` must not appear here. No rate
  // to divide by anymore — remaining seconds map straight to remaining time.
  //
  // Extrapolates forward from the last authoritative tick's anchor (built
  // seconds + energy state as of energy.lastUpdatedAt) using elapsed
  // wall-clock time, so the countdown moves every second on screen instead
  // of jumping once per 5s controller tick. _liveTicker just forces the
  // repaint; it never mutates researchSecondsBuilt itself, so a resync
  // (next controller tick) only changes what's displayed if the real rate
  // actually changed — no drift to catch up on.
  double _researchBuiltNowSeconds(TechDef def) {
    final settlement = _ctrl.settlement!;
    final effectiveSeconds = _ctrl.effectiveResearchSeconds(def);
    final e = _ctrl.energy;
    final rate = (e != null && e.currentEnergy > 0) ? 1.0 : 0.0;
    final anchorTime = e?.lastUpdatedAt ?? DateTime.now().toUtc();
    final elapsed =
        DateTime.now().toUtc().difference(anchorTime).inMilliseconds / 1000.0;
    return (settlement.researchSecondsBuilt + rate * elapsed).clamp(
      0.0,
      effectiveSeconds,
    );
  }

  String _progressLabel(TechDef def) {
    final effectiveSeconds = _ctrl.effectiveResearchSeconds(def);
    if (effectiveSeconds <= 0) return '100% — completing…';
    final built = _researchBuiltNowSeconds(def);
    final remaining = (effectiveSeconds - built).clamp(0.0, effectiveSeconds);
    final pct = ((built / effectiveSeconds) * 100).clamp(0, 100).toInt();
    final e = _ctrl.energy;
    if (e == null) return '$pct% complete';
    if (e.currentEnergy <= 0) return '$pct% — no research energy';
    return '$pct%  ·  ${fmtDuration(remaining)} left';
  }

  // Looks up the EraDef with order == the current era's order + 1, or null
  // if the developer hasn't defined a next era yet (capstone simply doesn't
  // render/select in that case — see _canvas/_detailColumn).
  EraDef? get _nextEra {
    final currentOrder =
        _ctrl.currentEra?.order ?? _ctrl.settlement?.eraIndex ?? 1;
    for (final era in kEraDefs.values) {
      if (era.order == currentOrder + 1) return era;
    }
    return null;
  }

  // Era capstone — advance to the next era. Unlocks once every technology
  // of the CURRENT era has been researched; costs resources (like a
  // building), grants the next era's one-time bonus + permanent effects on
  // advancement (see SettlementController.advanceEra).
  Widget _nextEraNode(List<TechDef> techs, Set<String> unlocked) {
    final next = _nextEra;
    if (next == null) return const SizedBox.shrink();

    final allResearched = techs.every((t) => unlocked.contains(t.id));
    final canAfford =
        allResearched &&
        next.advancementCost.entries.every(
          (e) => (_ctrl.resources?.asMap[e.key] ?? 0) >= e.value,
        );
    final selected = _sel == _kEraCapstoneNodeId;

    return Positioned(
      left: _colX(_hallCol(techs)) - _kNodeW / 2,
      top: _rowY(_hallRow(techs)) - _kNodeH / 2,
      child: GestureDetector(
        onTap: () =>
            setState(() => _sel = selected ? null : _kEraCapstoneNodeId),
        child: _NodeWidget(
          emoji: next.emoji,
          name: 'Advance to ${next.name}',
          researched: false,
          available: allResearched,
          canAfford: canAfford,
          selected: selected,
          costLabel: _costStr(next.advancementCost),
        ),
      ),
    );
  }

  // ── Right detail column ───────────────────────────────────
  Widget _detailColumn() {
    // Responsive width instead of a fixed 200 — scales down on narrow phones
    // (landscape) so the tech tree keeps enough room, but never shrinks so
    // far the panel's own text wraps awkwardly.
    final width = (MediaQuery.sizeOf(context).width * 0.30).clamp(160.0, 220.0);
    return Container(
      width: width,
      decoration: const BoxDecoration(
        gradient: FoE.panelGradient,
        border: Border(left: BorderSide(color: FoE.border, width: 1)),
      ),
      child: _sel == null
          ? _emptyDetail()
          : _sel == _kEraCapstoneNodeId
          ? _nextEraDetail()
          : _techDetail(kTechDefs[_sel!]!),
    );
  }

  Widget _emptyDetail() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('🔬', style: TextStyle(fontSize: 28, color: Colors.black26)),
        const SizedBox(height: 8),
        Text(
          'Tap a technology\nto see details',
          textAlign: TextAlign.center,
          style: FoE.dim().copyWith(color: FoE.textMuted),
        ),
      ],
    ),
  );

  Widget _techDetail(TechDef def) {
    final unlocked = _ctrl.unlockedTechs;
    final researched = unlocked.contains(def.id);
    final activeId = _ctrl.settlement?.activeResearchId;
    final inProgress = activeId == def.id;
    final busyWithOther = !researched && !inProgress && activeId != null;
    final available = def.prerequisites.every(unlocked.contains);
    final canAfford = available && !busyWithOther && _ctrl.bp >= def.bpCost;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Center(child: Text(def.emoji, style: const TextStyle(fontSize: 34))),
          const SizedBox(height: 6),
          Center(
            child: Text(
              def.name,
              style: FoE.title(size: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Center(child: Text('${def.bpCost} BP', style: FoE.dim())),
          FoE.divider(vPad: 10),
          // Description
          Text(
            def.description,
            style: FoE.label(
              size: 11,
            ).copyWith(color: FoE.parchment, height: 1.5),
          ),
          const SizedBox(height: 10),
          // Effects
          ...def.effectLines.map(
            (l) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  const Icon(Icons.chevron_right, color: FoE.gold, size: 13),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      l,
                      style: FoE.label(
                        size: 10.5,
                      ).copyWith(color: FoE.parchment),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Prerequisites not met
          if (!researched && !inProgress && !available) ...[
            const SizedBox(height: 6),
            Text(
              'Requires: ${def.prerequisites.map((p) => kTechDefs[p]?.name ?? p).join(', ')}',
              style: FoE.dim(
                size: 9.5,
              ).copyWith(color: Colors.redAccent.shade100),
            ),
          ],
          // Research slot busy with a different tech
          if (busyWithOther) ...[
            const SizedBox(height: 6),
            Text(
              'Research slot busy — finish '
              '${kTechDefs[activeId]?.name ?? activeId} first',
              style: FoE.dim(
                size: 9.5,
              ).copyWith(color: Colors.redAccent.shade100),
            ),
          ],
          const Spacer(),
          // Action
          if (researched)
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: FoE.gold, size: 16),
                  const SizedBox(width: 6),
                  Text('Researched', style: FoE.label()),
                ],
              ),
            )
          else if (inProgress) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value:
                    (_ctrl.settlement!.researchSecondsBuilt /
                            def.researchSeconds)
                        .clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: FoE.panelDark,
                color: const Color(0xFFFF8C00),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                _progressLabel(def),
                style: FoE.dim().copyWith(color: const Color(0xFFFF8C00)),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: canAfford ? () => _research(def) : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: FoE.btn(active: canAfford),
                  child: Column(
                    children: [
                      Text(
                        'Research',
                        textAlign: TextAlign.center,
                        style: FoE.label().copyWith(
                          color: canAfford ? FoE.goldBright : FoE.textMuted,
                        ),
                      ),
                      Text(
                        '${def.bpCost} BP · ~${fmtDuration(_ctrl.effectiveResearchSeconds(def))}',
                        style: FoE.dim().copyWith(color: FoE.textDim),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _nextEraDetail() {
    final next = _nextEra;
    if (next == null) return _emptyDetail();
    final current = _ctrl.currentEra;
    final techs = _currentEraTechs;
    final allResearched = techs.every(
      (t) => _ctrl.unlockedTechs.contains(t.id),
    );
    final canAfford =
        allResearched &&
        next.advancementCost.entries.every(
          (e) => (_ctrl.resources?.asMap[e.key] ?? 0) >= e.value,
        );

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Text(next.emoji, style: const TextStyle(fontSize: 34))),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Advance to ${next.name}',
              style: FoE.title(size: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              '${current?.name ?? 'Era ${current?.order ?? ''}'} → ${next.name}',
              style: FoE.dim(),
            ),
          ),
          FoE.divider(vPad: 10),
          Text(
            'Completing every technology of ${current?.name ?? 'the current era'} '
            'unlocks the advance into ${next.name}.',
            style: FoE.label(
              size: 11,
            ).copyWith(color: FoE.parchment, height: 1.5),
          ),
          if (!allResearched) ...[
            const SizedBox(height: 10),
            Text(
              'Requires: all ${current?.name ?? 'current era'} technologies researched',
              style: FoE.dim(
                size: 9.5,
              ).copyWith(color: Colors.redAccent.shade100),
            ),
          ],
          const Spacer(),
          Center(
            child: Text(_costStr(next.advancementCost), style: FoE.label()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: canAfford ? _advanceEra : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: FoE.btn(active: canAfford),
                child: Text(
                  'Advance',
                  textAlign: TextAlign.center,
                  style: FoE.label().copyWith(
                    color: canAfford ? FoE.goldBright : FoE.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _advanceEra() async {
    final next = _nextEra;
    if (next == null) return;

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
              Text(
                '${next.emoji}  Advance to ${next.name}',
                style: FoE.title(size: 14),
              ),
              const SizedBox(height: 10),
              Text(_costStr(next.advancementCost), style: FoE.label()),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _dlgBtn('Cancel', () => Navigator.pop(context, false)),
                  _dlgBtn(
                    'Advance',
                    () => Navigator.pop(context, true),
                    gold: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final err = await _ctrl.advanceEra();
      if (mounted && err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: FoE.danger),
        );
      }
    }
  }

  String _costStr(Map<String, double> cost) => cost.entries
      .map((e) {
        final em = e.key == 'wood'
            ? '🪵'
            : e.key == 'stone'
            ? '🪨'
            : e.key;
        return '$em ${e.value.toInt()}';
      })
      .join('   ');

  Future<void> _research(TechDef def) async {
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
              Text('${def.emoji}  ${def.name}', style: FoE.title(size: 14)),
              const SizedBox(height: 10),
              Text(
                'Spend ${def.bpCost} BP to start researching?\n'
                'Takes ~${fmtDuration(_ctrl.effectiveResearchSeconds(def))}; '
                'cannot be cancelled once started.',
                textAlign: TextAlign.center,
                style: FoE.label(),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _dlgBtn('Cancel', () => Navigator.pop(context, false)),
                  _dlgBtn(
                    'Start',
                    () => Navigator.pop(context, true),
                    gold: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      final err = await _ctrl.startResearch(def.id);
      if (mounted && err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: FoE.danger),
        );
      }
    }
  }

  Widget _dlgBtn(String label, VoidCallback onTap, {bool gold = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: FoE.btn(active: gold),
          child: Text(
            label,
            style: FoE.label().copyWith(
              color: gold ? FoE.goldBright : FoE.textDim,
            ),
          ),
        ),
      );
}

// ── Node widget ───────────────────────────────────────────
class _NodeWidget extends StatelessWidget {
  final String emoji, name, costLabel;
  final bool researched, available, canAfford, selected, inProgress;
  final double progress; // 0-1, only meaningful when inProgress

  const _NodeWidget({
    required this.emoji,
    required this.name,
    required this.costLabel,
    required this.researched,
    required this.available,
    required this.canAfford,
    required this.selected,
    this.inProgress = false,
    this.progress = 0,
  });

  // In-progress research gets its own colour, matching the amber "queued
  // construction" tone already used elsewhere in the settlement UI.
  static const _inProgressColor = Color(0xFFFF8C00);

  @override
  Widget build(BuildContext context) {
    final Color topBorder;
    final Color botBorder;
    final List<Color> grad;
    final Color nameColor;

    if (researched) {
      topBorder = FoE.goldBright;
      botBorder = FoE.borderGold;
      grad = [const Color(0xFF3A2C10), const Color(0xFF22180A)];
      nameColor = FoE.goldBright;
    } else if (inProgress) {
      topBorder = _inProgressColor;
      botBorder = const Color(0xFF7A4400);
      grad = [const Color(0xFF3A2A10), const Color(0xFF221808)];
      nameColor = _inProgressColor;
    } else if (available) {
      topBorder = FoE.gold;
      botBorder = FoE.border;
      grad = [FoE.panelMid, FoE.panelDark];
      nameColor = FoE.gold;
    } else {
      topBorder = FoE.border;
      botBorder = const Color(0xFF2A1E08);
      grad = [FoE.panelDark, FoE.bg];
      nameColor = FoE.textMuted;
    }

    return Container(
      width: _kNodeW,
      height: _kNodeH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: grad,
        ),
        // No borderRadius — Flutter forbids it with non-uniform border colors
        border: Border(
          top: BorderSide(
            color: selected ? FoE.goldBright : topBorder,
            width: selected ? 2 : 1.5,
          ),
          left: BorderSide(
            color: selected ? FoE.goldBright : topBorder,
            width: selected ? 2 : 1.5,
          ),
          right: BorderSide(color: botBorder, width: 1.5),
          bottom: BorderSide(color: botBorder, width: 1.5),
        ),
        boxShadow: selected || researched || inProgress
            ? [
                BoxShadow(
                  color: (inProgress ? _inProgressColor : FoE.gold).withValues(
                    alpha: researched ? 0.3 : 0.2,
                  ),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            emoji,
            style: TextStyle(
              fontSize: researched ? 20 : (available || inProgress ? 18 : 14),
              color: researched || available || inProgress
                  ? null
                  : Colors.black26,
            ),
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 9.5).copyWith(
                color: nameColor,
                fontWeight: researched ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 2),
          if (researched)
            const Icon(Icons.check, color: FoE.gold, size: 11)
          else if (inProgress) ...[
            SizedBox(
              width: _kNodeW - 24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: FoE.panelDark,
                  color: _inProgressColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              costLabel,
              style: FoE.dim(size: 7.5).copyWith(color: _inProgressColor),
            ),
          ] else
            Text(
              costLabel,
              style: FoE.dim(
                size: 8.5,
              ).copyWith(color: canAfford ? FoE.parchment : FoE.textMuted),
            ),
        ],
      ),
    );
  }
}

// ── Canvas background painter ─────────────────────────────
class _CanvasBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dark parchment-like background
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF100C06),
    );

    // Subtle grid overlay (very faint, like aged paper)
    final paint = Paint()
      ..color = const Color(0x06C8A030)
      ..strokeWidth = 0.5;
    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_CanvasBgPainter _) => false;
}

// ── Connection line painter ───────────────────────────────
class _LinePainter extends CustomPainter {
  final List<TechDef> techs; // already filtered to the current era
  final Set<String> unlocked;
  final String? selected;

  const _LinePainter({
    required this.techs,
    required this.unlocked,
    this.selected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Edges come straight from each def's own prerequisites — no separate
    // edge list to keep in sync (that used to be kTechEdges, which could
    // drift from the actual prerequisite data; see tech_definitions.dart).
    // Looked up within the (already era-filtered) `techs` list rather than
    // the global kTechDefs, so a dangling/cross-era prerequisite id never
    // draws an edge to an off-canvas node.
    final byId = {for (final t in techs) t.id: t};
    for (final to in techs) {
      for (final fromId in to.prerequisites) {
        final from = byId[fromId];
        if (from == null) continue;
        _drawEdge(canvas, from, to, fromId, to.id);
      }
    }
  }

  void _drawEdge(
    Canvas canvas,
    TechDef from,
    TechDef to,
    String fromId,
    String toId,
  ) {
    final start = Offset(_center(from).dx + _kNodeW / 2, _center(from).dy);
    final end = Offset(_center(to).dx - _kNodeW / 2, _center(to).dy);

    final lit = unlocked.contains(fromId);
    final hi = selected == fromId || selected == toId;

    final lineColor = hi
        ? FoE.parchment.withValues(alpha: 0.7)
        : lit
        ? FoE.gold.withValues(alpha: 0.6)
        : FoE.border.withValues(alpha: 0.6);

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = hi ? 2.0 : 1.5
      ..style = PaintingStyle.stroke;

    // Cubic bezier for smooth bends
    final dx = (end.dx - start.dx) * 0.4;
    canvas.drawPath(
      Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + dx, start.dy, end.dx - dx, end.dy, end.dx, end.dy),
      paint,
    );

    // Arrow head on lit/highlighted lines
    if (lit || hi) {
      final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
      const aLen = 7.0, aHalf = 0.38;
      final p2 =
          end -
          Offset(
            aLen * math.cos(angle - aHalf),
            aLen * math.sin(angle - aHalf),
          );
      final p3 =
          end -
          Offset(
            aLen * math.cos(angle + aHalf),
            aLen * math.sin(angle + aHalf),
          );
      canvas.drawPath(
        Path()
          ..moveTo(end.dx, end.dy)
          ..lineTo(p2.dx, p2.dy)
          ..lineTo(p3.dx, p3.dy)
          ..close(),
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.unlocked != unlocked || old.selected != selected;
}
