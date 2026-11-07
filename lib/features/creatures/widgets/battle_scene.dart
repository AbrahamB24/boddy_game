import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/building_icon.dart'
    show castShadowImage, kShadowTint, kShadowOpacity;
import '../models/creature_enums.dart' show CreatureElement;
import 'creature_backdrop.dart';
import 'creature_sprite.dart' show decodeWidthFor;

// ── Der Kampfplatz (user 2026-07-31) ─────────────────────────
// "Jetzt kann der Hintergrund nicht mehr der Typ sein, da es mehrere haben kann.
//  Welche Lösung gibt es?"
//
// It used to be the lead monster's ELEMENT: each half of the field was tiled
// with a fire/water/plant backdrop. That worked while a side was one monster and
// broke the moment a rank could hold three — the tile picked one of the three
// and presented it as the world. Type is a property of a MONSTER, so it went
// where it belongs (the plate each one stands on); the background answers the
// other question instead: WHERE is this fight happening.
//
// The region's own art when it has been uploaded (AreaDef.imageUrl), else the
// era's painted gradient — a fallback that has to look deliberate, because most
// regions will not have art for a long time and "no image yet" must never read
// as "something failed to load".
class BattleScene extends StatelessWidget {
  /// The region's scene art. Null = the era gradient.
  final String? imageUrl;

  /// 1-based era, for the fallback palette. Out-of-range values wrap, so a
  /// ninth era invents no crash.
  final int era;

  const BattleScene({super.key, this.imageUrl, this.era = 1});

  /// Sky/ground pair per era — the chapters read as different WORLDS: a green
  /// valley, then bare stone, then embers, and so on up the ladder.
  static const List<List<Color>> _eraPalette = [
    [Color(0xFF3E6B45), Color(0xFF23331F)], // I   verdant
    [Color(0xFF4E5A63), Color(0xFF23282B)], // II  stone
    [Color(0xFF6B4433), Color(0xFF2B1B16)], // III ember
    [Color(0xFF3F5570), Color(0xFF1B2430)], // IV  tide
    [Color(0xFF5C4A6B), Color(0xFF241D2B)], // V   dusk
    [Color(0xFF6B6242), Color(0xFF2B271B)], // VI  sand
    [Color(0xFF3A6B66), Color(0xFF162B29)], // VII glass
    [Color(0xFF4A4F6B), Color(0xFF1D1F2B)], // VIII crystal
  ];

  static List<Color> paletteFor(int era) =>
      _eraPalette[(era - 1).clamp(0, _eraPalette.length - 1)];

  @override
  Widget build(BuildContext context) {
    final palette = paletteFor(era);
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.first, palette.last],
            ),
          ),
        ),
        if (imageUrl != null)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            // Capped, not native (user 2026-09-06: "performance deutlich
            // verbessern") — this fills the whole arena at StackFit.expand,
            // so its own device-pixel width is the right bound; screen width
            // is the closest thing to that available without a LayoutBuilder.
            cacheWidth: decodeWidthFor(
              context,
              MediaQuery.sizeOf(context).width,
            ),
            // A broken URL leaves the ground below standing rather than a grey
            // box with an icon in it — the fallback IS the design, not an error
            // state, so failing back to it costs nothing.
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          )
        else
          // ── Ein Kampfplatz auf dem Rasen (user request) ──
          // A photographic map texture (tried first) reads as a zoomed-in
          // crop the moment the arena is this small and this tall a strip —
          // no fixed image agrees with every phone's aspect ratio at once.
          // Painted ground does: a lawn with a worn earthen pitch trodden
          // into its middle, sized off the arena's OWN bounds every time, so
          // it always looks like it was made for this fight.
          const _ArenaGround(),
        // The horizon: a band of light across the middle, where the two ranks
        // meet. It gives the field a floor without drawing a line on it, and it
        // is what keeps a photographic region image from swallowing the sprites.
        const _Horizon(),
        // Corner shade, so the nameplates and the log always sit on something
        // darker than themselves whatever the art behind them does.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.1,
                  colors: [Colors.transparent, FoE.bg.withValues(alpha: 0.55)],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The battlefield: a clearing in the SAME forest the settlement map is built
