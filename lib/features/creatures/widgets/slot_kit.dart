import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../../common/widgets/recess_bar.dart';
import '../../social/widgets/social_kit.dart';

/// THE SLOT FAMILY (user 2026-09-20, "Variante 2, Slot-Karten"): the Healing Hut,
/// the Combat School and the Hatchery are one page with different nouns — a
/// building with PLACES (beds, practice spots, incubators) and often a LINE,
/// and a grid of everything that could go in.
///
/// Top card: the places as big cards (what is in it, a bar, the time left, one
/// small action), free places dashed, and the line as small chips beside them.
/// Bottom card: everything waiting, as tiles with one button each.
///
/// The parts live here so the three pages cannot drift apart.

/// One place with something in it: a bed with a patient, a desk with a pupil, an
/// incubator with an egg.
class SlotCard extends StatelessWidget {
  static const double width = 196;
  static const double height = 106;

  final Widget avatar;
  final String name;
  final String sub;

  /// 0..1 — how far along.
  final double progress;
  final Color? barColor;

  /// "1m 20s", or "ready" when [ready].
  final String time;

  /// The small action at the bottom right: skip with gold, take back, hatch.
  final Widget? action;

  /// Done and waiting to be collected — a gold rim and a green bar.
  final bool ready;
  final VoidCallback? onTap;

  const SlotCard({
    super.key,
    required this.avatar,
    required this.name,
    required this.sub,
    required this.progress,
    required this.time,
    this.barColor,
    this.action,
    this.ready = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 8),
      decoration: raisedTile(lit: ready),
      child: Column(
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: kBoxInk,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          RecessBar(
            value: ready ? 1 : progress,
            color: ready
                ? CreamPalette.better
                : (barColor ?? CreamPalette.gold),
            height: 10,
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: ready ? CreamPalette.better : kBoxAccent,
                ),
              ),
              const Spacer(),
              ?action,
            ],
          ),
        ],
      ),
    );
    return onTap == null
        ? card
        : Pressable(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: card,
          );
  }
}

/// A place nobody is in, dashed — tapping it says what would go there.
class FreeSlotCard extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const FreeSlotCard({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: SlotCard.width,
      height: SlotCard.height,
      child: CustomPaint(
        painter: const DashedRRectPainter(
          color: CreamPalette.goldDeep,
          radius: 12,
        ),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: CreamPalette.gold.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add, size: 24, color: CreamPalette.goldDeep),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: CreamPalette.goldDeep,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A small pill for the actions inside a card (skip for gold, take back).
class SlotPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool gold;

  const SlotPill(this.label, {super.key, this.onTap, this.gold = false});

  @override
  Widget build(BuildContext context) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: gold ? goldButton() : raisedTile(radius: 9),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: kBoxInk,
          ),
        ),
      ),
    ),
  );
}

/// A small chip for the line: who is waiting, tap to take them out.
class SlotChip extends StatelessWidget {
  final Widget avatar;
  final String name;
  final VoidCallback? onRemove;

  const SlotChip({
    super.key,
    required this.avatar,
    required this.name,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onRemove,
    child: Container(
      height: 30,
      padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
      decoration: raisedTile(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          Text(
            name,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: kBoxInk,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 5),
            Icon(Icons.close, size: 12, color: kBoxInkFaint),
          ],
        ],
      ),
    ),
  );
}

/// Something waiting, as a tile: picture, name, one line, an optional bar, a
/// note (cost · time) and ONE button.
class SlotTile extends StatelessWidget {
  final Widget avatar;
  final String name;
  final String sub;

  /// 0..1 bar under the sub line (a monster's HP), or null.
  final double? bar;
  final Color? barColor;

  /// "🐟 6 · ⏱ 4m".
  final String? note;
  final bool noteWarn;

  final String actionLabel;
  final VoidCallback? onAction;

  /// A gold outline (the egg you arrived with).
  final bool highlighted;

  /// Tapping the tile body (not the button) — details.
  final VoidCallback? onTap;

  const SlotTile({
    super.key,
    required this.avatar,
    required this.name,
    required this.sub,
    required this.actionLabel,
    this.onAction,
    this.bar,
    this.barColor,
    this.note,
    this.noteWarn = false,
    this.highlighted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: raisedTile(lit: highlighted),
      child: Column(
        children: [
          SizedBox(height: 42, child: Center(child: avatar)),
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: kBoxInk,
            ),
          ),
          Text(
            sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
          ),
          if (bar != null) ...[
            const SizedBox(height: 3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: RecessBar(
                value: bar!,
                color: barColor ?? CreamPalette.better,
                height: 6,
              ),
            ),
          ],
          if (note != null) ...[
            const SizedBox(height: 3),
            Text(
              note!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: noteWarn ? CreamPalette.warn : kBoxInkSoft,
              ),
            ),
          ],
          const Spacer(),
          SocialGoldButton(
            actionLabel,
            height: 24,
            fontSize: 11,
            padding: EdgeInsets.zero,
            onTap: onAction,
          ),
        ],
      ),
    ),
  );
}

/// The whole page body: the places on top, everything waiting below.
class SlotFamilyLayout extends StatelessWidget {
  /// The place cards (filled and free), in order.
  final List<Widget> slots;

  /// The line beside them (its own heading and chips), or null.
  final Widget? line;

  /// Extra controls under the places, at the right of the top card (Hatch all).
  final Widget? topTrailing;

  final String tilesTitle;
  final Widget? tilesTrailing;
  final List<Widget> tiles;

  /// Shown in place of the tiles when there are none.
  final Widget? whenNoTiles;

  const SlotFamilyLayout({
    super.key,
    required this.slots,
    required this.tilesTitle,
    required this.tiles,
    this.line,
    this.topTrailing,
    this.tilesTrailing,
    this.whenNoTiles,
  });

  static const double lineWidth = 250;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        creamCard(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < slots.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        slots[i],
                      ],
                    ],
                  ),
                ),
              ),
              if (line != null || topTrailing != null) ...[
                Container(
                  width: 1,
                  height: SlotCard.height,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: CreamPalette.tan.withValues(alpha: 0.4),
                ),
                SizedBox(
                  width: lineWidth,
                  height: SlotCard.height,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (line != null) Expanded(child: line!),
                      if (topTrailing != null) topTrailing!,
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: creamCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: Row(
                    children: [
                      Text(
                        tilesTitle.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: kBoxAccent,
                        ),
                      ),
                      const Spacer(),
                      ?tilesTrailing,
                    ],
                  ),
                ),
                Expanded(
                  child: tiles.isEmpty
                      ? Center(child: whenNoTiles ?? const SizedBox.shrink())
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisExtent: 146,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                          itemCount: tiles.length,
                          itemBuilder: (_, i) => tiles[i],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The heading of the line beside the places, with its count.
Widget slotLineHeading(String label, String count) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Row(
    children: [
      Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: kBoxAccent,
        ),
      ),
      const SizedBox(width: 8),
      Text(
        count,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: kBoxInk,
        ),
      ),
    ],
  ),
);

/// A quiet centred message for "nothing to do".
Widget slotEmptyNote(String title, String body) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 24),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        title,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: kBoxInk,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        body,
        textAlign: TextAlign.center,
        style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
      ),
    ],
  ),
);
