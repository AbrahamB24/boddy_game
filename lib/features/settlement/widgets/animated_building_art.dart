import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../data/building_model.dart';
import 'day_night.dart';
import 'building_icon.dart';
import 'building_life.dart';

/// A building on the MAP whose model has moving parts (user 2026-11-03:
/// "Kleider wiegen sich im Wind, Blumen wanken, Licht flackert").
///
/// Draws three things into one canvas, on [AmbientClock]:
///  1. the base picture — the render with every swaying part CUT OUT
///     (`<id>_base.webp`), so a part that moves never also stands still
///     behind itself;
///  2. each swaying/bobbing part from the building's atlas, leaned about its
///     own pivot;
///  3. the light layers, added on top (BlendMode.plus) with a breathing or
///     flickering strength.
///
/// Everywhere else (build menu, dialogs, an unfinished or paused building)
/// the ordinary still picture is shown through [BuildingIcon] — it still has
/// every part in it.
///
/// Sized like [BuildingIcon] with `anchorBottomOverflowTop`: [width] wide,
/// as tall as the picture's own aspect says.
class AnimatedBuildingArt extends StatefulWidget {
  final String defId;
  final BuildingAnimSpec spec;
  final double width;

  /// Distinct per placed building, so a row of houses never sways in step.
  final int phaseSeed;

  /// The NIGHT-LIGHT pass: draws only the light layers (windows, lanterns)
  /// and only at night, with a halo. The map stacks it ABOVE the night
  /// multiply so lights shine instead of being darkened with everything else.
  final bool lightsOnly;

  const AnimatedBuildingArt({
    super.key,
    required this.defId,
    required this.spec,
    required this.width,
    required this.phaseSeed,
    this.lightsOnly = false,
  });

  /// The base picture's provider, at the same decode width the widget uses —
  /// for the loading screen's precache (a different key would decode twice;
  /// see BuildingIcon.providerFor).
  static ImageProvider baseProvider(
    BuildContext context,
    String defId,
    BuildingAnimSpec spec,
    double width,
  ) {
    final w = BuildingIcon.decodeWidthFor(context, width);
    return ResizeImage.resizeIfNeeded(w, null, AssetImage(spec.baseAsset(defId)));
  }

  static ImageProvider atlasProvider(String defId) =>
      AssetImage(BuildingAnimSpec.atlasAsset(defId));

  @override
  State<AnimatedBuildingArt> createState() => _AnimatedBuildingArtState();
}

class _AnimatedBuildingArtState extends State<AnimatedBuildingArt> {
  ImageStream? _baseStream, _atlasStream;
  ImageStreamListener? _baseL, _atlasL;
  ui.Image? _base, _atlas;
  bool _retained = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_retained) {
      _retained = true;
      AmbientClock.instance.retain();
    } else if (!visible && _retained) {
      _retained = false;
      AmbientClock.instance.release();
    }
    _resolve();
  }

  @override
  void didUpdateWidget(AnimatedBuildingArt old) {
    super.didUpdateWidget(old);
    if (old.defId != widget.defId || old.width != widget.width) _resolve();
  }

  void _resolve() {
    final cfg = createLocalImageConfiguration(context);
    final base = AnimatedBuildingArt.baseProvider(
      context,
      widget.defId,
      widget.spec,
      widget.width,
    ).resolve(cfg);
    if (base.key != _baseStream?.key) {
      if (_baseL != null) _baseStream?.removeListener(_baseL!);
      _baseStream = base;
      _baseL = ImageStreamListener((info, _) {
        if (mounted) setState(() => _base = info.image);
      });
      base.addListener(_baseL!);
    }
    final atlas = AnimatedBuildingArt.atlasProvider(widget.defId).resolve(cfg);
    if (atlas.key != _atlasStream?.key) {
      if (_atlasL != null) _atlasStream?.removeListener(_atlasL!);
      _atlasStream = atlas;
      _atlasL = ImageStreamListener((info, _) {
        if (mounted) setState(() => _atlas = info.image);
      });
      atlas.addListener(_atlasL!);
    }
  }

  @override
  void dispose() {
    if (_baseL != null) _baseStream?.removeListener(_baseL!);
    if (_atlasL != null) _atlasStream?.removeListener(_atlasL!);
    if (_retained) {
      _retained = false;
      AmbientClock.instance.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.width, widget.width * widget.spec.aspect);
    final base = _base;
    if (base == null) return SizedBox.fromSize(size: size);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: size,
          painter: _AnimPainter(
            clock: AmbientClock.instance,
            base: base,
            atlas: _atlas,
            spec: widget.spec,
            seed: widget.phaseSeed,
            lightsOnly: widget.lightsOnly,
          ),
        ),
      ),
    );
  }
}

class _AnimPainter extends CustomPainter {
  final AmbientClock clock;
  final ui.Image base;
  final ui.Image? atlas;
  final BuildingAnimSpec spec;
  final int seed;
  final bool lightsOnly;

  _AnimPainter({
    required this.clock,
    required this.base,
    required this.atlas,
    required this.spec,
    required this.seed,
    this.lightsOnly = false,
  }) : super(repaint: clock);

  static final Paint _img = Paint()..filterQuality = FilterQuality.medium;
  static final Paint _light = Paint()
    ..filterQuality = FilterQuality.medium
    ..blendMode = BlendMode.plus;