/// on (user 2026-11-04: "mache es im genau gleichen Stil wie die Karte, auf
/// welcher gebaut wird").
///
/// Not repainted by hand: it uses the map's own pictures — the grass swatch,
/// the broadleaf and conifer trees, the stones and the heather/gorse patches
/// (`assets/images/terrain/`) — and throws the trees' and stones' shadows with
/// the map's own [castShadowImage] and tint, so a tree here and a tree on the
/// map are the same object. Only the PLACEMENT is this file's: a tree line
/// behind the enemy rank, stones and flowers at the edges and the middle left
/// open for the fight. Placement is by fractions of the arena's own box, so
/// every phone gets a clearing sized for it.
class _ArenaGround extends StatefulWidget {
  const _ArenaGround();

  @override
  State<_ArenaGround> createState() => _ArenaGroundState();
}

class _ArenaGroundState extends State<_ArenaGround> {
  _ForestArt? _art = _ForestArt.cached;

  @override
  void initState() {
    super.initState();
    if (_art == null) {
      _ForestArt.load().then((art) {
        if (mounted && art != null) setState(() => _art = art);
      });
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _ArenaGroundPainter(_art),
      size: Size.infinite,
    ),
  );
}

/// The map's ground art, loaded once for the life of the app.
class _ForestArt {
  final ui.Image grass;
  final Map<String, ui.Image> props;
  final Map<String, ui.Image> shadows;

  const _ForestArt(this.grass, this.props, this.shadows);

  static _ForestArt? cached;
  static Future<_ForestArt?>? _pending;

  /// key → (file, decode width, shadow depth or null for "casts none"). The
  /// decode widths are about twice the size drawn, so the pictures stay sharp
  /// without holding the 400 px originals.
  static const _files = <String, (String, int, double?)>{
    // Rendered in the buildings' pipeline (tool/blender/make_prop.py); the
    // widths are the files' own, i.e. not resized.
    'tree1': ('prop_broadleaf_m', 300, 0.14),
    'tree2': ('prop_conifer_m', 294, 0.14),
    'stone': ('prop_stone_b', 106, 0.08),
    'flat': ('prop_stone_c', 162, 0.08),
    'boulder': ('prop_stone_d', 108, 0.08),
    'heather': ('prop_flowers_d', 122, null),
    'gorse': ('prop_bush_c', 100, null),
  };

  static Future<_ForestArt?> load() => _pending ??= _build();

  static Future<ui.Image> _decode(String asset, {int? width}) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  static Future<_ForestArt?> _build() async {
    try {
      final grass = await _decode('assets/images/terrain/grass_tile.webp');
      final props = <String, ui.Image>{};
      final shadows = <String, ui.Image>{};
      for (final e in _files.entries) {
        final (file, width, depth) = e.value;
        final image = await _decode(
          'assets/images/terrain/$file.webp',
          width: width,
        );
        props[e.key] = image;
        if (depth != null) {
          final shadow = await castShadowImage(image, groundDepth: depth);
          if (shadow != null) shadows[e.key] = shadow;
        }
      }
      return cached = _ForestArt(grass, props, shadows);
    } catch (_) {
      // Not there: the painter keeps its plain lawn, as the map does.
      _pending = null;
      return null;
    }
  }
}

class _ArenaGroundPainter extends CustomPainter {
  final _ForestArt? art;
  const _ArenaGroundPainter(this.art);

