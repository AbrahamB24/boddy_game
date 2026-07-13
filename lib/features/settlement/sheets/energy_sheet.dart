import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../services/game_engine.dart';
import '../settlement_controller.dart';
import 'build_menu_sheet.dart' show fmtDuration;

// Tap target for the Energy header cell — shows the drain estimate (how
// long the current charge lasts) plus the step-logging form that used to
// live in its own quick-menu sheet (StepInputSheet). Steps are the only way
// to refill energy, so keeping "how long is left" and "add more" in the same
// place makes the causal link obvious. Manual entry only for now — the hint
// text below flags that this is meant to be superseded by an automatic step
// tracker integration later, without changing the addSteps contract now.
class EnergySheet extends StatefulWidget {
  final SettlementController ctrl;
  const EnergySheet({super.key, required this.ctrl});

  @override
  State<EnergySheet> createState() => _EnergySheetState();
}

class _EnergySheetState extends State<EnergySheet> {
  final _tc = TextEditingController();
  bool _loading = false;
  Timer? _liveTicker;

  double get _preview => (int.tryParse(_tc.text) ?? 0) * kEnergyPerStep;

  @override
  void initState() {
    super.initState();
    // Energy drains continuously in real time but the controller only
    // resyncs on its 5s-authoritative tick — without this, the "lasts ~Xh"
    // estimate would visibly jump in 5s steps instead of counting down
    // smoothly. Same technique as ResearchScreen's _liveTicker: this timer
    // only forces a repaint, _currentEnergyNow does the extrapolation.
    _liveTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveTicker?.cancel();
    _tc.dispose();
    super.dispose();
  }

  // Mirrors GameEngine.tick()'s energy drain exactly (flat kDrainPerHour,
  // clamped at 0 — never negative) — extrapolated from the last tick's
  // anchor (energy.currentEnergy as of energy.lastUpdatedAt) using elapsed
  // wall-clock time.
  double get _currentEnergyNow {
    final e = widget.ctrl.energy;
    if (e == null) return 0;
    final elapsedHours =
        DateTime.now().toUtc().difference(e.lastUpdatedAt).inMilliseconds /
        3.6e6;
    return (e.currentEnergy - kDrainPerHour * elapsedHours).clamp(
      0.0,
      kMaxEnergy,
    );
  }

  Future<void> _submit() async {
    final steps = int.tryParse(_tc.text.trim());
    if (steps == null || steps <= 0) return;
    setState(() => _loading = true);
    await widget.ctrl.addSteps(steps);
    if (mounted) {
      _tc.clear();
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (context, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: FoE.panelGradient,
            border: Border(top: BorderSide(color: FoE.borderGold, width: 1.5)),
          ),
          child: AnimatedBuilder(
            animation: widget.ctrl,
            builder: (context, _) {
              final current = _currentEnergyNow;
              final isEmpty = current <= 0;
              final hoursLeft = GameEngine.hoursUntilEmpty(current);

              return Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  controller: scrollCtrl,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FoE.borderGold,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Text('⚡', style: TextStyle(fontSize: 20)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Energy', style: FoE.title(size: 16)),
                          ),
                          Text(
                            '${current.toStringAsFixed(0)}/${kMaxEnergy.toStringAsFixed(0)}',
                            style: FoE.value(size: 14).copyWith(
                              color: isEmpty
                                  ? Colors.redAccent
                                  : FoE.goldBright,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (current / kMaxEnergy).clamp(0.0, 1.0),
                          minHeight: 8,
                          color: isEmpty ? Colors.redAccent : FoE.gold,
                          backgroundColor: FoE.panelDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isEmpty
                            ? 'Empty — production, building and research are stalled until you add steps.'
                            : 'Lasts ~${fmtDuration(hoursLeft * 3600)} at the current drain (${kDrainPerHour.toStringAsFixed(1)}/h).',
                        style: FoE.dim(size: 11).copyWith(color: FoE.textDim),
                      ),
                      const SizedBox(height: 16),
                      FoE.divider(vPad: 0),
                      const SizedBox(height: 14),
                      Text('Add steps', style: FoE.title(size: 14)),
                      const SizedBox(height: 2),
                      Text(
                        '100 steps = 1 energy · max ${kMaxEnergy.toStringAsFixed(0)} · '
                        'manual for now, will sync automatically from a step tracker later',
                        style: FoE.dim(size: 10).copyWith(color: FoE.textDim),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [FoE.panelMid, FoE.panelDark],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: FoE.borderGold),
                        ),
                        child: TextField(
                          controller: _tc,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => setState(() {}),
                          style: FoE.value(size: 18),
                          decoration: InputDecoration(
                            hintText: 'e.g. 8 000',
                            hintStyle: FoE.dim(
                              size: 16,
                            ).copyWith(color: FoE.textMuted),
                            suffixText: 'steps',
                            suffixStyle: FoE.label().copyWith(
                              color: FoE.textDim,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      if (_tc.text.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('⚡', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              '+${_preview.toStringAsFixed(1)} energy',
                              style: FoE.label(
                                size: 13,
                              ).copyWith(color: FoE.gold),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: _loading ? null : _submit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: FoE.btn(active: true),
                            child: Center(
                              child: _loading
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: FoE.goldBright,
                                      ),
                                    )
                                  : Text(
                                      'Add Steps',
                                      style: FoE.label(
                                        size: 14,
                                      ).copyWith(color: FoE.goldBright),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
