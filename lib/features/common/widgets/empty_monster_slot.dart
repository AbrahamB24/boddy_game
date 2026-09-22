import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/pressable.dart';

/// An unfilled monster/egg slot — the "+" tile every picker in the game
/// shows for a place waiting to be filled (team slots, hunt/expedition/
/// caravan seats, workshop posts, breeding parents, the Hatchery's egg slot).
///
/// One shared widget (user 2026-08-30, pointing at the worker-assignment
/// sheet's own empty tile: "überall wo ich solche Boxen habe um Monster
/// hinzuzufügen, diesen Style übernehmen"). Now the building dialog's empty
/// seat (user 2026-09-18: "auch ... wo ich auf eine + Kachel drücke"): a dashed
/// outline with a gold "+", see [EmptySeat].
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
      // The tile reserves its top 17% for the art that pops out of a filled
      // slot's card, so the empty one leaves the same gap to stay lined up
      // with it.
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: box.maxHeight * 0.17),
        child: EmptySeat(radius: 14, label: label),
      ),
    ),
  );
}