  // ── Night lights (lightsOnly) ──
  // Lights are drawn in a pass ABOVE the night multiply, so they are not
  // darkened with the rest of the map and keep their warm colour. Any light
  // layer's brightness becomes lamp-orange (rgb is the sum of the source's
  // channels), and a blurred second draw gives a halo.
  static final ColorFilter _warm = ColorFilter.matrix(<double>[
    0.45, 0.45, 0.45, 0, 0, //
    0.26, 0.26, 0.26, 0, 0, //
    0.08, 0.08, 0.08, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);
  static final ColorFilter _haloGain = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 4, 0, //
  ]);
  static final Paint _haloLayer = Paint()
    ..blendMode = BlendMode.plus
    ..colorFilter = _haloGain;
  static final Paint _haloDraw = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = _warm;
  static double _haloSigma = -1;
  final List<(Rect, Rect, double)> _halo = [];

  void _lit(Canvas canvas, ui.Image a, Rect src, Rect dst, double alpha) {
    _light.color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0));
    canvas.drawImageRect(a, src, dst, _light);
    _halo.add((src, dst, alpha));
  }

  void _paintHalo(Canvas canvas, ui.Image a, double w) {
    if (_halo.isEmpty) return;
    var bounds = _halo.first.$2;
    for (final h in _halo) {
      bounds = bounds.expandToInclude(h.$2);
    }
    final sigma = (w * 0.012).clamp(1.5, 14.0);
    if ((sigma - _haloSigma).abs() > 0.01) {
      _haloSigma = sigma;
      _haloLayer.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      );
    }
    canvas.saveLayer(bounds.inflate(sigma * 3), _haloLayer);
    for (final h in _halo) {
      _haloDraw.color = Color.fromRGBO(
        255, 255, 255, h.$3.clamp(0.0, 1.0));
      canvas.drawImageRect(a, h.$1, h.$2, _haloDraw);
    }
    canvas.restore();
    _halo.clear();
  }

  void _paintLights(Canvas canvas, Size size, double night) {
    final a = atlas;
    if (a == null) return;
    final w = size.width, h = size.height;
    final tb = clock.seconds + (seed % 997) * 0.37;
    _light.colorFilter = _warm;
    for (final L in spec.layers) {
      if (L.kind != AnimKind.glow && L.kind != AnimKind.flicker) continue;
      final src = Rect.fromLTWH(L.sx, L.sy, L.sw, L.sh);
      final dst = Rect.fromLTWH(L.l * w, L.t * h, L.w * w, L.h * h);
      final wave = 2 * math.pi * tb / L.period + L.phase;
      final double k;
      if (L.kind == AnimKind.glow) {
        k = 0.5 + 0.5 * math.sin(wave);
      } else {
        final n =
            math.sin(tb * 7.3 + L.phase) * 0.45 +
            math.sin(tb * 12.9 + L.phase * 2) * 0.35 +
            math.sin(tb * 3.1 + L.phase * 3) * 0.2;
        k = (0.55 + 0.45 * n).clamp(0.0, 1.0);
      }
      // A steady lit window with a slight breath, a lantern with a flicker.
      _lit(canvas, a, src, dst, (0.7 + 0.3 * k) * night);
    }
    _light.colorFilter = null;
    _paintHalo(canvas, a, w);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (lightsOnly) {
      final night = nightK();
      if (night > 0.02) _paintLights(canvas, size, night);
      return;
    }
    final w = size.width, h = size.height;
    canvas.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Offset.zero & size,
      _img,
    );
    final a = atlas;
    if (a == null) return;
    final t = clock.seconds;
    // A per-building offset in time, not just in phase: two houses with the
    // same layers would otherwise lean together all day.
    final tb = t + (seed % 997) * 0.37;
    for (final L in spec.layers) {
      final src = Rect.fromLTWH(L.sx, L.sy, L.sw, L.sh);
      final dst = Rect.fromLTWH(L.l * w, L.t * h, L.w * w, L.h * h);
      final wave = 2 * math.pi * tb / L.period + L.phase;
      switch (L.kind) {
        case AnimKind.sway:
          // A gust on top of the swing: wind is not a metronome.
          final s =
              L.amp * (math.sin(wave) * 0.75 + math.sin(wave * 2.7 + 1.3) * 0.25);
          final px = L.px * w, py = L.py * h;
          canvas
            ..save()
            ..translate(px, py)
            ..transform(_shearX(s))
            ..translate(-px, -py)
            ..drawImageRect(a, src, dst, _img)
            ..restore();
        case AnimKind.bob:
          final dy = L.amp * w * math.sin(wave);
          canvas.drawImageRect(a, src, dst.shift(Offset(0, dy)), _img);
        case AnimKind.glow:
          final k = 0.5 + 0.5 * math.sin(wave);
          _light.color = Color.fromRGBO(255, 255, 255, (L.amp * k).clamp(0, 1));
          canvas.drawImageRect(a, src, dst, _light);
        case AnimKind.flicker:
          // Three incommensurate sines: never repeats visibly, never smooth.
          final n =
              math.sin(tb * 7.3 + L.phase) * 0.45 +
              math.sin(tb * 12.9 + L.phase * 2) * 0.35 +
              math.sin(tb * 3.1 + L.phase * 3) * 0.2;
          final k = (0.55 + 0.45 * n).clamp(0.0, 1.0);
          _light.color = Color.fromRGBO(255, 255, 255, (L.amp * k).clamp(0, 1));
          canvas.drawImageRect(a, src, dst, _light);
      }
    }
  }

  static Float64List _shearX(double s) => Float64List.fromList([
    1, 0, 0, 0, //
    s, 1, 0, 0, //
    0, 0, 1, 0, //
    0, 0, 0, 1, //
  ]);

  @override
  bool shouldRepaint(_AnimPainter old) =>
      old.base != base || old.atlas != atlas || old.spec != spec || old.lightsOnly != lightsOnly;
}
