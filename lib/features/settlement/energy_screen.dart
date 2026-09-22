import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import 'data/building_definitions.dart';
import 'models/energy_model.dart';
import 'services/step_tracker_service.dart';
import 'settlement_controller.dart';

/// THE ENERGY PAGE — "Batterie" (user 2026-09-22): the pool as a battery of 25
/// cells of 5 % each (amber up to 100 %, cyan above it), what it is worth and how
/// long it lasts, and everything about STEPS: what you have walked, what it takes
/// to fill it, whether the phone is counting, and a short explanation of the
/// rules. It replaces the bottom sheet the header's energy bar used to open.
///
/// Energy is a POOL: steps fill it, time empties it, and every rate in the game is
/// multiplied by it (see [EnergyModel]). All the numbers below come from the same
/// dials the rules run on ([kEnergyFullSteps] and friends), so the page and the
/// game cannot disagree.
class EnergyScreen extends StatelessWidget {
  const EnergyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = SettlementController();
    return MenuScaffold(
      title: '⚡ Energy',
      trailing: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          final e = ctrl.energy;
          if (e == null) return const SizedBox.shrink();
          return Text(
            '${_pct(e.percent)} %'
            '${e.isEmpty ? '' : ' · ${hoursWords(e.hoursLeft)} left'}',
            style: FoE.value(
              size: 14,
            ).copyWith(color: e.isEmpty ? CreamPalette.warn : kBoxInk),
          );
        },
      ),
      child: AnimatedBuilder(
        animation: Listenable.merge([ctrl, StepTrackerService()]),
        builder: (context, _) {
          final energy = ctrl.energy;
          if (energy == null) {
            return creamCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Energy is loading…',
                style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
              ),
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _PoolCard(energy: energy)),
              const SizedBox(width: 12),
              SizedBox(width: 300, child: _StepsCard(energy: energy)),
            ],
          );
        },
      ),
    );
  }

  static String _pct(double p) => p.toStringAsFixed(p < 10 ? 1 : 0);
}

/// "18 h", "5 h 30 min", "45 min" — a countdown in the words a person uses.
String hoursWords(double hours) {
  if (hours.isInfinite) return '∞';
  final totalMin = (hours * 60).round();
  if (totalMin <= 0) return '0 min';
  final h = totalMin ~/ 60;
  final m = totalMin % 60;
  if (h == 0) return '$m min';
  if (m == 0 || h >= 10) return '$h h';
  return '$h h $m min';
}

/// The steps it takes to get the pool from [percent] to [target] (100 or the
/// ceiling), by the rules [energyAfterSteps] runs: 100 / [kEnergyFullSteps]
/// percent a step below 100 %, [kEnergyBoostPerThousandSteps] per 1000 above it.
/// Zero when it is already there.
int stepsToReach(double percent, double target) {
  final lowPerStep = kEnergyFullSteps <= 0 ? 0.0 : 100.0 / kEnergyFullSteps;
  final highPerStep = kEnergyBoostPerThousandSteps * 100.0 / 1000.0;
  var p = percent.clamp(0.0, kEnergyMaxPercent);
  final goal = target.clamp(0.0, kEnergyMaxPercent);
  var steps = 0.0;
  if (p < goal && p < 100 && lowPerStep > 0) {
    final to = goal < 100 ? goal : 100.0;
    steps += (to - p) / lowPerStep;
    p = to;
  }
  if (p < goal && highPerStep > 0) steps += (goal - p) / highPerStep;
  return steps.ceil();
}

// ── The pool: battery, figures ───────────────────────────────────────────────
class _PoolCard extends StatelessWidget {
  final EnergyModel energy;
  const _PoolCard({required this.energy});

