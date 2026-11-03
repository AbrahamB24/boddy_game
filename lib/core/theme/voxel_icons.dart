import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PIXEL ICONS FOR THE WHOLE APP
//
// [PixelIcon] is a drop-in for Flutter's [Icon]: hand it a Material [IconData]
// and, when there is a block drawing for it, it draws that on an 8 x 8 grid;
// otherwise it falls back to the Material glyph so nothing ever goes missing.
// ─────────────────────────────────────────────────────────────────────────────

List<String> _flipH(List<String> g) =>
    [for (final r in g) r.split('').reversed.join()];
List<String> _flipV(List<String> g) => g.reversed.toList();

const _paw = [
  '#..##..#',
  '#..##..#',
  '........',
  '..####..',
  '.######.',
  '.######.',
  '..####..',
  '........',
];
const _star = [
  '...##...',
  '...##...',
  '########',
  '.######.',
  '..####..',
  '.##..##.',
  '.#....#.',
  '........',
];
const _starOutline = [
  '...##...',
  '..#..#..',
  '###..###',
  '#......#',
  '.#....#.',
  '..#..#..',
  '.##..##.',
  '.#....#.',
];
const _plus = [
  '...##...',
  '...##...',
  '...##...',
  '########',
  '########',
  '...##...',
  '...##...',
  '...##...',
];
const _minus = [
  '........',
  '........',
  '........',
  '########',
  '########',
  '........',
  '........',
  '........',
];
const _check = [
  '......##',
  '.....###',
  '#...###.',
  '##.###..',
  '.####...',
  '..##....',
  '........',
  '........',
];
const _chevRight = [
  '##......',
  '.##.....',
  '..##....',
  '...##...',
  '..##....',
  '.##.....',
  '##......',
  '........',
];
const _chevDown = [
  '........',
  '##....##',
  '.##..##.',
  '..####..',
  '...##...',
  '........',
  '........',
  '........',
];
const _sort = [
  '..#.....',
  '.###....',
  '#.#.....',
  '..#..#..',
  '..#..#..',
  '..#.#.#.',
  '...###..',
  '....#...',
];
const _swapH = [
  '..#...#.',
  '.##...##',
  '########',
  '.##...##',
  '..#...#.',
  '........',
  '........',
  '........',
];
const _search = [
  '.####...',
  '#....#..',
  '#....#..',
  '#....#..',
  '.####...',
  '....##..',
  '.....##.',
  '......##',
];
const _filter = [
  '########',
  '########',
  '.######.',
  '..####..',
  '...##...',
  '...##...',
  '...##...',
  '........',
];
const _bolt = [
  '.....##.',
  '....##..',
  '...##...',
  '..######',
  '....##..',
  '...##...',
  '..##....',
  '........',
];
const _shield = [
  '########',
  '########',
  '########',
  '########',
  '.######.',
  '..####..',
  '...##...',
  '........',
];
const _clock = [
  '..####..',
  '.#.##.#.',
  '#..##..#',
  '#..###.#',
  '#......#',
  '#......#',
  '.#....#.',
  '..####..',
];
const _info = [
  '...##...',
  '........',
  '..###...',
  '...##...',
  '...##...',
  '...##...',
  '..####..',
  '........',
];
const _trash = [
  '..####..',
  '########',
  '.######.',
  '.#.##.#.',
  '.#.##.#.',
  '.#.##.#.',
  '.######.',
  '........',
];
const _lock = [
  '..####..',
  '.#....#.',
  '.#....#.',
  '########',
  '###..###',
  '###..###',
  '########',
  '........',
];
const _house = [
  '...##...',
  '..####..',
  '.######.',
  '########',
  '.######.',
  '.##..##.',
  '.##..##.',
  '........',
];
const _hammer = [
  '..#####.',
  '..#####.',
  '..#####.',
  '...##...',
  '...##...',
  '...##...',
  '...##...',
  '........',
];
const _bell = [
  '...##...',
  '..####..',
  '..####..',
  '.######.',
  '.######.',
  '########',
  '........',
  '...##...',
];
const _bag = [
  '..####..',
  '.#....#.',
  '########',
  '########',
  '#.####.#',
  '#.####.#',
  '########',
  '........',
];
const _person = [
  '..####..',
  '..####..',
  '..####..',
  '...##...',
  '.######.',
  '########',
  '########',
  '........',
];
const _box = [
  '########',
  '#......#',
  '#......#',
  '#......#',
  '#......#',
  '#......#',
  '########',
  '........',
];
const _boxChecked = [
  '########',
  '#.....##',
  '#....#.#',
  '##..#..#',
  '#.##...#',
  '#..#...#',
  '########',
  '........',
];
const _door = [
  '######..',
  '#....#..',
  '#....#.#',
  '#....###',
  '#....#.#',
  '#....#..',
  '######..',
  '........',
];
const _move = [
  '...##...',
  '..####..',
  '.#.##.#.',
  '########',
  '########',
  '.#.##.#.',
  '..####..',
  '...##...',
];
const _heart = [
  '.##..##.',
  '########',
  '########',
  '########',
  '.######.',
  '..####..',
  '...##...',
  '........',
];
const _flag = [
  '#####...',
  '######..',
  '#######.',
  '######..',
  '#.......',
  '#.......',
  '#.......',
  '#.......',
];
const _sword = [
  '......##',
  '.....###',
  '....###.',
  '#..###..',
  '.####...',
  '..##....',
  '.####...',
  '##..#...',
];
const _cross = [
  '##....##',
  '###..###',
  '.######.',
  '..####..',
  '..####..',
  '.######.',
  '###..###',
  '##....##',
];
const _pencil = [
  '.....##.',
  '....####',
  '...####.',
  '..####..',
  '.####...',
  '.###....',
  '##......',
  '........',
];
const _chart = [
  '......##',
  '......##',
  '...#..##',
  '...#..##',
  '##.#..##',
  '##.#..##',
  '##.#..##',
  '########',
];