  /// One placed picture: key, foot x and y as fractions of the arena, width as
  /// a fraction of the arena's HEIGHT, mirrored or not.
  static const _scatter = <(String, double, double, double, bool)>[
    // The tree line behind the enemy rank, two depths so it is not a fence.
    ('tree1', 0.02, 0.31, 0.28, false),
    ('tree2', 0.14, 0.29, 0.25, true),
    ('tree1', 0.27, 0.32, 0.27, true),
    ('tree2', 0.40, 0.28, 0.24, false),
    ('tree1', 0.53, 0.32, 0.28, false),
    ('tree2', 0.66, 0.29, 0.25, true),
    ('tree1', 0.79, 0.31, 0.27, true),
    ('tree2', 0.91, 0.29, 0.25, false),
    ('tree1', 1.01, 0.32, 0.28, true),
    // Edge dressing: a tree in the front corners, stones and flower patches.
    ('tree2', -0.01, 1.04, 0.36, false),
    // Stepping stones in the brook (user 2026-11-04: "Bachlauf").
    ('flat', 0.16, 0.555, 0.10, false),
    ('stone', 0.50, 0.565, 0.09, true),
    ('boulder', 0.82, 0.555, 0.10, false),
    ('stone', 0.035, 0.60, 0.10, false),
    ('boulder', 0.955, 0.96, 0.12, false),
    ('heather', 0.09, 0.86, 0.09, false),
    ('gorse', 0.13, 0.90, 0.08, true),
    ('heather', 0.90, 0.66, 0.09, true),
    ('gorse', 0.93, 0.70, 0.08, false),
    ('heather', 0.50, 0.99, 0.08, false),
    ('gorse', 0.07, 0.40, 0.08, true),
  ];

  static const _lawn = Color(0xFF5E9A48);

  // The map's own water and sand (terrain_layer), so the brook is the same
  // water the settlement's coast is made of.
  static const _waterDeep = Color(0xFF2A6188);
  static const _waterMid = Color(0xFF3E85B0);
  static const _waterShallow = Color(0xFF6FBBC4);
  static const _sand = Color(0xFFDCC48C);

