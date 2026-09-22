import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../models/pvp_match.dart';

/// The small parts every Social pane is built from, in the cream kit: a round
/// avatar (there are no profile pictures — the initial on a colour the name
/// picks), a red count badge, and the two button looks (gold, tile).

const List<Color> _avatarColors = [
  Color(0xFFE25822),
  Color(0xFF018ABE),
  Color(0xFF3BAE78),
  Color(0xFF8E5BB5),
  Color(0xFFD99A22),
  Color(0xFF6B5B95),
  Color(0xFFC2417A),
  Color(0xFF4F8A8B),
];

/// A round avatar: the first letter of [name] on a colour derived from the
/// name, so the same person always looks the same.
class SocialAvatar extends StatelessWidget {
  final String name;
  final double size;

  const SocialAvatar(this.name, {super.key, this.size = 34});

  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xFFFF);
    final color = _avatarColors[seed % _avatarColors.length];
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.45),
          colors: [Color.lerp(color, Colors.white, 0.3)!, color],
        ),
        border: Border.all(color: CreamPalette.tan, width: 1.5),
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.44,
          fontWeight: FontWeight.w800,
          shadows: const [
            Shadow(color: Color(0x59000000), offset: Offset(0, 1)),
          ],
        ),
      ),
    );
  }
}

/// The red number that says "this is waiting for you". Renders nothing at 0.
class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 17),
      height: 17,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: CreamPalette.warn,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1.1,
        ),
      ),
    );
  }
}

/// A gold pill button — the one look for the action that matters.
class SocialGoldButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const SocialGoldButton(
    this.label, {
    super.key,
    this.onTap,
    this.height = 30,
    this.fontSize = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 14),
  });

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: height,
      padding: padding,
      alignment: Alignment.center,
      decoration: goldButton(active: onTap != null),
      child: Text(
        label,
        maxLines: 1,
        style: TextStyle(
          color: goldButtonInk(active: onTap != null),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

/// A raised tile button — the secondary action next to a gold one.
class SocialTileButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;
  final double fontSize;
  final int badge;

  const SocialTileButton(
    this.label, {
    super.key,
    this.icon,
    this.onTap,
    this.height = 30,
    this.fontSize = 12,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: raisedTile(radius: 11),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: kBoxInk),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            maxLines: 1,
            style: TextStyle(
              color: kBoxInk,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (badge > 0) ...[const SizedBox(width: 6), CountBadge(badge)],
        ],
      ),
    ),
  );
}

/// A round raised button holding a glyph — the small actions on a row. A
/// [badge] rides on its corner.
class SocialGlyphButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final int badge;
  final bool gold;

  const SocialGlyphButton(
    this.icon, {
    super.key,
    this.onTap,
    this.tooltip,
    this.size = 30,
    this.badge = 0,
    this.gold = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Pressable(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: gold
                ? goldButton().copyWith(
                    borderRadius: BorderRadius.circular(size),
                  )
                : raisedTile(radius: size),
            child: Icon(icon, size: size * 0.56, color: kBoxInk),
          ),
          if (badge > 0)
            Positioned(right: -6, top: -6, child: CountBadge(badge)),
        ],
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// A raised row tile — the shape of every list entry.
Widget socialRow({
  required Widget child,
  bool lit = false,
  bool warm = false,
  double height = 46,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 10),
  VoidCallback? onTap,
}) {
  final body = Container(
    height: height,
    padding: padding,
    decoration: warm
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CreamPalette.gold.withValues(alpha: 0.42),
                CreamPalette.gold.withValues(alpha: 0.3),
              ],
            ),
            boxShadow: const [
              BoxShadow(color: CreamPalette.goldDeep, offset: Offset(0, 3)),
            ],
          )
        : raisedTile(lit: lit),
    child: child,
  );
  return onTap == null ? body : Pressable(onTap: onTap, child: body);
}

/// A small caps section label, with an optional trailing widget.
Widget socialSection(String text, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Row(
    children: [
      Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.9,
          color: kBoxAccent,
        ),
      ),
      const Spacer(),
      if (trailing != null) trailing,
    ],
  ),
);

/// A muted line for an empty list.
Widget socialHint(String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 10),
  child: Text(text, style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft)),
);

/// "Name · 1240 · 12W 5L" — the one way a player's record reads.
String recordLine(int rating, int wins, int losses) =>
    '$rating · ${wins}W ${losses}L';

/// Where the other player is in a match, as a small chip — the same words in
/// every list and in the lobby: "Not yet accepted", "Accepted — not in the
/// lobby", "Waiting in the lobby", "Ready". Gold when they are waiting on you
/// (in the lobby), green when they are ready, quiet before that.
class StageChip extends StatelessWidget {
  final PvpOpponentStage stage;

  const StageChip(this.stage, {super.key});

  @override
  Widget build(BuildContext context) {
    final waiting = stage == PvpOpponentStage.inLobby;
    final ready = stage == PvpOpponentStage.ready;
    final live = stage == PvpOpponentStage.inBattle;
    final Color fill = ready
        ? CreamPalette.better.withValues(alpha: 0.18)
        : (waiting || live)
        ? CreamPalette.gold.withValues(alpha: 0.4)
        : Colors.transparent;
    final Color edge = ready
        ? CreamPalette.better
        : (waiting || live)
        ? CreamPalette.goldDeep
        : CreamPalette.tan.withValues(alpha: 0.55);
    final Color ink = ready
        ? CreamPalette.better
        : (waiting || live)
        ? kBoxAccent
        : kBoxInkFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: edge),
      ),
      child: Text(
        stage.label,
        maxLines: 1,
        style: FoE.dim(
          size: 10,
        ).copyWith(color: ink, fontWeight: FontWeight.w800),
      ),
    );
  }
}
