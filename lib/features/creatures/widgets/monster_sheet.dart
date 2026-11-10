import 'dart:math' as math;
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

  /// Where the creature's FEET stand inside one cell, as fractions of its width
  /// and height. The side-view battle art is cut with the feet at the bottom
  /// edge (1.0), the isometric art keeps its shadow below the feet, so its feet
  /// sit higher in the cell (see [MonsterSheets.battleIso]). The player plants
  /// this point, not the cell's edge, on the ground.
  final double footX;
  final double footY;

  const MonsterSheetSet({
    required this.frameW,
    required this.frameH,
    this.cols = 8,
    required this.anims,
    this.decodeScale = 1,
    this.scale = 1,
    this.footX = 0.5,
    this.footY = 1.0,
  });

  double get aspect => frameW / frameH;
}

/// Which creatures have baked, animated 3D sprites. Everything else keeps its
/// flat network PNG, so a species can move over one at a time.
abstract final class MonsterSheets {
  static const String _t = 'assets/images/monsters/tidelord';

  // Every 560 x 448 battle sheet decodes at HALF size (user 2026-11-09: slow on
  // phones). A full 16-frame sheet is 4480 x 896 = 16 MB of texture; at 0.5 it
  // is 4 MB, decodes ~4x faster, and is still sharp at the ~200 px it is shown.
  static const double _battleDecode = 0.5;

  static const MonsterSheetSet _tidelordFront = MonsterSheetSet(
    frameW: 560,
    frameH: 448,
    decodeScale: _battleDecode,
    anims: {'idle': SheetAnim('$_t/front_idle.webp', 16, 12)},
  );
  static const MonsterSheetSet _tidelordBack = MonsterSheetSet(
    frameW: 560,
    frameH: 448,
    decodeScale: _battleDecode,
    anims: {'idle': SheetAnim('$_t/back_idle.webp', 16, 12)},
  );

  /// Evolutions: Oceanking (stage 1) and Abyssal Titan (stage 2). Same sheet
  /// layout as the pup, own folders.
  static MonsterSheetSet _evo(int stage, bool back, double scale) {
    final d = 'assets/images/monsters/tidelord_s$stage';
    final v = back ? 'back' : 'front';
    return MonsterSheetSet(
      frameW: 560,
      frameH: 448,
      decodeScale: _battleDecode,
      scale: scale,
      anims: {'idle': SheetAnim('$d/${v}_idle.webp', 16, 12)},
    );
  }

  static final MonsterSheetSet _oceankingFront = _evo(1, false, 1.2);
  static final MonsterSheetSet _oceankingBack = _evo(1, true, 1.2);
  static final MonsterSheetSet _titanFront = _evo(2, false, 1.4);
  static final MonsterSheetSet _titanBack = _evo(2, true, 1.4);

  static final Map<String, MonsterSheetSet> _isoCache = {};
  static const List<double> _isoScale = [1.0, 1.2, 1.4];

  /// Battle art for the ISOMETRIC arena (user 2026-11-08, forest arena): the
  /// same camera as the settlement map, so a monster stands on the arena's
  /// ground like a tree does. [mine] stands at the lower left facing up-right
  /// (the map's 'ne' heading), the enemy at the upper right facing down-left
  /// ('sw').
  ///
  /// Built from the MAP sheets, which only have idle and walk: the attack plays
  /// the walk cycle while the battle screen lunges the monster across the
  /// ground, and a hit is the idle with the screen's own shake and flash. Real
  /// attack and hurt bakes in these headings would replace the two aliases here
  /// and nothing else. Null when the creature has no baked art.
  static MonsterSheetSet? battleIso(
    String? speciesId,
    int stage, {
    required bool mine,
  }) {
    if (stage < 0 || stage > 2) return null;
    final base = map(speciesId, stage, mine ? 'ne' : 'sw');
    if (base == null) return null;
    return _isoCache.putIfAbsent('$speciesId/$stage/$mine', () {
      final walk = base.anims['walk']!;
      final idle = base.anims['idle']!;
      return MonsterSheetSet(
        frameW: base.frameW,
        frameH: base.frameH,
        // Same 0.5 as the map walkers: the arena draws the very same files, so
        // map and battle share ONE decoded texture per sheet, not two.
        decodeScale: 0.5,
        scale: _isoScale[stage],
        footX: mine ? 0.55 : 0.50,
        footY: 0.75,
        anims: {'idle': idle, 'walk': walk, 'attack': walk, 'hurt': idle},
      );
    });
  }

  // ── Glimmergnaw (tool/blender/glimmergnaw_bake.py) ──
  // One folder per stage, assets/images/monsters/glimmergnaw_s<stage>/, the
  // same sheet layout as the Tidelord: battle cells 560 x 448, map cells as
  // meta_map.json says. The evolutions are drawn bigger by [scale].
  static const List<double> _ggBattleScale = [1.0, 1.2, 1.4];
  static const List<double> _ggMapScale = [1.0, 1.15, 1.3];

