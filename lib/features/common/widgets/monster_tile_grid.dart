import 'package:flutter/material.dart';

/// The ONE size every monster-or-resource card tile in the game uses (user
/// 2026-08-31: "Alle solche Kacheln (Monster oder Ressourcen) sollen immer
/// genau gleich hoch sein... genau gleich gross sein wie die Kacheln beim
/// Monstersscreen") — the exact geometry [collection_screen.dart]'s Monsters
/// grid computes: 3 columns, a 24px page margin, 10px gaps, aspect 0.60.
///
/// Read straight off the DEVICE width, not whatever width each screen's own
/// container happens to hand a [LayoutBuilder] — that is what let a dozen
/// screens each compute a slightly different number from a copy of the same
/// formula the moment their own padding, or a bottom sheet's inset, differed
/// from the Monsters screen's by even a couple of pixels. Every grid built
/// through [monsterTileGrid] (or sized via [monsterTileWidth] /
/// [monsterTileHeight] directly) lands on the exact same tile the Monsters
/// screen shows, on that device, full stop.
const int kMonsterTileCols = 3;
const double kMonsterTileSpacing = 10.0;
const double kMonsterTilePageMargin = 24.0;
const double kMonsterTileAspect = 0.60;

/// The shared monster/resource tile width.
///
/// FIXED since the landscape switch (2026-09-18): this used to be a third of
/// the DEVICE width, which was the short axis in portrait. Landscape makes
/// the width the long axis (up to 932px), so the same formula would size a
/// single tile taller than the whole screen. A constant keeps every tile
/// identical everywhere and lets grids auto-flow as many columns as fit
/// ([monsterTileGridDelegate]). [context] is kept so callers didn't change.
double monsterTileWidth(BuildContext context) => kMonsterTileWidth;

/// Landscape-friendly tile width, see [monsterTileWidth].
const double kMonsterTileWidth = 96.0;

/// A grid delegate that flows as many [kMonsterTileWidth]-wide columns as
/// fit, each [monsterTileHeight] tall (plus [extraHeight] for a caption).
SliverGridDelegate monsterTileGridDelegate(
  BuildContext context, {
  double extraHeight = 0,
}) => SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: kMonsterTileWidth + 14,
  mainAxisSpacing: kMonsterTileSpacing,
  crossAxisSpacing: kMonsterTileSpacing,
  mainAxisExtent: monsterTileHeight(context) + extraHeight,
);

double monsterTileHeight(BuildContext context) =>
    monsterTileWidth(context) / kMonsterTileAspect;

/// Lays [tiles] out at the shared size, wrapping to as many per row as the
/// available width fits (ordinarily [kMonsterTileCols], since that width is
/// derived from the SAME page margin the Monsters screen itself uses — a
/// narrower host, a bottom sheet with extra inset, simply fits fewer).
///
/// [alignment] only affects a row shorter than a full one — the battle-prep
/// party grid centres it (user 2026-08-28: "Monsterkacheln bitte
/// zentrieren"); every other caller leaves it at the default, flush left.
Widget monsterTileGrid(
  List<Widget> tiles, {
  WrapAlignment alignment = WrapAlignment.start,
}) => Builder(
  builder: (context) {
    final w = monsterTileWidth(context);
    final h = w / kMonsterTileAspect;
    return Wrap(
      alignment: alignment,
      spacing: kMonsterTileSpacing,
      runSpacing: kMonsterTileSpacing,
      children: [
        for (final t in tiles) SizedBox(width: w, height: h, child: t),
      ],
    );
  },
);
