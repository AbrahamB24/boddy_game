import 'package:flutter/material.dart';

import '../data/building_art.dart';
import '../data/building_definitions.dart';
import '../data/iso_grid.dart';
import '../data/road_tiles.dart';
import '../models/placed_building.dart';
import '../services/game_engine.dart';
import 'building_icon.dart';
import 'terrain_layer.dart';

/// A read-only rendering of another player's settlement — the "visit a
/// friend's city" screen. Deliberately a SEPARATE widget from [SettlementMap]
/// rather than a `readOnly` flag threaded through it: that widget takes the
/// live, singleton [SettlementController] directly and references it at 34
/// call sites (drag placement, road/build modes, ...) — retrofitting a
/// foreign, view-only settlement through the same controller would risk
/// bleeding a visited city's data into the player's own live state.
///
/// Reuses the same pure projection/art helpers [SettlementMap] does
/// (iso_grid.dart, building_art.dart, road_tiles.dart, [TerrainLayer],
/// [BuildingIcon]) — only the interactive/mutable parts are left out: no
/// drag, no placement ghost, no road/edit mode, no life overlay animation.
class VisitSettlementMap extends StatefulWidget {
  final List<PlacedBuilding> buildings;
  final void Function(PlacedBuilding building, BuildingDef def) onTapBuilding;

  const VisitSettlementMap({
    super.key,
    required this.buildings,
    required this.onTapBuilding,
  });

  @override
  State<VisitSettlementMap> createState() => _VisitSettlementMapState();
}

class _VisitSettlementMapState extends State<VisitSettlementMap> {
  final _txCtrl = TransformationController();
  bool _txInitialized = false;

  @override
  void dispose() {
    _txCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapW = isoCanvasSize.width;
    final mapH = isoCanvasSize.height;
    final buildableRegion = GameEngine.buildableRegionCells(widget.buildings);
    final roadCells = {
      for (final b in widget.buildings)
        if (placedDefOf(b)?.isRoad ?? false)
          roadCellKey(b.gridX, b.gridY),
    };

    // A STORED building (its owner's Umbaumodus tray, mid-rearrange) isn't
    // standing anywhere — a visitor must never see it at its stale spot.
    final tiles = [for (final b in widget.buildings) if (!b.isStored) b]
      ..sort((a, b) {
        final da = placedDefOf(a);
        final db = placedDefOf(b);
        if (da == null || db == null) return 0;
        return isoDrawOrder(
          a.gridX,
          a.gridY,
          da.gridW,
          da.gridH,
          b.gridX,
          b.gridY,
          db.gridW,
          db.gridH,
        );
      });

    return LayoutBuilder(
      builder: (context, constraints) {
        final minScale = minMapScale(
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final maxScale = minScale > kMaxMapZoom ? minScale : kMaxMapZoom;

        if (!_txInitialized) {
          _txInitialized = true;
          final tx = (constraints.maxWidth - mapW * minScale) / 2;
          final ty = (constraints.maxHeight - mapH * minScale) / 2;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _txCtrl.value = mapTransform(minScale, tx, ty);
          });
        }

        return InteractiveViewer(
          constrained: false,
          minScale: minScale,
          maxScale: maxScale,
          boundaryMargin: EdgeInsets.zero,
          transformationController: _txCtrl,
          child: GestureDetector(
            onTapUp: (d) => _handleTap(d.localPosition),
            child: SizedBox(
              width: mapW,
              height: mapH,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: TerrainLayer(buildableRegion: buildableRegion),
                    ),
                  ),
                  for (final b in tiles) _tile(b, roadCells),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(Offset local) {
    if (!isoContains(local)) return;
    final (gx, gy) = screenToGrid(local);
    for (final b in widget.buildings.reversed) {
      final def = placedDefOf(b);
      if (def == null || def.isRoad || def.isBuildPlot || b.isStored) continue;
      if (gx >= b.gridX &&
          gx < b.gridX + def.gridW &&
          gy >= b.gridY &&
          gy < b.gridY + def.gridH) {
        widget.onTapBuilding(b, def);
        return;
      }
    }
  }

  Widget _tile(PlacedBuilding b, Set<int> roadCells) {
    final def = placedDefOf(b);
    if (def == null) return const SizedBox.shrink();
    final iso = isoBounds(b.gridX, b.gridY, def.gridW, def.gridH);
    return Positioned(
      left: iso.left,
      top: iso.top,
      width: iso.width,
      height: iso.height,
      child: Opacity(
        opacity: b.isPaused && b.isComplete ? 0.6 : 1.0,
        child: RepaintBoundary(child: _buildingArt(def, b, roadCells)),
      ),
    );
  }

  Widget _buildingArt(BuildingDef def, PlacedBuilding b, Set<int> roadCells) {
    if (def.isRoad) {
      final mask = roadMask(roadCells, b.gridX, b.gridY);
      return Image.asset(
        roadAsset(mask),
        width: kIsoTileW,
        height: kIsoTileH,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        cacheWidth: 256,
        errorBuilder: (_, _, _) => ColoredBox(color: def.color),
      );
    }
    if (def.isBuildPlot) return const SizedBox.shrink();

    final bounds = isoLocalBounds(def.gridW, def.gridH);
    final box = artBoxOf(def);
    final art = artPlacement(
      bounds,
      baseWidth: box.baseWidth,
      anchorX: box.anchorX,
      lift: box.lift,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The same ground shadow the player's own map gives every building.
        Positioned(
          left: art.left,
          width: art.width,
          bottom: bounds.height - art.bottom,
          child: BuildingGroundShadow(
            imageUrl: def.imageUrl,
            defId: def.artId,
            width: art.width,
            dimmed: !b.isComplete,
          ),
        ),
        Positioned(
          left: art.left,
          width: art.width,
          bottom: bounds.height - art.bottom,
          child: BuildingIcon(
            imageUrl: def.imageUrl,
            defId: def.artId,
            width: art.width,
            anchorBottomOverflowTop: true,
            dimmed: !b.isComplete,
          ),
        ),
      ],
    );
  }
}