  static MonsterSheetSet _ggView(int stage, String v) {
    final d = 'assets/images/monsters/glimmergnaw_s$stage';
    return MonsterSheetSet(
      frameW: 560,
      frameH: 448,
      decodeScale: _battleDecode,
      scale: _ggBattleScale[stage],
      anims: {'idle': SheetAnim('$d/${v}_idle.webp', 16, 12)},
    );
  }

  static final List<MonsterSheetSet> _ggFront = [
    for (var s = 0; s < 3; s++) _ggView(s, 'front'),
  ];
  static final List<MonsterSheetSet> _ggBack = [
    for (var s = 0; s < 3; s++) _ggView(s, 'back'),
  ];

  static Map<String, MonsterSheetSet> _ggWalkSets(int stage) {
    final d = 'assets/images/monsters/glimmergnaw_s$stage';
    return {
      for (final h in const ['se', 'ne', 'nw', 'sw'])
        h: MonsterSheetSet(
          frameW: stage == 0 ? 543 : 544,
          frameH: stage == 0 ? 434 : 435,
          decodeScale: 0.5,
          scale: _ggMapScale[stage],
          anims: {
            'walk': SheetAnim('$d/${h}_walk.webp', 8, 10),
            'idle': SheetAnim('$d/${h}_idle.webp', 8, 8),
          },
        ),
    };
  }

  static final List<Map<String, MonsterSheetSet>> _ggMap = [
    for (var s = 0; s < 3; s++) _ggWalkSets(s),
  ];

  /// Species that have baked, animated art (battle, lists, map).
  static bool hasBaked(String? speciesId) =>
      speciesId == 'tidelord' || speciesId == 'glimmergnaw';

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
    if (speciesId == 'glimmergnaw' && stage >= 0 && stage < 3) {
      return (back ? _ggBack : _ggFront)[stage];
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
    for (var s = 0; s < 3; s++) {
      if (url.contains('creature-images/glimmergnaw_${s}_back.png')) {
        return (set: _ggBack[s], back: true);
      }
      if (url.contains('creature-images/glimmergnaw_$s.png')) {
        return (set: _ggFront[s], back: false);
      }
    }
    return null;
  }

