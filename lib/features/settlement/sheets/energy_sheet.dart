import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/foe_theme.dart';
import '../data/building_definitions.dart';
import '../services/step_tracker_service.dart';
import '../settlement_controller.dart';
import '../widgets/parchment_sheet.dart';
import '../widgets/scroll_paper.dart'
    show parchmentButton, parchmentButtonInk;
import '../../common/widgets/recess_bar.dart';
import '../../../core/ui/pressable.dart';

// Tap target for the Energy header cell — shows today's step progress plus
// the step sync. Steps are the only way to raise the rate, so keeping
// "today's progress" and "where steps come from" in the same place makes the
// causal link obvious. Steps sync automatically from the phone's hardware
// step counter (StepTrackerService, user 2026-07-18); the manual entry form
// remains as a dev-only fallback.
//
// ENERGY IS A DAILY-STEPS RATE (user 2026-09-14, replacing the old draining
// pool) — there is no more "how long until it runs out": [stepsToday] only
// ever grows today, resetting at midnight, and [EnergyModel.multiplier]
// reads it fresh every time, no live extrapolation needed (unlike the old
// version of this sheet, which ran its own 1s ticker just to keep a drain
// countdown moving).
class EnergySheet extends StatefulWidget {
  final SettlementController ctrl;
  const EnergySheet({super.key, required this.ctrl});

  @override
  State<EnergySheet> createState() => _EnergySheetState();
}

class _EnergySheetState extends State<EnergySheet> {
  final _tc = TextEditingController();
  bool _loading = false;

  int get _typedSteps => int.tryParse(_tc.text) ?? 0;

  /// What today's total (and rate) would become if the typed steps were
  /// added right now — the dev form's own preview.
  double get _previewMultiplier => energyMultiplierForSteps(
    (widget.ctrl.energy?.stepsToday ?? 0) + _typedSteps,
  );

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final steps = _typedSteps;
    if (steps <= 0) return;
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
          final energy = widget.ctrl.energy;
          final pct = energy?.percent ?? kEnergyFloorMultiplier * 100;
          final atFloor = (energy?.stepsToday ?? 0) <= 0;
          return Text(
            '${pct.round()}%',
            style: FoE.value(size: 14).copyWith(
              color: atFloor ? FoE.danger : ParchmentSheet.accent,
            ),
          );
        },
      ),
      builder: (context, scrollCtrl) => AnimatedBuilder(
        animation: Listenable.merge([widget.ctrl, StepTrackerService()]),
        builder: (context, _) {
          final stepsToday = widget.ctrl.energy?.stepsToday ?? 0;
          final rate = energyMultiplierForSteps(stepsToday);
          final atFloor = stepsToday <= 0;
          // The bar reads as a STEP GOAL — progress toward the 100% target —
          // rather than the rate itself, which is the more motivating framing
          // (and the rate alone can't show "how much further to 100%" once
          // it's already past it in the bonus range).
          final barValue = (stepsToday / kEnergyFullSteps).clamp(0.0, 1.0);
          final stepsToFull = (kEnergyFullSteps - stepsToday)
              .clamp(0, kEnergyFullSteps)
              .round();
          final maxBoostSteps =
              kEnergyFullSteps +
              1000 * (kEnergyMaxBoost / kEnergyBoostPerThousandSteps);

          return SingleChildScrollView(
            controller: scrollCtrl,
            // +16/+16 (2026-09-06): ParchmentSheet's own bands widened from
            // flush-to-edge to a 14px inset/16px wide band.
            padding: EdgeInsets.only(
              left: 46,
              right: 46,
              top: 4,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RecessBar(
                  value: barValue,
                  color: atFloor ? FoE.danger : ParchmentSheet.accent,
                  height: 12,
                ),
                const SizedBox(height: 8),
                Text(
                  '$stepsToday / ${kEnergyFullSteps.round()} steps today · '
                  '${rate == rate.roundToDouble() ? rate.round() : rate.toStringAsFixed(2)}'
                  '× rate',
                  style: FoE.dim(size: 11).copyWith(
                    color: atFloor ? FoE.danger : ParchmentSheet.inkSoft,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stepsToday >= kEnergyFullSteps
                      ? (stepsToday >= maxBoostSteps
                            ? 'Maximum rate reached for today.'
                            : '${(maxBoostSteps - stepsToday).round()} more '
                                  'steps to the max bonus '
                                  '(+${(kEnergyMaxBoost * 100).round()}%).')
                      : '$stepsToFull more steps to 100%. Below that, '
                            'production and building still run — just slower, '
                            'never stopped.',
                  style: FoE.dim(
                    size: 11,
                  ).copyWith(color: ParchmentSheet.inkFaint),
                ),
                const SizedBox(height: 18),
                // 15 / 4 / 11, not 14 / 2 / 10 (2026-08-31 audit) — the
                // same "heading with one caption line under it" shape as
                // settlement_screen.dart's "Today's goals" and the upgrade
                // sheet's "fully upgraded" heading; all three numbers had
                // drifted together here.
                Text(
                  'Step sync',
                  style: FoE.title(
                    size: 15,
                  ).copyWith(color: ParchmentSheet.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  '${kEnergyFullSteps.round()} steps = 100% · up to '
                  '${maxBoostSteps.round()} = ${(100 + kEnergyMaxBoost * 100).round()}% '
                  '· resets at midnight',
                  style: FoE.dim(
                    size: 11,
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
                        hintText: 'e.g. 5 000',
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
                      '→ ${(stepsToday + _typedSteps)} steps today · '
                      '${(_previewMultiplier * 100).round()}% rate',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: ParchmentSheet.accent),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Pressable(
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
                Pressable(
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
                Pressable(
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