final Map<String, List<String>> _bitmaps = {
  'paw': _paw,
  'star': _star,
  'starO': _starOutline,
  'plus': _plus,
  'minus': _minus,
  'check': _check,
  'right': _chevRight,
  'left': _flipH(_chevRight),
  'down': _chevDown,
  'up': _flipV(_chevDown),
  'sort': _sort,
  'swapH': _swapH,
  'search': _search,
  'filter': _filter,
  'bolt': _bolt,
  'shield': _shield,
  'clock': _clock,
  'info': _info,
  'trash': _trash,
  'lock': _lock,
  'house': _house,
  'hammer': _hammer,
  'bell': _bell,
  'bag': _bag,
  'person': _person,
  'box': _box,
  'boxOn': _boxChecked,
  'door': _door,
  'move': _move,
  'heart': _heart,
  'flag': _flag,
  'sword': _sword,
  'x': _cross,
  'pencil': _pencil,
  'chart': _chart,
};

/// Material icon code point -> the key of its block drawing.
final Map<int, String> _iconKeys = {
  Icons.close.codePoint: 'x',
  Icons.cancel.codePoint: 'x',
  Icons.pets.codePoint: 'paw',
  Icons.add.codePoint: 'plus',
  Icons.add_circle_outline.codePoint: 'plus',
  Icons.remove.codePoint: 'minus',
  Icons.remove_circle_outline.codePoint: 'minus',
  Icons.swap_vert.codePoint: 'sort',
  Icons.unfold_more.codePoint: 'sort',
  Icons.swap_horiz.codePoint: 'swapH',
  Icons.filter_alt_outlined.codePoint: 'filter',
  Icons.tune.codePoint: 'filter',
  Icons.star_rounded.codePoint: 'star',
  Icons.star.codePoint: 'star',
  Icons.star_border_rounded.codePoint: 'starO',
  Icons.search.codePoint: 'search',
  Icons.search_off.codePoint: 'search',
  Icons.arrow_upward.codePoint: 'up',
  Icons.arrow_upward_rounded.codePoint: 'up',
  Icons.upgrade.codePoint: 'up',
  Icons.trending_up.codePoint: 'up',
  Icons.arrow_downward.codePoint: 'down',
  Icons.expand_more.codePoint: 'down',
  Icons.check.codePoint: 'check',
  Icons.check_rounded.codePoint: 'check',
  Icons.check_circle.codePoint: 'check',
  Icons.check_circle_outline.codePoint: 'check',
  Icons.done.codePoint: 'check',
  Icons.delete_outline.codePoint: 'trash',
  Icons.delete.codePoint: 'trash',
  Icons.chevron_right.codePoint: 'right',
  Icons.chevron_right_rounded.codePoint: 'right',
  Icons.arrow_forward.codePoint: 'right',
  Icons.chevron_left.codePoint: 'left',
  Icons.chevron_left_rounded.codePoint: 'left',
  Icons.arrow_back.codePoint: 'left',
  Icons.arrow_back_rounded.codePoint: 'left',
  Icons.arrow_back_ios_new.codePoint: 'left',
  Icons.bolt.codePoint: 'bolt',
  Icons.shield.codePoint: 'shield',
  Icons.schedule.codePoint: 'clock',
  Icons.hourglass_bottom.codePoint: 'clock',
  Icons.info_outline.codePoint: 'info',
  Icons.lock_outline.codePoint: 'lock',
  Icons.lock.codePoint: 'lock',
  Icons.favorite.codePoint: 'heart',
  Icons.flag.codePoint: 'flag',
  Icons.notifications_none_rounded.codePoint: 'bell',
  Icons.notifications_active_rounded.codePoint: 'bell',
  Icons.notifications.codePoint: 'bell',
  Icons.backpack.codePoint: 'bag',
  Icons.inventory_2_outlined.codePoint: 'bag',
  Icons.groups.codePoint: 'person',
  Icons.people_alt_outlined.codePoint: 'person',
  Icons.person.codePoint: 'person',
  Icons.home_work.codePoint: 'house',
  Icons.home_outlined.codePoint: 'house',
  Icons.home.codePoint: 'house',
  Icons.check_box.codePoint: 'boxOn',
  Icons.check_box_outline_blank.codePoint: 'box',
  Icons.crop_square.codePoint: 'box',
  Icons.logout.codePoint: 'door',
  Icons.sports_martial_arts.codePoint: 'sword',
  Icons.open_with.codePoint: 'move',
  Icons.edit.codePoint: 'pencil',
  Icons.bar_chart.codePoint: 'chart',
};

