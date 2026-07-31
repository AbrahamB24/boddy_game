import 'package:flutter/material.dart';

/// WHAT THE BARS MEASURE — a two-segment switch over any stat table (user
/// 2026-07-27: "lvl 1 und das Icon sollen klickbar sein. Wenn ich das level up
/// icon anklicke, dann sollen die Balken für dies erscheinen").
///
/// The two captions were labels: "lvl 1" over the starting value and the
/// level-up glyph over the growth per level. Only the first had bars, so the
/// growth column was fourteen numbers to compare by reading — exactly the job
/// the bars exist to save you.
///
/// Now they are the control. It is drawn as a SEGMENTED CONTROL — a bordered
/// track with the live half filled — because a caption that merely changes
/// colour when tapped never looks tappable before the first tap.
///
/// The numbers do not move: both genes stay printed on every row. Only which
/// one the bars are drawn from changes.
class GeneBarToggle extends StatelessWidget {
  /// False = bars show the level-1 value, true = the growth per level.
  final bool showGrowth;
  final ValueChanged<bool> onChanged;

  /// The surface's palette — parchment on the breeding and Hatchery pages,
  /// FoE's dark ink on the monster detail screen.
  final Color ink;
  final Color inkFaint;
  final Color accent;

  const GeneBarToggle({
    super.key,
    required this.showGrowth,
    required this.onChanged,
    required this.ink,
    required this.inkFaint,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 22,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: inkFaint.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segment(
          active: !showGrowth,
          onTap: () => onChanged(false),
          // AN ICON, not "lvl 1" (user 2026-07-27: "Nimm auch ein Icon für die
          // aktuellen stats anstelle von lvl 1") — a bar chart, which is
          // literally what this half draws. Two glyphs also make the pair read
          // as one switch; a word beside an icon read as a label beside a
          // button.
          child: Icon(
            Icons.bar_chart,
            size: 14,
            color: !showGrowth ? accent : inkFaint,
          ),
        ),
        _segment(
          active: showGrowth,
          onTap: () => onChanged(true),
          child: Icon(
            Icons.upgrade,
            size: 13,
            color: showGrowth ? accent : inkFaint,
          ),
        ),
      ],
    ),
  );

  Widget _segment({
    required bool active,
    required VoidCallback onTap,
    required Widget child,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: child,
    ),
  );
}
