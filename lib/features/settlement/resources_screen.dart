import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/number_format.dart';
import '../../core/ui/pressable.dart';
import 'data/goods_definitions.dart';
import 'data/resource_icons.dart';
import 'resource_detail_screen.dart';
import 'settlement_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;

/// ALL RESOURCES AT ONE GLANCE — "Epochen-Regale" (user 2026-09-22): one shelf per
/// era, its resources on it as tiles (glyph, stock, rate per hour, a bar of how
/// full the store is). It replaces the eras drop-down under the header, which
/// listed every era's resources as chips; this is the same idea, big enough to
/// carry twenty resources and more without a scroll on a phone.
///
/// GOLD BELONGS TO NO ERA (user 2026-09-22: "Gold ist aber keiner Epoche
/// zugeordnet"), so it stands on a shelf of its own at the top, not on era I's.
///
/// A shelf shows for every era the settlement has reached, and for any later one
/// it already holds something of (a refinery's first output can come early). A
/// tile is the door into that resource's [ResourceDetailScreen].
class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});

  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

/// The eras that get a shelf, each with its resources' ids: Gold first (it
/// belongs to no era — user 2026-09-22), then every era the settlement has
/// reached, plus any later one it already holds something of (a refinery's
/// first output can come early). Shared by [ResourcesScreen] and the
/// header's own resources dropdown (settlement_screen.dart), so "what's
/// currently unlocked" can never drift between the two.
List<({int? era, List<String> ids})> unlockedResourceShelves(
  SettlementController ctrl,
) {
  double amount(String id) => ctrl.resources?.amountOf(id) ?? 0;
  final current = ctrl.dungeonMaxStage;
  return [
    (era: null, ids: const ['gold']),
    for (var r = 1; r <= kMaxRegionOrder; r++)
      if (r <= current || resourceIdsOfRegion(r).any((id) => amount(id) > 0))
        (era: r, ids: resourceIdsOfRegion(r)),
  ];
}

/// "I", "II", … — the eras' own numerals.
String romanNumeral(int n) {
  const numerals = [
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];
  return n >= 1 && n <= numerals.length ? numerals[n - 1] : '$n';
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final _ctrl = SettlementController();

  /// The eras that get a shelf, each with its resources' ids — shared with
  /// the header's own resources dropdown (`settlement_screen.dart`
  /// `_resourcesDropdown`, 2026-09-30), which shows the same "only what is
  /// currently unlocked" set inline instead of navigating here.
  List<({int? era, List<String> ids})> _shelves() =>
      unlockedResourceShelves(_ctrl);

  // The chrome is built once and only the numbers listen (the same rule the
  // resource pages follow): [_ctrl] ticks every few seconds, and rebuilding the
  // whole route on it while a pop transition plays is what once hung the app on
  // a black screen.
  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Resources',
    trailing: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final shelves = _shelves();
        final kinds = shelves.fold<int>(0, (n, s) => n + s.ids.length);
        return Text(
          'Era ${romanNumeral(_ctrl.dungeonMaxStage)} · $kinds kinds',
          style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
        );
      },
    ),
    // No card of its own any more (user 2026-09-30, "hier und andernorts
    // sind noch die alten Kästchen vorhanden") — MenuScaffold is already
    // the one card on screen.
    child: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final shelves = _shelves();
        final current = _ctrl.dungeonMaxStage;
        final rates = _ctrl.hourlyRates;
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            for (final s in shelves) _shelf(s.era, s.ids, current, rates),
          ],
        );
      },
    ),
  );

  /// One shelf: the era's name on the left, its tiles along it.
  Widget _shelf(
    int? era,
    List<String> ids,
    int current,
    Map<String, double> rates,
  ) {
    final isCurrent = era == current;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: CreamPalette.tan.withValues(alpha: 0.4),
            width: 3,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 66,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      era == null ? 'Gold' : romanNumeral(era),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: kBoxInk,
                      ),
                    ),
                    if (isCurrent) ...[
                      const SizedBox(width: 5),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: CreamPalette.gold,
                          shape: BoxShape.rectangle,
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  era == null
                      ? 'any era'
                      : ids.length == 1
                      ? '1 kind'
                      : '${ids.length} kinds',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
                ),
              ],
            ),
          ),
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: i < ids.length
                  ? _tile(ids[i], rates[ids[i]] ?? 0)
                  : const SizedBox.shrink(),
            ),
          ],
        ],
      ),
    );
  }

  /// One resource on the shelf. A full store has a red rim; one with nothing in
  /// it and nothing coming is dimmed.
  Widget _tile(String id, double rate) => ResourceTile(id: id, rate: rate);
}

/// One resource, as a pressable tile — a glyph, its stock, its hourly rate,
/// and (when it has a ceiling) a bar of how full the store is. A full store
/// has a red rim; one with nothing in it and nothing coming is dimmed. Tap
/// opens its [ResourceDetailScreen]. Pulled out of [ResourcesScreen]'s own
/// shelf (2026-09-30) so the header's resources dropdown can show the exact
/// same tile instead of a copy that could drift out of sync with it.
class ResourceTile extends StatelessWidget {
  final String id;
  final double rate;

  const ResourceTile({super.key, required this.id, required this.rate});

  @override
  Widget build(BuildContext context) {
    final ctrl = SettlementController();
    final amount = ctrl.resources?.amountOf(id) ?? 0;
    final cap = ctrl.storageCapacity(id);
    final full = cap > 0 && amount >= cap;
    final empty = amount < 1 && rate <= 0;
    final frac = cap > 0 ? (amount / cap).clamp(0.0, 1.0) : 0.0;
    final rateColor = rate < 0
        ? CreamPalette.warn
        : rate > 0
        ? CreamPalette.better
        : kBoxInkFaint;
    return Opacity(
      opacity: empty ? 0.55 : 1,
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ResourceDetailScreen(
              resourceId: id,
              emoji: resourceEmoji(id),
              title: resourceName(id),
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
          decoration: raisedTile(radius: 10).copyWith(
            border: full
                ? Border.all(color: CreamPalette.warn, width: 1.6)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Text(resourceEmoji(id), style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  Text(
                    shortNumber(amount),
                    style: FoE.value(size: 12.5).copyWith(color: kBoxInk),
                  ),
                  const Spacer(),
                  Text(
                    _rateText(rate),
                    style: FoE.dim(
                      size: 10.5,
                    ).copyWith(color: rateColor, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              if (cap > 0) ...[
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: vr(3),
                  child: SizedBox(
                    height: 6,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: kBoxInk.withValues(alpha: 0.16)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: frac,
                            child: ColoredBox(
                              color: full
                                  ? CreamPalette.warn
                                  : CreamPalette.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "+39.8", "−6", "–" — the hourly rate without its unit (the tile is small).
  static String _rateText(double r) => r == 0
      ? '–'
      : '${r > 0 ? '+' : '−'}${r.abs().toStringAsFixed(r.abs() >= 10 ? 0 : 1)}';
}