  /// The brook across the field, between the enemy's side and mine (user
  /// 2026-11-04, background 4): sand banks, shallows at the edges, a deeper
  /// middle, and blocky ripples — flat hard-edged blocks like the voxel ground
  /// around it, no blur, no anti-aliasing.
  void _paintBrook(Canvas canvas, double w, double h) {
    Paint fill(Color c) => Paint()
      ..isAntiAlias = false
      ..color = c;
    final top = (h * 0.465).roundToDouble();
    final bank = (h * 0.022).roundToDouble();
    final water = (h * 0.105).roundToDouble();
    final u = math.max(2.0, (h / 90).roundToDouble());
    canvas.drawRect(Rect.fromLTWH(0, top - bank, w, bank), fill(_sand));
    canvas.drawRect(Rect.fromLTWH(0, top + water, w, bank), fill(_sand));
    canvas.drawRect(Rect.fromLTWH(0, top, w, water), fill(_waterMid));
    canvas.drawRect(Rect.fromLTWH(0, top, w, water * 0.24), fill(_waterShallow));
    canvas.drawRect(
      Rect.fromLTWH(0, top + water * 0.76, w, water * 0.24),
      fill(_waterShallow),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, top + water * 0.40, w, water * 0.22),
      fill(_waterDeep),
    );
    // Ripples: a fixed seed, so repaints never shimmer.
    final rnd = math.Random(5);
    final light = fill(const Color(0xB3BFE6F5));
    for (var i = 0; i < 26; i++) {
      final rx = (rnd.nextDouble() * w).roundToDouble();
      final ry = (top + u + rnd.nextDouble() * (water - 3 * u)).roundToDouble();
      canvas.drawRect(
        Rect.fromLTWH(rx, ry, u * (4 + rnd.nextInt(5)), u),
        light,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final a = art;
    if (a == null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = _lawn);
      return;
    }
    final w = size.width;
    final h = size.height;

    // The ground: the map's own swatch, tiled. Mirrored at the seams so the
    // repeat leaves no line, at about the zoom the map is usually seen at.
    final k = 0.5 * (h / 360).clamp(0.7, 1.4); // tile density = the original 256 px per cell
    final shader = ImageShader(
      a.grass,
      TileMode.mirror,
      TileMode.mirror,
      Matrix4.diagonal3Values(k, k, 1).storage,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
    _paintBrook(canvas, w, h);

    // Back to front, like the map: a prop lower on the screen is nearer.
    final order = [..._scatter]..sort((p, q) => p.$3.compareTo(q.$3));
    final shadowPaint = Paint()
      ..filterQuality = FilterQuality.low
      ..colorFilter = ColorFilter.mode(
        kShadowTint.withValues(alpha: kShadowOpacity),
        BlendMode.srcIn,
      );
    final picture = Paint()..filterQuality = FilterQuality.medium;

    // Every shadow before any prop: a shadow lies on the ground.
    for (final p in order) {
      final mask = a.shadows[p.$1];
      final image = a.props[p.$1];
      if (mask == null || image == null) continue;
      _draw(canvas, mask, image, p, w, h, shadowPaint);
    }
    for (final p in order) {
      final image = a.props[p.$1];
      if (image == null) continue;
      _draw(canvas, image, image, p, w, h, picture);
    }
  }

  /// Draws [picture] (a prop or its shadow mask, both in the prop's own pixel
  /// grid) anchored by the prop's FOOT, as the map does.
  void _draw(
    Canvas canvas,
    ui.Image picture,
    ui.Image prop,
    (String, double, double, double, bool) p,
    double w,
    double h,
    Paint paint,
  ) {
    final destW = p.$4 * h;
    final unit = destW / prop.width;
    final foot = Offset(p.$2 * w, p.$3 * h);
    final dest = Rect.fromLTWH(
      foot.dx - destW / 2,
      foot.dy - prop.height * unit,
      picture.width * unit,
      picture.height * unit,
    );
    final src = Rect.fromLTWH(
      0,
      0,
      picture.width.toDouble(),
      picture.height.toDouble(),
    );
    if (!p.$5) {
      canvas.drawImageRect(picture, src, dest, paint);
    } else {
      canvas.save();
      canvas.translate(foot.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-foot.dx, 0);
      canvas.drawImageRect(picture, src, dest, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ArenaGroundPainter old) => old.art != art;
}

class _Horizon extends StatelessWidget {
  const _Horizon();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.07),
            Colors.transparent,
          ],
          stops: const [0.36, 0.5, 0.64],
        ),
      ),
    ),
  );
}

/// The PLATFORM a fighter stands on — a slab of ground wearing the monster's
/// own type, with its HP running round the front edge (user 2026-07-31: "der
/// Typ ist so fast nicht ersichtlich, mache wie eine Plattform, Kampfplatz für
/// die Monster" → "das Logo wie bei der monster card in den Hintergrund der
/// Plattform einarbeiten" → "der hp balken wird zum Rand der Plattform, wobei
/// dieser ein Halbkreis bleibt").
///
/// The surface IS the card's: [CreatureBackdrop] paints the same diagonal
/// element gradient and embosses the same type glyph into it, so a monster's
/// platform and its card are the same material. Anything hand-mixed here would
/// drift from the card the first time the card changed.
///
/// Its FRONT EDGE is the health bar — the semicircle facing you, on the slab's
/// own curve. It is the only piece of chrome that can sit on a crowded field
/// without taking space from anything: a straight bar under six monsters is six
/// more rectangles, while the edge of a shape that is already there costs
/// nothing. There is no rim anywhere else: a second stroked arc, however thin,
/// is a second bar to anyone who has not read this file.
///
/// One monster, one platform, which is the whole point: a rank of three can hold
/// three types, and the half-wide tile this replaced could only ever show one.
/// [dim] fades the flanks standing further back.
class TypePodium extends StatelessWidget {
  final CreatureElement element;
  final double width;
  final bool dim;

