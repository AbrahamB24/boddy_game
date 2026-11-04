import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'road_walkers.dart';

/// The depth map a model with walkways ships beside its picture
/// (tool/blender/depth_pass.py): one grey value per pixel, 0 where the
/// picture is empty, else 1..255 for how far FORWARD the ground under that
/// pixel's surface lies — 1 at the footprint's back corner, 255 at its front
/// corner, i.e. (gx + gy) / (gridW + gridH) of the placed footprint.
String buildingDepthAsset(String artId) =>
    'assets/images/buildings/${artId}_depth.png';

/// A monster walking INSIDE a building (the Castle's yard, user 2026-11-03:
/// "Manchmal sind sie über Gebäuden, obwohl sie dahinter sein sollten"),
/// with every pixel of it ERASED where the building stands in front of its
/// feet.
///
/// The map draws the building, then this. The depth map says, pixel by
/// pixel, how far forward the ground under the building's surface lies; a
/// wall, a tower, a house is a column standing on its own ground, so "its
/// ground is in front of my feet" is exactly "it hides me" — which no split
/// of the picture into slices could get right everywhere.
///
/// Erasing the monster, not redrawing the building over it: a second copy of
/// the picture never matches the cached tile under it exactly (grain,
/// sharpness), and showed as a tinted rectangle wherever a monster walked.
///
/// The mask is a colour matrix, no shader: the depth map's red channel minus
/// the monster's depth, scaled up, becomes alpha, drawn with
/// [BlendMode.dstOut] into a layer holding only the monster.
class BuildingOccluder extends StatefulWidget {
  final String artId;

  /// Where the picture stands on the map: its left edge, its bottom edge and
  /// its width (the same placement the building's tile uses). Its height
  /// is the depth map's aspect: the map is framed exactly like the picture.
  final double left, bottom, width;

  /// The placed footprint.
  final int gridX, gridY, gridW, gridH;

  final RoadWalker walker;
  final RoadWalkers walkers;

  /// The monster itself ([RoadWalkerView]).
  final Widget child;

  const BuildingOccluder({
    super.key,
    required this.artId,
    required this.left,
    required this.bottom,
    required this.width,
    required this.gridX,
    required this.gridY,
    required this.gridW,
    required this.gridH,
    required this.walker,
    required this.walkers,
    required this.child,
  });

  @override
  State<BuildingOccluder> createState() => _BuildingOccluderState();
}

const _isolate = ColorFilter.matrix(<double>[
  1, 0, 0, 0, 0, //
  0, 1, 0, 0, 0, //
  0, 0, 1, 0, 0, //
  0, 0, 0, 1, 0,
]);

class _BuildingOccluderState extends State<BuildingOccluder> {
  ImageStream? _stream;
  ImageStreamListener? _l;
  ui.Image? _depth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(BuildingOccluder old) {
    super.didUpdateWidget(old);
    if (old.artId != widget.artId) _resolve();
  }

  void _resolve() {
    final s = AssetImage(
      buildingDepthAsset(widget.artId),
    ).resolve(createLocalImageConfiguration(context));
    if (s.key == _stream?.key) return;
    _stop();
    _stream = s;
    _l = ImageStreamListener(
      (info, _) {
        if (mounted) setState(() => _depth = info.image);
      },
      // no depth map: the monster is simply drawn whole
      onError: (_, _) {},
    );
    s.addListener(_l!);
  }

  void _stop() {
    if (_l != null) _stream?.removeListener(_l!);
    _stream = null;
    _l = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final depth = _depth;
    if (depth == null) return widget.child;
    return Positioned.fill(
      child: IgnorePointer(
        // A layer of its own, so the eraser below takes out the MONSTER's
        // pixels and nothing of the map under it. A colour filter that
        // changes nothing always gets one; an Opacity of 0.999 rounds to
        // fully opaque and is drawn without (on the web the eraser then cut
        // a dark hole into the map).
        child: ColorFiltered(
          colorFilter: _isolate,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              Positioned.fill(
                child: CustomPaint(
                  painter: _EraserPainter(widget, depth),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EraserPainter extends CustomPainter {
  final BuildingOccluder o;
  final ui.Image depth;

  _EraserPainter(this.o, this.depth) : super(repaint: o.walkers.pulse);

  /// How far in front of the feet (in cells along the depth axis) a surface
  /// must stand to hide the monster: its body has some thickness, and the
  /// wall it walks along must not cut into it.
  static const double _margin = 0.3;

  /// How sharply the mask goes from "behind" to "in front": all of it after
  /// one depth step (a twelfth of a cell on the Castle).
  static const double _ramp = 255;

  @override
  void paint(Canvas canvas, Size size) {
    final w = o.walker;
    final h = o.width * depth.height / depth.width;
    final art = Rect.fromLTWH(o.left, o.bottom - h, o.width, h);
    // The monster's box, generously: its sprite is a little wider than tall
    // and its feet sit three quarters of the way down (road_walkers.dart).
    final foot = RoadWalkers.footOf(w);
    final box = Rect.fromLTWH(
      foot.dx - w.height * 0.7,
      foot.dy - w.height * 0.8,
      w.height * 1.4,
      w.height * 1.0,
    ).intersect(art);
    if (box.isEmpty) return;
    final cells = (o.gridW + o.gridH).toDouble();
    final s = (w.gx + 0.5 - o.gridX) + (w.gy + 0.5 - o.gridY) + _margin;
    final t = 1 + (s / cells).clamp(0.0, 1.0) * 254;
    canvas.save();
    canvas.clipRect(box);
    canvas.drawImageRect(
      depth,
      Rect.fromLTWH(0, 0, depth.width.toDouble(), depth.height.toDouble()),
      art,
      Paint()
        ..blendMode = BlendMode.dstOut
        ..filterQuality = FilterQuality.low
        ..colorFilter = ColorFilter.matrix(<double>[
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          0, 0, 0, 0, 0, //
          _ramp, 0, 0, 0, -_ramp * t,
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.depth != depth || old.o != o;
}
