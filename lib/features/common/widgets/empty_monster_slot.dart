import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';

/// An unfilled monster/egg slot — the "+" tile every picker in the game
/// shows for a place waiting to be filled (team slots, hunt/expedition/
/// caravan seats, workshop posts, breeding parents, the Hatchery's egg slot).
///
/// One shared widget now (user 2026-08-30, pointing at the worker-assignment
/// sheet's own empty tile: "überall wo ich solche Boxen habe um Monster
/// hinzuzufügen, diesen Style übernehmen") — every one of those screens had
/// its own copy of this tile, each independently quoting "the build menu's
/// dead-card style," and they had drifted: most still wear that style's
/// original warm, translucent ink wash, one had already moved to a flat,
/// opaque dark tile. Consolidating them here means the next style change
/// only has to happen once.
///
/// [label] is the caption under the "+" — pass null for a silent tile (the
/// common case when several empty seats sit side by side and only the next
/// one to fill should say anything), or a word ("Add", "Choose") when this
/// tile is the only one, or always names its action.
class EmptyMonsterSlot extends StatelessWidget {
  final VoidCallback onTap;
  final String? label;

  const EmptyMonsterSlot({super.key, required this.onTap, this.label});

  @override
  Widget build(BuildContext context) => Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: LayoutBuilder(
          // The tile reserves its top 17% for the art that pops out of a
          // filled slot's card, so the empty one leaves the same gap to stay
          // lined up with it.
          builder: (context, box) => Padding(
            padding: EdgeInsets.only(top: box.maxHeight * 0.17),
            child: Container(
              decoration: ShapeDecoration(
                color: FoE.panelDark,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.24),
                    blurRadius: 0,
                    offset: const Offset(0, 3),
                  ),
                ],
                shape: FoE.facet(radius: 22),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, size: 24, color: FoE.textMuted),
                  if (label != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      label!,
                      style: FoE.label(size: 11).copyWith(color: FoE.textMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