  /// 0..1 of its health, or null for a platform with nobody on it (previews,
  /// the dev form) — then the whole rim is plain.
  final double? hpFraction;

  /// The bar's colour at this level of health. The battle screen owns that
  /// scale (green → amber → red), so it hands the answer down rather than this
  /// widget inventing a second one.
  final Color hpColor;

  /// Which side the embossed type glyph sits on — true (default) is the
  /// enemy's own podium; the player's own monster mirrors it to the right
  /// (user 2026-08-28: "bei den eigenen Monster das Typicon gespiegelt auf
  /// der rechten Seite").
  final bool watermarkLeft;

  /// The rim's thickness. Thick (5) on the arena's big platforms; the battle's
  /// small monsters ([SockelAvatar]) pass a thinner one so the rim stays a rim.
  final double gauge;

  /// Adds the half-sphere under the disc — only for the big monsters on the
  /// battlefield (user 2026-09-21). The small ones keep the plain disc.
  final bool bowl;

  const TypePodium({
    super.key,
    required this.element,
    required this.width,
    this.dim = false,
    this.hpFraction,
    this.hpColor = const Color(0xFF6FBF73),
    this.watermarkLeft = true,
    this.gauge = _PodiumRim.kGauge,
    this.bowl = false,
  });

  @override
  Widget build(BuildContext context) {
    // FLATTER (user 2026-09-21: "die Kugeln sind flacher" — both ranks): the disc is
    // a quarter of its width high, not a third.
    final height = width * 0.24;
    // A true ellipse: BoxShape.rectangle would draw a circle of the shorter side,
    // which on a wide platform is a coin lying in the middle of it.
    final oval = BorderRadius.all(Radius.elliptical(width / 2, height / 2));
    // THE HALF-SPHERE (user 2026-09-21: "die Halbkugel unter der Scheibe … nur
    // für die Monster auf dem Kampffeld"): a bowl under the disc — the lower half
    // of an ellipse that starts behind the disc and shows below its front edge —
    // so a fighter stands on a rounded pedestal. It hangs BELOW the widget's own
    // box (which stays the disc's size, so the arena's layout does not move) into
    // the gap the arena keeps under every platform.
    // The bowl starts at the disc's widest line, so its top corners sit exactly on
    // the disc's left and right extremes — no corner sticks out beside it.
    final bowlTop = height * 0.5;
    final bowlDepth = height * 0.25;
    final bowlH = height - bowlTop + bowlDepth;
    return Opacity(
      opacity: dim ? 0.72 : 1.0,
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            if (bowl)
              // The bowl and the shadow it casts on the ground.
              Positioned(
                left: 0,
                right: 0,
                top: bowlTop,
                height: bowlH,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.elliptical(width / 2, bowlH),
                    ),
                    color: Color.lerp(element.color, Colors.black, 0.5),
                    boxShadow: [
                      BoxShadow(
                        color: FoE.bg.withValues(alpha: 0.55),
                        blurRadius: 0,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              )
            else
              // The shadow the slab casts. Its own layer because the surface
              // above is clipped, and a clip eats the shadow of the thing it
              // clips.
              //
              // ONE RING ONLY (user 2026-07-31: "gibt es jetzt 2 Balken?"). A
              // second BoxShadow here used to be a halo in the element's own
              // colour — but a coloured glow hugging the edge, next to a
              // coloured rim, is two rings, and the rim is the health bar.
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: oval,
                  boxShadow: [
                    BoxShadow(
                      color: FoE.bg.withValues(alpha: 0.55),
                      blurRadius: 0,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            // THE CARD'S OWN SURFACE — same gradient, same embossed glyph.
            // Watermarked to one SIDE because the monster stands in the middle
            // and would otherwise be standing on its own type symbol —
            // [watermarkLeft] picks which.
            ClipRRect(
              borderRadius: oval,
              child: CreatureBackdrop(
                element: element,
                radius: 0,
                watermarkLeft: watermarkLeft,
                // The platform is a wide, shallow strip, so the glyph is scaled
                // off its SHORT side and needs the boost to fill it the way it
                // fills a card.
                symbolScale: 1.9,
                child: const SizedBox.expand(),
              ),
            ),
            // The light: a bright centre falling off toward the rim, so the top
            // reads as a lit, slightly domed disc (like the Sockel preview). A
            // WASH, not an edge: the dark band that used to sit at the bottom
            // traced the ellipse just inside the rim, which was the other half
            // of "two bars".
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: oval,
                gradient: RadialGradient(
                  center: const Alignment(0, -0.25),
                  radius: 0.85,
                  colors: [
                    Colors.white.withValues(alpha: 0.32),
                    Colors.white.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
            // The health, drawn last so nothing paints over it.
            CustomPaint(
              painter: _PodiumRim(
                hpFraction: hpFraction,
                hpColor: hpColor,
                gauge: gauge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The health bar, drawn on the platform's own curve (user 2026-07-31: "Der HP
/// Balken soll genau die Krümmung haben wie das Podest, so als sähe es aus, als
/// wäre der HP Balken der Rand des Podests" → "lösche den anderen Balken und
/// allgemein den Rand des Podests").
///
/// NOTHING ELSE IS STROKED. The platform used to carry a plain rim all the way
/// round, and a second arc beside the gauge — however thin — is a second bar to
/// anyone who has not read this file. The slab's own edge is where its surface
/// stops; it needs no line to say so, and without one there is exactly one
/// stroked thing on a platform and it means exactly one thing.
///
/// The arc is the FRONT half (0 → π: 0 rad is 3 o'clock and positive sweeps
/// clockwise, so that is the half facing the player), on the ellipse the
/// platform itself is cut to — deflated by half its own width, which puts the
/// stroke's outer edge on the slab's edge. That is what makes it read as the
/// rim rather than as a bar lying on top.
class _PodiumRim extends CustomPainter {
  final double? hpFraction;
  final Color hpColor;
  final double gauge;

  const _PodiumRim({
    required this.hpFraction,
    required this.hpColor,
    this.gauge = kGauge,
  });

  static const double _front = 3.1415926535897932;

  /// Thick on purpose (user 2026-07-31: "dafür dicker machen, damit er besser
  /// ersichtlich ist") — it is the only gauge each monster has now that the
  /// straight bar under the name is gone.
  static const double kGauge = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final frac = hpFraction;
    // Nobody standing here: nothing to report, so nothing is drawn.
    if (frac == null) return;

    final path = (Offset.zero & size).deflate(gauge / 2);
    Paint stroke(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = c
      ..strokeWidth = gauge;

    // ── NO EMPTY TRACK (user 2026-08-04) ──
    // There used to be a dark arc across the whole front, with the coloured
    // fill drawn on top of it. Its round cap sat just past the end of the fill
    // and read as a stray dot trailing every health bar on the field — six of
    // them at once. The argument for keeping it was that a half-full bar needs
    // something to be read against, but the PLATFORM is that something: the
    // rim follows the slab's own edge, so how far short of the corner the
    // colour stops is exactly the reading.
    final v = frac.clamp(0.0, 1.0);
    if (v <= 0) return;
    // Filled from the LEFT end so it drains to the right the way every other bar
    // in the game does. Sweeping backwards from π is what puts the start on the
    // left.
    canvas.drawArc(path, _front, -_front * v, false, stroke(hpColor));
  }

  @override
  bool shouldRepaint(_PodiumRim old) =>
      old.hpFraction != hpFraction ||
      old.hpColor != hpColor ||
      old.gauge != gauge;
}