  @override
  Widget build(BuildContext context) {
    final pct = energy.percent;
    final full = energy.isFull;
    final empty = energy.isEmpty;
    final toTop = stepsToReach(pct, kEnergyMaxPercent);
    final headline = full
        ? 'Full — steps you take now are lost. They count again as soon as the '
              'energy has dropped a little.'
        : empty
        ? 'Empty. Production and building still run, just at '
              '${(kEnergyFloorMultiplier * 100).round()} % — walk to fill it.'
        : 'Every step you take adds to it right away.';
    return creamCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ENERGY POOL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: kBoxAccent,
            ),
          ),
          const SizedBox(height: 6),
          _Battery(percent: pct),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '${EnergyScreen._pct(pct)} %',
                style: FoE.value(
                  size: 38,
                ).copyWith(color: empty ? CreamPalette.warn : kBoxInk),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  headline,
                  style: FoE.dim(size: 12).copyWith(
                    color: full || empty ? CreamPalette.warn : kBoxInkSoft,
                    fontWeight: full || empty ? FontWeight.w700 : null,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _tile(
                  empty ? '—' : hoursWords(energy.hoursLeft),
                  'until empty',
                  color: empty ? CreamPalette.warn : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tile(
                  '×${energy.multiplier.toStringAsFixed(2)}',
                  'production factor',
                  color: pct > 100 ? _cyanInk : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _tile(
                  toTop <= 0 ? 'Top' : '+${_group(toTop)}',
                  toTop <= 0
                      ? 'the pool is full'
                      : 'steps to the top '
                            '(${kEnergyMaxPercent.round()} %)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String value, String caption, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: raisedTile(radius: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          maxLines: 1,
          style: FoE.value(size: 22).copyWith(color: color ?? kBoxInk),
        ),
        const SizedBox(height: 2),
        Text(caption, style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft)),
      ],
    ),
  );
}

/// The deep cyan the bonus range is written in on cream.
const Color _cyanInk = Color(0xFF1C7FA1);

/// The battery: 25 cells of 5 %, amber up to 100 %, cyan from there to the
/// ceiling, the cell the pool ends in filled to its height, and "100 %" / "125 %"
/// marks above the cells where those lines fall.
class _Battery extends StatelessWidget {
  final double percent;
  const _Battery({required this.percent});

  static const int _cells = 25;

