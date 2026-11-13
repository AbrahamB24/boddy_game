import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/voxel_icons.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/ui/game_text.dart';
import '../../../core/ui/scroll_cue.dart';
import '../../common/widgets/monster_tile_grid.dart';
import 'picker_detail_panel.dart';

// The card stage (user 2026-11-11: "mit den Trading Cards arbeiten, überall
// dort wo ein Monster eingesetzt wird"). What every monster picker looks like
// now: the seat on the LEFT (the monster standing in it, or a dashed empty
// seat), the previewed candidate as a card on the RIGHT, a plate between them
// with what the swap does (old → new, green or red), and the whole roster as a
// strip of cards along the bottom. Tapping a card in the strip only previews
// it; the plate's gold button commits, as before ([pickerChooseButton]).

/// One "old → new" line on the stage's plate, with a green/red change chip.
/// [from] null = nothing in the seat yet, so only the new figure shows.
Widget pickerCompareRow(String label, {int? from, required int to}) {
  final d = from == null ? null : to - from;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: FoE.dim(size: 13).copyWith(color: kBoxInkSoft),
          ),
        ),
        if (from != null) ...[
          SizedBox(
            width: 42,
            child: Text(
              '$from',
              textAlign: TextAlign.right,
              style: FoE.value(size: 14).copyWith(color: kBoxInkFaint),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: PixelIcon(Icons.arrow_forward, size: 15, color: kBoxInkSoft),
          ),
        ],
        SizedBox(
          width: 42,
          child: Text(
            '$to',
            style: FoE.value(size: 16).copyWith(color: kBoxInk),
          ),
        ),
        if (d != null && d != 0) _pickerDelta(d),
      ],
    ),
  );
}

Widget _pickerDelta(int d) {
  final c = d > 0 ? CreamPalette.better : const Color(0xFFFF7A66);
  return Container(
    padding: const EdgeInsets.fromLTRB(1, 0, 6, 0),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixelIcon(
          d > 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
          size: 18,
          color: c,
        ),
        Text('${d.abs()}', style: FoE.value(size: 14).copyWith(color: c)),
      ],
    ),
  );
}

/// A plain "label  value" line for the plate (no change to show).
Widget pickerPlateRow(String label, String value, {Color? valueColor}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: FoE.dim(size: 13).copyWith(color: kBoxInkSoft),
            ),
          ),
          Text(
            value,
            style: FoE.value(size: 15).copyWith(color: valueColor ?? kBoxInk),
          ),
        ],
      ),
    );

/// The context strip above the picker grid: a small caps [label] over the
/// [text] (what the post needs, the enemy, the route…), [trailing] on the right
/// (a figure, a progress readout).
Widget pickerBanner(String label, String text, {Widget? trailing}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  decoration: BoxDecoration(
    color: const Color(0xFF0E2A36).withValues(alpha: 0.5),
    borderRadius: vr(10),
    border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.7)),
  ),
  child: Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              style: FoE.label(size: 10).copyWith(color: kBoxInkSoft),
            ),
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.value(size: 14).copyWith(color: kBoxInk),
            ),
          ],
        ),
      ),
      if (trailing != null) trailing,
    ],
  ),
);

class PickerStage extends StatelessWidget {
  /// The monster standing in the seat now, as a [CreatureCard]; null shows the
  /// dashed empty seat.
  final Widget? current;
  final String currentLabel;

  /// The previewed candidate as a [CreatureCard]; null shows an empty frame.
  final Widget? preview;
  final String previewLabel;

  /// The plate's lines (use [pickerCompareRow] / [pickerPlateRow]); null shows
  /// [placeholder].
  final List<Widget>? rows;
  final String? plateTitle;
  final Widget? action;
  final String placeholder;

  /// Every candidate as a card (already wrapped in its tap and frame); the
  /// stage sizes them.
  final List<Widget> tiles;

  /// Search/sort/filter pills above everything.
  final Widget? controls;

  /// Height each tile adds BELOW its card (a caption), so the strip can size
  /// the card to leave room for it.
  final double tileExtra;

  /// Shown in the strip when [tiles] is empty.
  final String emptyText;

  /// False drops the left-hand seat entirely (the screen already shows its
  /// seats elsewhere), giving the plate the room.
  final bool showCurrent;

  /// What the screen needs from the pick (requirement, enemy, route…), shown
  /// above the grid. Null = nothing.
  final Widget? banner;

