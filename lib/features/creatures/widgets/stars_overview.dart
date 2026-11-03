import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart' show ParchmentDialog;
import '../../common/widgets/recess_bar.dart';
import '../services/battle_stars.dart';
import '../services/star_overview.dart';
import 'star_row.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';

/// The whole campaign's stars at a glance (user 2026-09-28: "auf der Map braucht
/// es eine Gesamtübersicht über die erreichten Sterne"): a card per region with
/// its total and every battle's best result, and the rules at the foot.
Future<void> showStarsOverview(
  BuildContext context, {
  required Map<int, int> stars,
  required int battlesCleared,
}) {
  final regions = starOverview(stars: stars, battlesCleared: battlesCleared);
  final totals = starTotals(stars: stars, battlesCleared: battlesCleared);
  return showDialog<void>(
    context: context,
    barrierColor: CreamPalette.dim,
    builder: (_) => ParchmentDialog(
      title: 'Stars',
      maxWidth: 720,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelIcon(Icons.star_rounded, size: 18, color: CreamPalette.gold),
          const SizedBox(width: 3),
          Text(
            '${totals.earned} / ${totals.max}',
            style: FoE.value(size: 14).copyWith(color: kBoxInk),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: StarsOverviewBody(regions: regions),
      ),
    ),
  );
}

/// The list of region cards plus the rules — split out so a test can lay it out
/// without a dialog around it.
class StarsOverviewBody extends StatelessWidget {
  final List<RegionStars> regions;
  const StarsOverviewBody({super.key, required this.regions});

  @override
  Widget build(BuildContext context) {
    final need = (kStarHpFraction * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [for (final r in regions) _region(r)],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '★ win the battle   ★★ no monster knocked out   '
          '★★★ your team keeps $need % of its HP.  '
          'More stars pay more XP, and a star reached for the first time pays '
          'a little gold.',
          style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
        ),
      ],
    );
  }

  Widget _region(RegionStars r) {
    final frac = r.max <= 0 ? 0.0 : r.earned / r.max;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      decoration: raisedTile(radius: 12),
      child: Opacity(
        opacity: r.reached ? 1 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.reached ? r.name : 'Region ${r.region} · not reached yet',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.title(size: 14).copyWith(color: kBoxInk),
                  ),
                ),
                const PixelIcon(
                  Icons.star_rounded,
                  size: 16,
                  color: CreamPalette.gold,
                ),
                const SizedBox(width: 3),
                Text(
                  '${r.earned} / ${r.max}',
                  style: FoE.value(size: 13).copyWith(color: kBoxInk),
                ),
              ],
            ),
            const SizedBox(height: 6),
            RecessBar(value: frac, color: CreamPalette.gold, height: 7),
            if (r.reached) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final b in r.battles) _cell(b)],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(BattleStarsEntry b) => Container(
    width: 46,
    padding: const EdgeInsets.symmetric(vertical: 4),
    decoration: BoxDecoration(
      color: b.cleared
          ? kBoxInk.withValues(alpha: 0.07)
          : kBoxInk.withValues(alpha: 0.03),
      borderRadius: vr(8),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          b.isBoss ? '👑 ${b.battle}' : '${b.battle}',
          style: FoE.value(
            size: 11,
          ).copyWith(color: b.cleared ? kBoxInk : kBoxInkFaint),
        ),
        const SizedBox(height: 1),
        StarRow(count: b.stars, size: 11),
      ],
    ),
  );
}
