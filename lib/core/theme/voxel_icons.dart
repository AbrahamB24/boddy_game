import 'package:flutter/material.dart';

import 'game_icon_data.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ICONS FOR THE WHOLE APP
//
// [PixelIcon] (the name is historical) is a drop-in for Flutter's [Icon]: hand
// it a Material [IconData] and, when we drew a coloured icon for it, it shows
// that picture (assets/images/icons/<key>.webp, smooth, with outline and
// light/shade); otherwise it is the ordinary Material glyph, tinted as usual.
//
// The pictures come from tool/icons (icons_base.js, icons_extra.js,
// gen_icons.js). [GameIcon] shows one by key — the resources, rewards, status
// effects ... that used to be emoji (see kEmojiToIcon and core/ui/game_text.dart).
// ─────────────────────────────────────────────────────────────────────────────

/// Material icon code point -> the key of its pixel drawing.
final Map<int, String> _iconKeys = {
  Icons.close.codePoint: 'x',
  Icons.close_rounded.codePoint: 'x',
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
  Icons.filter_alt.codePoint: 'filter',
  Icons.tune.codePoint: 'filter',
  Icons.star_rounded.codePoint: 'star',
  Icons.star.codePoint: 'star',
  Icons.star_border_rounded.codePoint: 'starO',
  Icons.search.codePoint: 'search',
  Icons.search_off.codePoint: 'search',
  Icons.arrow_downward.codePoint: 'arrowDown',
  Icons.expand_more.codePoint: 'down',
  Icons.expand_less_rounded.codePoint: 'up',
  Icons.arrow_drop_down.codePoint: 'caretDown',
  Icons.arrow_drop_up.codePoint: 'caretUp',
  Icons.check_circle.codePoint: 'checkCircle',
  Icons.check_circle_outline.codePoint: 'checkCircle',
  Icons.delete_outline.codePoint: 'trash',
  Icons.delete_outline_rounded.codePoint: 'trash',
  Icons.delete.codePoint: 'trash',
  Icons.chevron_right.codePoint: 'right',
  Icons.chevron_right_rounded.codePoint: 'right',
  Icons.arrow_forward.codePoint: 'arrowRight',
  Icons.arrow_forward_rounded.codePoint: 'arrowRight',
  Icons.chevron_left.codePoint: 'left',
  Icons.chevron_left_rounded.codePoint: 'left',
  Icons.arrow_back.codePoint: 'arrowLeft',
  Icons.arrow_back_rounded.codePoint: 'arrowLeft',
  Icons.arrow_back_ios_new.codePoint: 'left',
  Icons.bolt.codePoint: 'bolt',
  Icons.flash_on.codePoint: 'bolt',
  Icons.shield.codePoint: 'shield',
  Icons.schedule.codePoint: 'clock',
  Icons.hourglass_bottom.codePoint: 'hourglass',
  Icons.hourglass_top.codePoint: 'hourglass',
  Icons.info_outline.codePoint: 'info',
  Icons.error_outline.codePoint: 'error',
  Icons.help_outline.codePoint: 'help',
  Icons.lock_outline.codePoint: 'lock',
  Icons.lock.codePoint: 'lock',
  Icons.favorite.codePoint: 'heart',
  Icons.flag.codePoint: 'flag',
  Icons.checklist.codePoint: 'tasks',
  Icons.travel_explore.codePoint: 'compass',
  Icons.notifications_none_rounded.codePoint: 'bell',
  Icons.notifications_active_rounded.codePoint: 'bell',
  Icons.notifications_active_outlined.codePoint: 'bell',
  Icons.circle_notifications_outlined.codePoint: 'bell',
  Icons.notifications.codePoint: 'bell',
  Icons.backpack.codePoint: 'backpack',
  Icons.inventory_2_outlined.codePoint: 'crate',
  Icons.inventory_2.codePoint: 'crate',
  Icons.groups.codePoint: 'groups',
  Icons.groups_2_outlined.codePoint: 'groups',
  Icons.group.codePoint: 'groups',
  Icons.people_alt_outlined.codePoint: 'groups',
  Icons.person.codePoint: 'person',
  Icons.directions_walk.codePoint: 'person',
  Icons.person_add_alt.codePoint: 'personAdd',
  Icons.home_work.codePoint: 'house',
  Icons.home_work_outlined.codePoint: 'house',
  Icons.home_outlined.codePoint: 'house',
  Icons.home.codePoint: 'house',
  Icons.check_box.codePoint: 'boxOn',
  Icons.check_box_outline_blank.codePoint: 'box',
  Icons.crop_square.codePoint: 'box',
  Icons.radio_button_unchecked.codePoint: 'ring',
  Icons.logout.codePoint: 'door',
  Icons.logout_rounded.codePoint: 'door',
  Icons.sports_martial_arts.codePoint: 'sword',
  Icons.open_with.codePoint: 'move',
  Icons.edit.codePoint: 'pencil',
  Icons.bar_chart.codePoint: 'chart',
  Icons.query_stats.codePoint: 'chart',
  Icons.construction.codePoint: 'hammer',
  Icons.build_outlined.codePoint: 'hammer',
  Icons.engineering.codePoint: 'gear',
  Icons.visibility_off.codePoint: 'eyeOff',
  Icons.wifi_off.codePoint: 'wifiOff',
  Icons.cloud_off_rounded.codePoint: 'wifiOff',
  Icons.sensors_off.codePoint: 'wifiOff',
  Icons.volume_up_outlined.codePoint: 'volume',
  Icons.save_outlined.codePoint: 'save',
  Icons.route.codePoint: 'road',
  Icons.add_road.codePoint: 'road',
  Icons.remove_road.codePoint: 'roadOff',
  Icons.map.codePoint: 'map',
  Icons.menu_book.codePoint: 'book',
  Icons.workspace_premium_rounded.codePoint: 'medal',
  Icons.military_tech.codePoint: 'medal',
  Icons.emoji_events_outlined.codePoint: 'trophy',
  Icons.whatshot_rounded.codePoint: 'flame',
  Icons.local_fire_department.codePoint: 'flame',
  Icons.egg.codePoint: 'egg',
  Icons.egg_alt.codePoint: 'egg',
  Icons.catching_pokemon.codePoint: 'ball',
  Icons.balance.codePoint: 'balance',
  Icons.sell_outlined.codePoint: 'tag',
  Icons.chat_bubble_outline.codePoint: 'chat',
  Icons.restore.codePoint: 'refresh',
  Icons.restart_alt.codePoint: 'refresh',
  Icons.replay_rounded.codePoint: 'refresh',
  Icons.screen_rotation.codePoint: 'refresh',
  Icons.rotate_90_degrees_cw_rounded.codePoint: 'refresh',
  Icons.grid_on.codePoint: 'grid',
  Icons.apps_rounded.codePoint: 'grid',
  Icons.hexagon_outlined.codePoint: 'hex',
  Icons.hub.codePoint: 'hex',
  Icons.forest.codePoint: 'tree',
  Icons.grass.codePoint: 'grass',
  Icons.auto_awesome.codePoint: 'sparkles',
  Icons.healing.codePoint: 'medical',
  Icons.medical_services.codePoint: 'medical',
  Icons.bookmark_border.codePoint: 'bookmark',
  Icons.drag_handle.codePoint: 'drag',
  Icons.vibration.codePoint: 'vibration',
  Icons.smart_toy.codePoint: 'robot',
  Icons.travel_explore.codePoint: 'globe',
  Icons.account_balance.codePoint: 'bank',
  Icons.broken_image.codePoint: 'picture',
  Icons.image_not_supported_outlined.codePoint: 'picture',
};