  @override
  Widget build(BuildContext context) {
    final per = kEnergyMaxPercent / _cells;
    final hundredCell = (100 / per).round();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              flex: hundredCell,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '100 %',
                  style: FoE.dim(
                    size: 10,
                  ).copyWith(color: kBoxInkSoft, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            Expanded(
              flex: _cells - hundredCell,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${kEnergyMaxPercent.round()} %',
                  style: FoE.dim(
                    size: 10,
                  ).copyWith(color: _cyanInk, fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBoxInk, width: 3.5),
                    color: kBoxInk.withValues(alpha: 0.05),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _cells; i++) ...[
                        if (i > 0) const SizedBox(width: 3),
                        Expanded(child: _cell(i * per, per)),
                      ],
                    ],
                  ),
                ),
              ),
              // The battery's contact.
              Container(
                width: 11,
                height: 34,
                decoration: BoxDecoration(
                  color: kBoxInk,
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cell(double from, double size) {
    final fill = ((percent - from) / size).clamp(0.0, 1.0);
    final bonus = from >= 100 - 1e-6;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: kBoxInk.withValues(alpha: 0.13)),
          if (fill > 0)
            Align(
              alignment: Alignment.bottomCenter,
              // widthFactor: 1 — without it the Align above loosens the cell's
              // width, the childless DecoratedBox shrinks to nothing and the
              // battery shows no fill at all (user 2026-09-22: "die Füllung der
              // Batterie fehlt noch").
              child: FractionallySizedBox(
                widthFactor: 1,
                heightFactor: fill,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: bonus
                          ? const [Color(0xFFA6ECFF), Color(0xFF2FA9D0)]
                          : const [Color(0xFFFFD46B), Color(0xFFD9921A)],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── The steps ────────────────────────────────────────────────────────────────
class _StepsCard extends StatelessWidget {
  final EnergyModel energy;
  const _StepsCard({required this.energy});

  @override
  Widget build(BuildContext context) {
    final pct = energy.percent;
    final to100 = stepsToReach(pct, 100);
    final toTop = stepsToReach(pct, kEnergyMaxPercent);
    final maxSteps =
        kEnergyFullSteps +
        1000 * (kEnergyMaxBoost / kEnergyBoostPerThousandSteps);
    final maxPct = kEnergyMaxPercent.round();
    return sectionCard(
      title: 'Steps',
      expand: true,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _group(energy.stepsToday),
                style: FoE.value(size: 26).copyWith(color: kBoxInk),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'steps today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _row('To 100 %', to100 <= 0 ? 'reached' : '+${_group(to100)} steps'),
          _row('To $maxPct %', toTop <= 0 ? 'full' : '+${_group(toTop)} steps'),
          const SizedBox(height: 8),
          _syncStatus(),
          const SizedBox(height: 10),
          Container(height: 1, color: CreamPalette.tan.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          _rule(
            '👟',
            '${_group(kEnergyFullSteps.round())} steps fill it from 0 to 100 %. '
                'Every 1 000 after that add '
                '${(kEnergyBoostPerThousandSteps * 100).round()} %, up to $maxPct % '
                '(${_group(maxSteps.round())} steps).',
          ),
          _rule(
            '🗑',
            'Steps at the top are lost. They count again as soon as it has '
                'dropped a little.',
          ),
          _rule(
            '⏳',
            'It runs down by itself: 100 % lasts ${kEnergyFullHours.round()} h, '
                '$maxPct % lasts '
                '${(kEnergyFullHours * maxPct / 100).round()} h.',
          ),
          _rule(
            '🏭',
            'Every production and building rate is multiplied by it. Empty, '
                'the settlement still runs at '
                '${(kEnergyFloorMultiplier * 100).round()} %.',
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(label, style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft)),
        const Spacer(),
        Text(value, style: FoE.value(size: 12.5).copyWith(color: kBoxInk)),
      ],
    ),
  );

  Widget _rule(String emoji, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Text(emoji, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          child: Text(
            text,
            style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft, height: 1.3),
          ),
        ),
      ],
    ),
  );

  /// One status row for the automatic step sync, per tracker state: live (with
  /// the steps credited this session), permission missing (with the actions to
  /// fix it), or no sensor.
  Widget _syncStatus() {
    final tracker = StepTrackerService();
    switch (tracker.status) {
      case StepTrackerStatus.active:
        return Row(
          children: [
            const Icon(
              Icons.directions_walk,
              size: 16,
              color: CreamPalette.better,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Auto-sync active — your phone counts the steps.',
                style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
              ),
            ),
            if (tracker.sessionSteps > 0)
              Text(
                '+${tracker.sessionSteps}',
                style: FoE.value(size: 12).copyWith(color: CreamPalette.better),
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
                  color: CreamPalette.warn,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Step tracking needs the activity permission.',
                    style: FoE.dim(size: 11).copyWith(color: CreamPalette.warn),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Pressable(
                  onTap: () => tracker.start(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: goldButton(),
                    child: Text(
                      'Allow',
                      style: FoE.label(
                        size: 12,
                      ).copyWith(color: goldButtonInk()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // "Don't ask again" on the system dialog silently kills every
                // in-app re-request — settings is the only way back then.
                Pressable(
                  onTap: tracker.openPermissionSettings,
                  child: Text(
                    'Open settings',
                    style: FoE.dim(size: 11).copyWith(
                      color: kBoxAccent,
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
            Icon(Icons.sensors_off, size: 16, color: kBoxInkFaint),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No step sensor available on this device.',
                style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
              ),
            ),
          ],
        );
      case StepTrackerStatus.idle:
        return Text(
          'Step sync starting…',
          style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
        );
    }
  }
}

/// "6 420" — a whole number with a thin gap every three digits.
String _group(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}
