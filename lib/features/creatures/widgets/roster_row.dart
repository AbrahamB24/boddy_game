import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../models/creature_instance.dart';
import 'creature_family.dart' show CreatureAvatar;
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';

/// How a [RosterRow]'s status pill reads: good (free to pick / already on
/// the team), a warning (taken elsewhere / over cap), or simply
/// unavailable (away, K.O., unfit).
enum RosterPillKind { free, warn, no }

/// THE one "pick a monster" row, everywhere a monster or a group is picked
/// (user 2026-10-05, pointing at the team editor: "wirklich überall den
/// gleichen [Monsterpicker] nehmen. Nur die Werte und der linke
/// Gesamtteil ist anders" — worker assignment and the team editor render
/// through this same row; only the values that fill its slots, and
/// whatever sits to the left of the picker on each screen, differ).
/// Face, name, the stat this picker sorts by (bar + number), a status
/// pill, a secondary figure, and an action icon honest about what
/// tapping the row actually does.
class RosterRow extends StatelessWidget {
  final CreatureInstance creature;
  final int statValue;
  final int statMax;
  final String status;
  final RosterPillKind statusKind;
  final String? figureText;
  final Color? figureColor;
  final IconData actionIcon;
  final Color actionColor;
  final Color actionIconColor;
  final bool dimmed;
  final VoidCallback onTap;

  const RosterRow({
    super.key,
    required this.creature,
    required this.statValue,
    required this.statMax,
    required this.status,
    required this.statusKind,
    this.figureText,
    this.figureColor,
    required this.actionIcon,
    this.actionColor = CreamPalette.gold,
    this.actionIconColor = CreamPalette.ink,
    this.dimmed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: dimmed ? 0.6 : 1,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: raisedTile(radius: 11),
          // The fixed columns below used to add up to 380 px — wider than
          // the 378 px a row gets in the Assign Workers roster, so the NAME
          // (the only flexible column) was squeezed to nothing and the row
          // overflowed. Narrow rows now get narrower columns; every row in
          // one list shares a width, so they still line up.
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < 460;
              return Row(
                children: [
                  CreatureAvatar.of(creature, size: 28, showHp: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      creature.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 13).copyWith(color: kBoxInk),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? 72 : 90,
                    child: Row(
                      children: [
                        Expanded(child: _statBar()),
                        const SizedBox(width: 6),
                        Text(
                          '$statValue',
                          style: FoE.value(
                            size: 13,
                          ).copyWith(color: kBoxAccent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: narrow ? 100 : 128,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _statusPill(),
                    ),
                  ),
                  SizedBox(
                    width: narrow ? 58 : 84,
                    child: Text(
                      figureText ?? '—',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.value(size: 12.5).copyWith(
                        color: figureText == null
                            ? kBoxInkFaint
                            : (figureColor ?? CreamPalette.better),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: actionColor,
                      shape: BoxShape.rectangle,
                    ),
                    child: PixelIcon(actionIcon, size: 15, color: actionIconColor),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _statBar() {
    final frac = statMax > 0 ? (statValue / statMax).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: vr(4),
      child: SizedBox(
        height: 7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: kBoxInk.withValues(alpha: 0.16)),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac,
                child: const ColoredBox(color: CreamPalette.gold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusPill() => Container(
    constraints: const BoxConstraints(maxWidth: 128),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: switch (statusKind) {
        RosterPillKind.free => CreamPalette.better.withValues(alpha: 0.18),
        RosterPillKind.warn => CreamPalette.warn.withValues(alpha: 0.18),
        RosterPillKind.no => kBoxInk.withValues(alpha: 0.12),
      },
      borderRadius: vr(9),
    ),
    child: Text(
      status,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        color: switch (statusKind) {
          RosterPillKind.free => CreamPalette.better,
          RosterPillKind.warn => CreamPalette.warn,
          RosterPillKind.no => kBoxInkSoft,
        },
      ),
    ),
  );

  /// The empty-state message every roster picker shares when nothing
  /// matches the current search/filter.
  static Widget emptyState(String text) => Center(
    child: Text(text, style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft)),
  );
}