/// Asset path of the icon for [key].
String gameIconAsset(String key) => 'assets/images/icons/$key.webp';

/// How much larger than its layout box a picture is painted. The sprites keep
/// a little margin (outline, shadow, extrusion), and at 16-24 dp they read
/// small; painting them bigger gives the figure its room WITHOUT moving
/// anything around it (Transform only affects painting).
const double kGameIconGrow = 1.4;

/// Colour boost for every picture (user 2026-11-05: "kräftigere Farben"):
/// saturation x1.45 plus a touch of contrast. 1.0 = untouched sprites.
const double kGameIconSaturation = 1.45;
const double kGameIconContrast = 1.08;

List<double> _boostMatrix(double sat, double con) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final ir = (1 - sat) * r, ig = (1 - sat) * g, ib = (1 - sat) * b;
  final off = 128 * (1 - con);
  return <double>[
    (ir + sat) * con, ig * con, ib * con, 0, off, //
    ir * con, (ig + sat) * con, ib * con, 0, off, //
    ir * con, ig * con, (ib + sat) * con, 0, off, //
    0, 0, 0, 1, 0,
  ];
}

final ColorFilter _gameIconBoost =
    ColorFilter.matrix(_boostMatrix(kGameIconSaturation, kGameIconContrast));

/// A coloured icon by key (e.g. 'coin', 'wood'). Layout box [size] square, the
/// picture itself painted [grow] times larger around the same centre.
class GameIcon extends StatelessWidget {
  final String name;
  final double size;
  final double grow;
  final String? semanticLabel;
  const GameIcon(this.name,
      {super.key, this.size = 24, this.grow = kGameIconGrow, this.semanticLabel});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Transform.scale(
          scale: grow,
          child: ColorFiltered(
            colorFilter: _gameIconBoost,
            child: Image.asset(
              gameIconAsset(name),
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
              semanticLabel: semanticLabel,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => SizedBox(width: size, height: size),
            ),
          ),
        ),
      );
}

/// Drop-in for [Icon]: our coloured picture where one exists, else the
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
    if (key == null || !kGameIconKeys.contains(key)) {
      return super.build(context);
    }
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24.0;
    final op = (color?.a ?? 1) * (theme.opacity ?? 1);
    Widget w = GameIcon(key, size: s, semanticLabel: semanticLabel);
    if (op < 1) w = Opacity(opacity: op, child: w);
    return w;
  }
}