  /// Map-walking art for a creature heading [heading] ('se', 'ne', 'nw',
  /// 'sw'), or null — what the road walkers ask for.
  static MonsterSheetSet? map(String? speciesId, int stage, String heading) {
    if (speciesId == 'tidelord' && stage >= 0 && stage < _tidelordMap.length) {
      return _tidelordMap[stage][heading];
    }
    if (speciesId == 'glimmergnaw' && stage >= 0 && stage < _ggMap.length) {
      return _ggMap[stage][heading];
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

/// Decodes the art of the given creatures up front (user 2026-11-03: "alle
/// Assets beim Ladescreen vorladen"). Never throws.
///
/// REWORKED 2026-11-09 (user: "läuft auf dem Handy ziemlich schlecht"): this
/// used to decode EVERY species at EVERY stage, front and back, all three
/// animations, at full size - hundreds of MB of textures, on the loading
/// screen. Now it takes only the creatures asked for ([creatures]: species id
/// + stage), loads the resting pose lists/cards draw, plus the map walkers'
/// and the arena's sheets, all at the reduced decode width. Attack/hurt of the
/// old side-view art load on demand.
Future<void> precacheMonsterSheets(
  Iterable<({String speciesId, int stage})> creatures,
) {
  final seen = <String>{};
  final jobs = <Future<void>>[];
  final background = <({String speciesId, int stage})>[];
  for (final c in creatures) {
    if (!seen.add('${c.speciesId}#${c.stage}')) continue;
    for (final back in const [false, true]) {
      final set = MonsterSheets.battle(c.speciesId, c.stage, back: back);
      final idle = set?.anims['idle'];
      if (set != null && idle != null) {
        jobs.add(
          _loadSheet(idle.asset, width: _decodeWidthOf(set)).then<void>(
            (_) {},
            onError: (Object _) {},
          ),
        );
      }
    }
    // Walkers and arena sheets are the bulk (~15 MB per species/stage): they
    // load in the BACKGROUND, one after the other, and are not waited for - the
    // loading screen only blocks on the resting poses above. The battle screen
    // waits for its own combatants' sheets anyway.
    background.add(c);
  }
  () async {
    for (final c in background) {
      await precacheMonsterWalkSheets(c.speciesId, c.stage);
      await precacheBattleSheets(c.speciesId, c.stage);
    }
  }();
  return Future.wait(jobs).then<void>((_) {});
}

/// The isometric arena's sheets (idle + walk, both sides) for one creature -
/// what a fight draws. Shares its textures with the map walkers. The battle
/// screen calls this for every combatant before the fighters walk on. Never
/// throws.
Future<void> precacheBattleSheets(String? speciesId, int stage) =>
    Future.wait([
      for (final mine in const [true, false])
        if (MonsterSheets.battleIso(speciesId, stage, mine: mine)
            case final set?)
          for (final anim in {set.anims['idle']!, set.anims['walk']!})
            _loadSheet(anim.asset, width: _decodeWidthOf(set)).then<void>(
              (_) {},
              onError: (Object _) {},
            ),
    ]).then<void>((_) {});

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
      _playing = false;
      _nextPlay = Duration.zero;
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

  // ── Rest between idles (user 2026-11-08) ──
  // The idle sheet no longer loops forever: the creature rests on its first
  // frame, breathing (a code-driven squash at the feet, no extra art), and
  // every few seconds plays the baked idle once. Nothing to re-bake.
  final ValueNotifier<double> _breath = ValueNotifier<double>(0);
  final math.Random _rng = math.Random();
  bool _playing = false;
  Duration _nextPlay = Duration.zero;

  bool get _resting => widget.anim == 'idle' && _anim.loop;

  Duration _gap(Duration from) =>
      from + Duration(milliseconds: 2500 + _rng.nextInt(5500));

  void _tick(Duration elapsed) {
    _now = elapsed;
    final a = _anim;
    if (_resting) {
      if (_nextPlay == Duration.zero) _nextPlay = _gap(elapsed);
      // No waiting for the breath to die down first: that was a dead stop
      // before every idle (user 2026-11-08). The breath is handed over to the
      // idle's own motion below instead.
      if (!_playing && elapsed >= _nextPlay) {
        _playing = true;
        _t0 = elapsed;
      }
      // How much of the breath shows: all of it at rest, fading out over the
      // first 0.35 s of the idle while the idle's motion takes over, and back in
      // over its last 0.35 s. The phase never stops, so the squash at the feet
      // flows into the baked motion and out of it again without a seam.
      var amp = 1.0;
      if (_playing) {
        final tp0 = (elapsed - _t0).inMicroseconds / 1e6;
        final d0 = a.frames / a.fps;
        final edge = (math.min(tp0, d0 - tp0) / 0.35).clamp(0.0, 1.0);
        amp = 1 - edge * edge * (3 - 2 * edge);
      }
      if (_playing) {
        final tp = (elapsed - _t0).inMicroseconds / 1e6;
        final dur = a.frames / a.fps;
        if (tp >= dur) {
          _playing = false;
          _nextPlay = _gap(elapsed);
          if (_frame.value != 0) _frame.value = 0;
        } else {
          // EASED TEMPO (user 2026-11-08: "nur das Tempo der Animation sollte
          // ease in und out sein"): the same frames, shown whole and sharp, but
          // the clock they are picked by is eased — slower leaving the rest
          // pose, quickest in the middle, slower settling back into it.
          // (A cross-fade of two frames made the idle look washed out, so there
          // is none.) Only 60 % of the smoothstep is mixed in: a full one
          // stands almost still at both ends, and that read as a stop right
          // before and after the idle.
          final u = tp / dur;
          final e = 0.4 * u + 0.6 * (u * u * (3 - 2 * u));
          final n = math.min(a.frames - 1, (e * a.frames).floor());
          if (n != _frame.value) _frame.value = n;
        }
      } else {
        if (_frame.value != 0) _frame.value = 0;
      }
      // ~4.2 s per breath.
      final v = amp * math.sin(elapsed.inMilliseconds / 1000 * 1.5);
      if (v != _breath.value) _breath.value = v;
      return;
    }
    final n = ((elapsed - _t0).inMicroseconds * a.fps / 1e6).floor();
    final idx = a.loop ? n % a.frames : (n < a.frames ? n : a.frames - 1);
    if (idx != _frame.value) _frame.value = idx;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _breath.dispose();
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
            breath: _breath,
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
  final ValueNotifier<double> breath;
  final MonsterSheetSet set;
  final double fill;
  final double lift;

  _SheetPainter({
    required this.image,
    required this.frame,
    required this.breath,
    required this.set,
    required this.fill,
    required this.lift,
  }) : super(repaint: Listenable.merge([frame, breath]));

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
    // The foot point (not the cell's edge) is what stands on the box's bottom.
    final dst = Rect.fromLTWH(
      (size.width - dw) / 2 - dw * (set.footX - 0.5),
      size.height * (1 - lift) - dh * set.footY,
      dw,
      dh,
    );
    final b = breath.value;
    if (b != 0) {
      // Breathing: grow a hair taller and narrower, pivoting on the feet.
      final px = dst.left + dw * set.footX;
      final py = size.height * (1 - lift);
      canvas.save();
      canvas.translate(px, py);
      canvas.scale(1 - 0.008 * b, 1 + 0.025 * b);
      canvas.translate(-px, -py);
    }
    canvas.drawImageRect(
      img,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
    if (b != 0) canvas.restore();
  }

  @override
  bool shouldRepaint(_SheetPainter old) =>
      old.image != image || old.set != set || old.fill != fill;
}