/// A block-drawn stand-in for [Icon]. It IS an [Icon] (so `find.byIcon` and
/// any `is Icon` check still see it); only the drawing differs, and only for
/// icons that have a block bitmap â€” the rest fall straight through to the
/// Material glyph.
class PixelIcon extends Icon {
  const PixelIcon(
    super.icon, {
    super.key,
    super.size,
    super.fill,
    super.weight,
    super.grade,
    super.opticalSize,
    super.color,
    super.shadows,
    super.semanticLabel,
    super.textDirection,
    super.applyTextScaling,
    super.blendMode,
  });

  @override
  Widget build(BuildContext context) {
    final key = icon == null ? null : _iconKeys[icon!.codePoint];
    final bits = key == null ? null : _bitmaps[key];
    if (bits == null) return super.build(context);
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24.0;
    var c = color ?? theme.color ?? Colors.white;
    final op = theme.opacity;
    if (op != null && op < 1) c = c.withValues(alpha: c.a * op);
    Widget w = SizedBox(
      width: s,
      height: s,
      child: CustomPaint(painter: _BitsPainter(bits, c)),
    );
    if (semanticLabel != null) {
      w = Semantics(label: semanticLabel, image: true, child: w);
    }
    return w;
  }
}
class _BitsPainter extends CustomPainter {
  final List<String> bits;
  final Color color;
  _BitsPainter(this.bits, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 8;
    final p = Paint()
      ..color = color
      ..isAntiAlias = false;
    // Cells snapped to whole device-independent edges so no hairline gaps open
    // between neighbouring blocks at fractional sizes.
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        if (bits[y][x] == '#') {
          canvas.drawRect(
            Rect.fromLTRB(
              (x * u).roundToDouble(),
              (y * u).roundToDouble(),
              ((x + 1) * u).roundToDouble(),
              ((y + 1) * u).roundToDouble(),
            ),
            p,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_BitsPainter o) => o.bits != bits || o.color != color;
}