  const PickerStage({
    this.banner,
    super.key,
    this.current,
    this.currentLabel = 'IN THE SEAT',
    this.preview,
    this.previewLabel = 'NEW',
    this.rows,
    this.plateTitle,
    this.action,
    this.placeholder = 'Tap a card below to see how it changes the seat.',
    required this.tiles,
    this.controls,
    this.tileExtra = 0,
    this.emptyText = 'No monsters.',
    this.showCurrent = true,
  });

  // Layout (user 2026-11-13, mockup "03 Raster + Detail-Seitenleiste"): the
  // roster is a wrapping GRID of cards on the left (scrolls vertically), the
  // right-hand sidebar holds the previewed card (with the seat's current
  // monster as a small card before it), the plate rows and the commit button.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth.isFinite ? box.maxWidth : 700.0;
      final h = box.maxHeight.isFinite ? box.maxHeight : 330.0;
      final sideW = (w * 0.34).clamp(210.0, 340.0);
      final tileW = h < 300 ? 66.0 : 78.0;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                if (banner != null) ...[banner!, const SizedBox(height: 8)],
                if (controls != null) ...[
                  SizedBox(height: 36, child: controls),
                  const SizedBox(height: 8),
                ],
                Expanded(child: _grid(tileW)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(width: sideW, child: _sidebar(sideW, h)),
        ],
      );
    },
  );

  Widget _grid(double tileW) => Container(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: vr(10),
      border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.9)),
    ),
    child: tiles.isEmpty
        ? Center(
            child: Text(
              emptyText,
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
          )
        : ScrollCue(
            axis: Axis.vertical,
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tiles) SizedBox(width: tileW, child: t),
                ],
              ),
            ),
          ),
  );

  Widget _sidebar(double w, double h) {
    const pad = 10.0;
    final hasRows = rows != null;
    final rowsH = hasRows
        ? (plateTitle != null ? 22.0 : 0.0) + rows!.length * 24.0
        : 40.0;
    final actionH = action != null ? 46.0 : 0.0;
    // label 16 + gaps ~ 24.
    final cardAvail = h - 2 * pad - 16 - rowsH - actionH - 24;
    final maxByWidth = showCurrent ? (w - 2 * pad - 30) / 1.7 : w - 2 * pad;
    final cardW = (cardAvail * kMonsterTileAspect).clamp(
      56.0,
      maxByWidth.clamp(56.0, 124.0),
    );
    final cardH = cardW / kMonsterTileAspect;
    final miniW = cardW * 0.7;
    final miniH = miniW / kMonsterTileAspect;
    return Container(
      padding: const EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: const Color(0xFF0E2A36).withValues(alpha: 0.62),
        borderRadius: vr(12),
        border: Border.all(color: CreamPalette.tan.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (showCurrent)
                SizedBox(
                  width: miniW,
                  child: Text(
                    currentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 10).copyWith(color: kBoxInkSoft),
                  ),
                ),
              if (showCurrent) const SizedBox(width: 30),
              Expanded(
                child: Text(
                  previewLabel,
                  maxLines: 1,
                  style: FoE.label(size: 12).copyWith(color: CreamPalette.gold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (showCurrent) ...[
                          SizedBox(
                            width: miniW,
                            height: miniH,
                            child: current != null
                                ? FittedBox(
                                    child: SizedBox(
                                      width: 84,
                                      height: 84 / kMonsterTileAspect,
                                      child: current,
                                    ),
                                  )
                                : Padding(
                                    padding: EdgeInsets.only(top: miniH * 0.17),
                                    child: const EmptySeat(
                                      radius: 10,
                                      label: 'Free',
                                    ),
                                  ),
                          ),
                          SizedBox(
                            width: 30,
                            child: PixelIcon(
                              Icons.arrow_forward,
                              size: 20,
                              color: CreamPalette.gold,
                            ),
                          ),
                        ],
                        preview == null
                            ? SizedBox(
                                width: cardW,
                                height: cardH,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: vr(14),
                                    color: CreamPalette.tan.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                ),
                              )
                            : pickerPreviewFrame(
                                active: true,
                                child: SizedBox(
                                  width: cardW,
                                  height: cardH,
                                  child: preview,
                                ),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!hasRows)
                    Text(
                      placeholder,
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 12).copyWith(color: kBoxInkFaint),
                    )
                  else
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (plateTitle != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                plateTitle!,
                                style: FoE.title(
                                  size: 14,
                                ).copyWith(color: kBoxInk),
                              ),
                            ),
                          ...rows!,
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
