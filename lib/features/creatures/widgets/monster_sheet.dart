import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One animation inside a baked sprite sheet (tool/blender/monster_anim_pro.py
/// and monster_walk.py write them): [frames] cells laid out left-to-right,
/// top-to-bottom, [cols] per row, every cell [MonsterSheetSet.frameW] x
/// [MonsterSheetSet.frameH]. [loop] false = plays once and holds the last
/// frame until the caller switches back.
class SheetAnim {
  final String asset;
  final int frames;
  final int fps;
  final bool loop;
  const SheetAnim(this.asset, this.frames, this.fps, {this.loop = true});
}

/// Everything one creature view needs: its animations by name ('idle',
/// 'attack', 'hurt', 'walk') and the cell size they share.
class MonsterSheetSet {
  final double frameW;
  final double frameH;
  final int cols;
  final Map<String, SheetAnim> anims;

  /// The fraction of its own resolution a sheet is DECODED at. The map
  /// walkers are drawn ~50 px tall from 435 px frames, so their sheets decode
  /// at half size — a quarter of the texture memory, still sharp at the map's
  /// closest zoom. [frameW]/[frameH] stay in the source's own pixels; the
  /// painter scales its cell rects to whatever size the image really has.
  final double decodeScale;

  /// How much larger than the pup this creature is DRAWN (an evolution is
  /// bigger and mightier). Multiplies the player's ill, capped so the art
  /// never leaves its box.
  final double scale;

  const MonsterSheetSet({
    required this.frameW,
    required this.frameH,
    this.cols = 8,
    required this.anims,
    this.decodeScale = 1,
    this.scale = 1,
  });

  double get aspect => frameW / frameH;
}

/// Which creatures have baked, animated 3D sprites. Everything else keeps its
/// flat network PNG, so a species can move over one at a time.
abstract final class MonsterSheets {
  static const String _t = 'assets/images/monsters/tidelord';

  static const MonsterSheetSet _tidelordFront = MonsterSheetSet(
    frameW: 560,
    frameH: 448,
    anims: {
      'idle': SheetAnim('$_t/front_idle.webp', 16, 12),
      'attack': SheetAnim('$_t/front_attack.webp', 14, 16, loop: false),
      'hurt': SheetAnim('$_t/front_hurt.webp', 10, 14, loop: false),
    },
  );
  static const MonsterSheetSet _tidelordBack = MonsterSheetSet(
    frameW: 560,
    frameH: 448,
    anims: {
      'idle': SheetAnim('$_t/back_idle.webp', 16, 12),
      'attack': SheetAnim('$_t/back_attack.webp', 14, 16, loop: false),
      'hurt': SheetAnim('$_t/back_hurt.webp', 10, 14, loop: false),
    },
  );

  /// Evolutions: Oceanking (stage 1) and Abyssal Titan (stage 2). Same sheet
  /// layout as the pup, own folders.
  static MonsterSheetSet _evo(int stage, bool back, double scale) {
    final d = 'assets/images/monsters/tidelord_s$stage';
    final v = back ? 'back' : 'front';
    return MonsterSheetSet(
      frameW: 560,
      frameH: 448,
      scale: scale,
      anims: {
        'idle': SheetAnim('$d/${v}_idle.webp', 16, 12),
        'attack': SheetAnim('$d/${v}_attack.webp', 14, 16, loop: false),
        'hurt': SheetAnim('$d/${v}_hurt.webp', 10, 14, loop: false),
      },
    );
  }

  static final MonsterSheetSet _oceankingFront = _evo(1, false, 1.2);
  static final MonsterSheetSet _oceankingBack = _evo(1, true, 1.2);
  static final MonsterSheetSet _titanFront = _evo(2, false, 1.4);
  static final MonsterSheetSet _titanBack = _evo(2, true, 1.4);

  /// The SIDE-VIEW battle sheets (user 2026-11-04: my monsters stand at the left
  /// of the field, the enemy's at the right, facing each other). Baked per side
  /// - sidel faces right, sider faces left - rather than mirrored, so the sun
  /// stays upper-left on both.
  static MonsterSheetSet _side(int stage, bool mine, double scale) {
    final d = stage == 0 ? _t : '${_t}_s$stage';
    final v = mine ? 'sidel' : 'sider';
    return MonsterSheetSet(
      frameW: 560,
      frameH: 448,
      scale: scale,
      anims: {
        'idle': SheetAnim('$d/${v}_idle.webp', 16, 12),
        'attack': SheetAnim('$d/${v}_attack.webp', 14, 16, loop: false),
        'hurt': SheetAnim('$d/${v}_hurt.webp', 10, 14, loop: false),
      },
    );
  }

  static final List<MonsterSheetSet> _sideMine = [
    _side(0, true, 1.0),
    _side(1, true, 1.2),
    _side(2, true, 1.4),
  ];
  static final List<MonsterSheetSet> _sideTheirs = [
    _side(0, false, 1.0),
    _side(1, false, 1.2),
    _side(2, false, 1.4),
  ];

  /// Battle art for the side-view field: [mine] stands at the left facing right,
  /// the enemy at the right facing left. Null when the creature has none.
  static MonsterSheetSet? battleSide(
    String? speciesId,
    int stage, {
    required bool mine,
  }) {
    if (speciesId != 'tidelord' || stage < 0 || stage > 2) return null;
    return (mine ? _sideMine : _sideTheirs)[stage];
  }

  /// The map headings, named by the screen direction of the world axis they
  /// walk along: se = +x, ne = +y, nw = -x, sw = -y.
  ///
  /// All three stages share one frame size; the evolutions fill it like the
  /// pup does, and [MonsterSheetSet.scale] draws them bigger on the map (a
  /// little less than in battle, so the roads do not look crowded).
  static Map<String, MonsterSheetSet> _walkSets(int stage, double scale) {
    final d = stage == 0 ? _t : '${_t}_s$stage';
    return {
      for (final h in const ['se', 'ne', 'nw', 'sw'])
        h: MonsterSheetSet(
          // The evolutions' frame rounds one pixel smaller (see monster_walk.py).
          frameW: stage == 0 ? 544 : 543,
          frameH: stage == 0 ? 435 : 434,
          decodeScale: 0.5,
          scale: scale,
          anims: {
            'walk': SheetAnim('$d/${h}_walk.webp', 8, 10),
            'idle': SheetAnim('$d/${h}_idle.webp', 8, 8),
          },
        ),
    };
  }

  static final List<Map<String, MonsterSheetSet>> _tidelordMap = [
    _walkSets(0, 1.0),
    _walkSets(1, 1.15),
    _walkSets(2, 1.3),
  ];

  /// Battle art for a creature, or null when it has none (-> flat sprite).
  /// [back] is the player's own monster seen from behind.
  static MonsterSheetSet? battle(
    String? speciesId,
    int stage, {
    required bool back,
  }) {
    if (speciesId == 'tidelord') {
      return switch (stage) {
        0 => back ? _tidelordBack : _tidelordFront,
        1 => back ? _oceankingBack : _oceankingFront,
        2 => back ? _titanBack : _titanFront,
        _ => null,
      };
    }
    return null;
  }

  /// The baked art standing in for a creature's flat network sprite, found by
  /// the sprite's URL — so every screen that draws a species' picture (lists,
  /// cards, detail, battle) switches over with no change of its own. Null when
  /// the URL is not one of ours. [back] is the back-view sprite.
  static ({MonsterSheetSet set, bool back})? forUrl(String? url) {
    if (url == null) return null;
    if (url.contains('creature-images/tidelord_0_back.png')) {
      return (set: _tidelordBack, back: true);
    }
    if (url.contains('creature-images/tidelord_0.png')) {
      return (set: _tidelordFront, back: false);
    }
    if (url.contains('creature-images/tidelord_1_back.png')) {
      return (set: _oceankingBack, back: true);
    }
    if (url.contains('creature-images/tidelord_1.png')) {
      return (set: _oceankingFront, back: false);
    }
    if (url.contains('creature-images/tidelord_2_back.png')) {
      return (set: _titanBack, back: true);
    }
    if (url.contains('creature-images/tidelord_2.png')) {
      return (set: _titanFront, back: false);
    }
    return null;
  }

  /// Map-walking art for a creature heading [heading] ('se', 'ne', 'nw',
  /// 'sw'), or null — what the road walkers ask for.
  static MonsterSheetSet? map(String? speciesId, int stage, String heading) {
    if (speciesId == 'tidelord' && stage >= 0 && stage < _tidelordMap.length) {
      return _tidelordMap[stage][heading];
    }
    return null;
  }
}

/// Decoded sheets, kept for the life of the app: a sheet is one image, so ten
/// monsters sharing a species decode it once.
final Map<String, Future<ui.Image>> _sheetImages = {};

/// The same sheets once decoded, for a synchronous look-up.
final Map<String, ui.Image> _sheetDone = {};

/// [width] is the decoded width wanted (null = the file's own); the height
/// follows the aspect. Keyed by it, so a full-size and a reduced decode of
/// one file never stand in for each other.
Future<ui.Image> _loadSheet(String asset, {int? width}) {
  final key = width == null ? asset : '$asset@$width';
  return _sheetImages.putIfAbsent(key, () async {
    final data = await rootBundle.load(asset);
    // instantiateImageCodec's targetWidth, not ImageDescriptor: the latter is
    // not implemented on web, where it failed silently and the walkers had no
    // picture at all (2026-11-03).
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: width,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return _sheetDone[key] = frame.image;
  });
}

/// The decode width [set] asks for, or null for the file's own.
int? _decodeWidthOf(MonsterSheetSet set) => set.decodeScale == 1
    ? null
    : (set.cols * set.frameW * set.decodeScale).round();

/// Decodes every map-walking sheet of [speciesId] at [stage], so a walker on
/// the settlement map never turns a corner onto a heading whose picture is
/// still loading. Never throws.
Future<void> precacheMonsterWalkSheets(String speciesId, int stage) =>
    Future.wait([
      for (final heading in const ['se', 'ne', 'nw', 'sw'])
        if (MonsterSheets.map(speciesId, stage, heading) case final set?)
          for (final anim in set.anims.values)
            _loadSheet(anim.asset, width: _decodeWidthOf(set)).then<void>(
              (_) {},
              onError: (Object _) {},
            ),
    ]).then<void>((_) {});

/// Decodes every BATTLE sheet up front (user 2026-11-03: "alle Assets beim
/// Ladescreen vorladen"). Lists, cards and battles all draw from these, and a
/// sheet decoded on demand left the first attack or hit of a fight playing
/// against the previous animation's picture until its own one arrived. The
/// map-walking sheets are not loaded: nothing on the map walks yet (see
/// [MonsterSheets.map]). Never throws.
Future<void> precacheMonsterSheets() => Future.wait([
  for (final set in [MonsterSheets._tidelordFront, MonsterSheets._tidelordBack])
    for (final anim in set.anims.values)
      _loadSheet(anim.asset).then<void>((_) {}, onError: (Object _) {
        _sheetImages.remove(anim.asset);
      }),
]);

/// Plays one named animation of a [MonsterSheetSet].
///
/// It draws into a box [height] tall that matches how the flat sprite it
/// replaces sits there: the creature art occupies [fill] of the height and
/// stands [lift] above the bottom edge, so swapping a species over does not
/// move or resize it on screen. Smooth filtering, not the pixel-art
/// `FilterQuality.none` of the flat sprites — this art is rendered 3D.
class MonsterSheetPlayer extends StatefulWidget {
  final MonsterSheetSet set;
  final String anim;
  final double height;

  /// 0..1 tint toward [flashColor] (the hit flash the flat sprites use).
  final double flash;
  final Color flashColor;
  final double fill;
  final double lift;

  /// False = show the first frame and never tick (thumbnails, long lists).
  final bool animate;

  const MonsterSheetPlayer({
    super.key,
    required this.set,
    this.anim = 'idle',
    required this.height,
    this.flash = 0,
    this.flashColor = Colors.white,
    this.fill = 0.70,
    this.lift = 0.042,
    this.animate = true,
  });

  @override
  State<MonsterSheetPlayer> createState() => _MonsterSheetPlayerState();
}

class _MonsterSheetPlayerState extends State<MonsterSheetPlayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  ui.Image? _image;
  String? _loading;
  Duration _now = Duration.zero;
  Duration _t0 = Duration.zero;

  SheetAnim get _anim =>
      widget.set.anims[widget.anim] ?? widget.set.anims['idle']!;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.animate) _ticker.start();
    _ensureImage();
  }

  @override
  void didUpdateWidget(MonsterSheetPlayer old) {
    super.didUpdateWidget(old);
    if (old.animate != widget.animate) {
      if (widget.animate && !_ticker.isActive) _ticker.start();
      if (!widget.animate && _ticker.isActive) _ticker.stop();
    }
    if (old.anim != widget.anim || old.set != widget.set) {
      _t0 = _now; // a new animation starts from its first frame
      _frame.value = 0;
      _ensureImage();
    }
  }

  void _ensureImage() {
    final asset = _anim.asset;
    if (_loading == asset) return;
    _loading = asset;
    final width = _decodeWidthOf(widget.set);
    // Already decoded: switch in THIS frame. Waiting a microtask for the
    // future drew the new animation's frame numbers on the old sheet for a
    // frame — a visible flicker each time a walker turns a corner.
    final ready = _sheetDone[width == null ? asset : '$asset@$width'];
    if (ready != null) {
      _image = ready;
      return;
    }
    _loadSheet(asset, width: width).then((img) {
      if (!mounted || _loading != asset) return;
      setState(() => _image = img);
    }, onError: (_) {});
  }

  void _tick(Duration elapsed) {
    _now = elapsed;
    final a = _anim;
    final n = ((elapsed - _t0).inMicroseconds * a.fps / 1e6).floor();
    final idx = a.loop ? n % a.frames : (n < a.frames ? n : a.frames - 1);
    if (idx != _frame.value) _frame.value = idx;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final set = widget.set;
    final fill = (widget.fill * set.scale).clamp(0.0, 0.98);
    final art = SizedBox(
      width: widget.height * fill * set.aspect,
      height: widget.height,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _SheetPainter(
            image: _image,
            frame: _frame,
            set: set,
            fill: fill,
            lift: widget.lift,
          ),
        ),
      ),
    );
    if (widget.flash <= 0) return art;
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        widget.flashColor.withValues(alpha: widget.flash),
        BlendMode.srcATop,
      ),
      child: art,
    );
  }
}

class _SheetPainter extends CustomPainter {
  final ui.Image? image;
  final ValueNotifier<int> frame;
  final MonsterSheetSet set;
  final double fill;
  final double lift;

  _SheetPainter({
    required this.image,
    required this.frame,
    required this.set,
    required this.fill,
    required this.lift,
  }) : super(repaint: frame);

  @override
  void paint(Canvas canvas, Size size) {
    final img = image;
    if (img == null) return;
    final f = frame.value;
    // Cells in the DECODED image's pixels — see [MonsterSheetSet.decodeScale].
    final k = img.width / (set.cols * set.frameW);
    final src = Rect.fromLTWH(
      (f % set.cols) * set.frameW * k,
      (f ~/ set.cols) * set.frameH * k,
      set.frameW * k,
      set.frameH * k,
    );
    final dh = size.height * fill;
    final dw = dh * set.aspect;
    final dst = Rect.fromLTWH(
      (size.width - dw) / 2,
      size.height - dh - size.height * lift,
      dw,
      dh,
    );
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.image != image || old.set != set || old.fill != fill;
}
