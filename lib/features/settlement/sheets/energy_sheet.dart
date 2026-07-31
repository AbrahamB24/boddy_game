import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../services/game_engine.dart';
import '../services/step_tracker_service.dart';
import '../settlement_controller.dart';
import '../widgets/parchment_sheet.dart';
import '../widgets/scroll_paper.dart'
    show parchmentButton, parchmentButtonInk;
import '../../../core/ui/duration_format.dart';
import '../../common/widgets/recess_bar.dart';

// Tap target for the Energy header cell — shows the drain estimate (how
// long the current charge lasts) plus the step sync. Steps are the only way
// to refill energy, so keeping "how long is left" and "where steps come from"
// in the same place makes the causal link obvious. Steps now sync
// automatically from the phone's hardware step counter (StepTrackerService,
// user 2026-07-18); the manual entry form remains as a dev-only fallback.
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
    return ParchmentSheet(
      // No icon (user 2026-07-27) — the newer menus name themselves in words.
      title: 'Energy',
      initialSize: 0.55,
      minSize: 0.35,
      maxSize: 0.9,
      trailing: AnimatedBuilder(
        animation: widget.ctrl,
        builder: (context, _) {
          final current = _currentEnergyNow;
          return Text(
            '${current.toStringAsFixed(0)}/${kMaxEnergy.toStringAsFixed(0)}',
            style: FoE.value(size: 14).copyWith(
              color: current <= 0 ? FoE.danger : ParchmentSheet.accent,
            ),
          );
        },
      ),
      builder: (context, scrollCtrl) => AnimatedBuilder(
        animation: Listenable.merge([widget.ctrl, StepTrackerService()]),
        builder: (context, _) {
          final current = _currentEnergyNow;
          final isEmpty = current <= 0;
          final hoursLeft = GameEngine.hoursUntilEmpty(current);

          return SingleChildScrollView(
            controller: scrollCtrl,
            padding: EdgeInsets.only(
              left: 30,
              right: 30,
              top: 4,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecessBar(
                  value: (current / kMaxEnergy).clamp(0.0, 1.0),
                  color: isEmpty ? FoE.danger : ParchmentSheet.accent,
                  height: 12,
                ),
                const SizedBox(height: 8),
                Text(
                  // ENERGY IS A GATE AGAIN (user 2026-07-27): an empty tank
                  // stops everything, so the line names what stops instead of
                  // the old three-item list that predated expeditions,
                  // healing and hatching being gated too.
                  isEmpty
                      ? 'Empty — nothing runs. No production, building, '
                            'expeditions, treatment, breeding or hatching '
                            'until you add steps.'
                      : 'Lasts ~${fmtDuration(hoursLeft * 3600)} at the '
                            'current drain (${kDrainPerHour.toStringAsFixed(1)}/h). '
                            'At zero the settlement stops.',
                  style: FoE.dim(size: 11).copyWith(
                    color: isEmpty ? FoE.danger : ParchmentSheet.inkSoft,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Step sync',
                  style: FoE.title(
                    size: 14,
                  ).copyWith(color: ParchmentSheet.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  '100 steps = 1 energy · max ${kMaxEnergy.toStringAsFixed(0)}',
                  style: FoE.dim(
                    size: 10,
                  ).copyWith(color: ParchmentSheet.inkFaint),
                ),
                const SizedBox(height: 10),
                _syncStatus(),
                if (widget.ctrl.isDev) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Add steps (dev)',
                    style: FoE.title(
                      size: 14,
                    ).copyWith(color: ParchmentSheet.ink),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: ParchmentSheet.card,
                    child: TextField(
                      controller: _tc,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      style: FoE.value(
                        size: 18,
                      ).copyWith(color: ParchmentSheet.ink),
                      cursorColor: ParchmentSheet.accent,
                      decoration: InputDecoration(
                        hintText: 'e.g. 10 000',
                        hintStyle: FoE.dim(
                          size: 16,
                        ).copyWith(color: ParchmentSheet.inkFaint),
                        suffixText: 'steps',
                        suffixStyle: FoE.label().copyWith(
                          color: ParchmentSheet.inkSoft,
                        ),
                        // The row draws its own box; silence every border
                        // state, not just the fallback — see SearchPill.
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  if (_tc.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '+${_preview.toStringAsFixed(1)} energy',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: ParchmentSheet.accent),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _loading ? null : _submit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: parchmentButton(),
                      child: _loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: parchmentButtonInk(),
                              ),
                            )
                          : Text(
                              'Add Steps',
                              style: FoE.label(
                                size: 14,
                              ).copyWith(color: parchmentButtonInk()),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  /// One status row for the automatic step sync, per tracker state: live
  /// (with the steps credited this session), permission missing (with the
  /// actions to fix it), or no sensor.
  Widget _syncStatus() {
    final tracker = StepTrackerService();
    switch (tracker.status) {
      case StepTrackerStatus.active:
        return Row(
          children: [
            const Icon(Icons.directions_walk, size: 16, color: FoE.positive),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Auto-sync active — steps from your phone count in by themselves.',
                style: FoE.dim(
                  size: 11,
                ).copyWith(color: ParchmentSheet.inkSoft),
              ),
            ),
            if (tracker.sessionSteps > 0)
              Text(
                '+${tracker.sessionSteps}',
                style: FoE.value(size: 12).copyWith(color: FoE.positive),
              ),
          ],
        );
      case StepTrackerStatus.permissionDenied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Step tracking needs the activity permission.',
                    style: FoE.dim(
                      size: 11,
                    ).copyWith(color: ParchmentSheet.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                GestureDetector(
                  onTap: () => tracker.start(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: parchmentButton(),
                    child: Text(
                      'Allow',
                      style: FoE.label(
                        size: 12,
                      ).copyWith(color: parchmentButtonInk()),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // "Don't ask again" on the system dialog silently kills every
                // in-app re-request — settings is the only way back then.
                GestureDetector(
                  onTap: tracker.openPermissionSettings,
                  child: Text(
                    'Open settings',
                    style: FoE.dim(size: 11).copyWith(
                      color: ParchmentSheet.accent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      case StepTrackerStatus.unavailable:
        return Row(
          children: [
            Icon(Icons.sensors_off, size: 16, color: ParchmentSheet.inkFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No step sensor available on this device.',
                style: FoE.dim(
                  size: 11,
                ).copyWith(color: ParchmentSheet.inkSoft),
              ),
            ),
          ],
        );
      case StepTrackerStatus.idle:
        return Text(
          'Step sync starting…',
          style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkSoft),
        );
    }
  }
}
