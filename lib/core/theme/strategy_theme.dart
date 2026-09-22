import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/pressable.dart';
import 'cream_kit.dart' show MenuScaffold;
import 'foe_theme.dart';

/// The app-wide chunky "strategy HUD" look (2026-09-18 redesign, following
/// Forge of Empires / Clash of Clans / Rise of Kingdoms: ribbon banners,
/// gem-badge resource pills, bevelled 3D buttons, gold rivets) — the shapes
/// every screen now builds its chrome from, alongside [FoE]'s own colour
/// tokens (which this reuses rather than replaces; see the doc comment on
/// each Strategy.* colour below for which FoE token it stands in for).
///
/// This supersedes `management_theme.dart`'s own scoping decision ("nothing
/// here is meant to leak into any other screen") — the whole app shares one
/// look now, not just the Management screen that first prototyped it.
class Strategy {
  Strategy._();

  /// True gold-yellow — the currency/premium accent every reference game
  /// uses for its gold resource and "collect" highlight. Not one of FoE's
  /// existing tokens (its own `FoE.gold` is actually a cyan-blue, kept for
  /// historical reasons — see that file's own doc comment); this is a new,
  /// deliberate addition in the same warm family as [FoE.danger]/coral.
  static const Color gold = Color(0xFFFFC94D);
  static const Color goldDeep = Color(0xFFDB9A18);

  /// The "active/positive" accent. Named `cyan` from the blue theme; since
  /// 2026-09-22 ("Alle blauen Reste im UI ersetzen") it is the kit's gold, and the
  /// name is kept only so no caller changes.
  static const Color cyan = FoE.gold;
  static const Color cyanDeep = Color(0xFFC98A10);

  /// Danger/alert — [FoE.danger], unchanged.
  static const Color coral = FoE.danger;
  static const Color coralDeep = Color(0xFF7A2E15);

  /// A locked/disabled fill — distinct from every action colour so a
  /// disabled chunky button reads as "can't", not as a dimmed version of
  /// whatever it would otherwise do.
  static const Color locked = Color(0xFFB8AA90);
  static const Color lockedDeep = Color(0xFF938670);

  /// Card surfaces — [FoE.cream]/[FoE.tan], unchanged (the light card every
  /// resource/creature tile sits on against the navy chrome).
  static const Color cream = FoE.cream;
  static const Color tan = FoE.tan;

  /// The dark navy outline/rim every chunky shape casts its hard shadow in —
  /// deliberately darker than [FoE.bg] itself so the shadow reads as a real
  /// drop rather than a slightly-darker fill.
  static const Color outline = Color(0xFF1A0F06);
}

/// [c], darkened toward black by [amount] — the bevel/shadow colour a fill
/// casts when no caller-supplied "deep" shade is given.
Color strategyDarken(Color c, [double amount = 0.42]) =>
    Color.lerp(c, Colors.black, amount)!;

/// [c], lightened toward white by [amount] — the highlight edge on a raised
/// fill.
Color strategyLighten(Color c, [double amount = 0.35]) =>
    Color.lerp(c, Colors.white, amount)!;

/// White ink on a saturated fill, dark ink on a pale one — so text on a
/// chunky shape stays readable no matter which action colour fills it,
/// without every call site picking its own ink by hand.
Color strategyTextOn(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.light
    ? Strategy.outline
    : Colors.white;

/// The flat 3D-bevelled fill every chunky shape wears: a top-lit gradient, a
/// hard (unblurred) offset shadow in its own "deep" shade standing in for
/// the bevel's dark rim, and an optional outline. [ChunkyButton] adds the
/// glossy highlight sheen on top of this; a caller that only wants the
/// surface (a card, a tile) without the sheen uses this directly.
BoxDecoration chunkyDecoration({
  required Color fill,
  Color? deep,
  double radius = 14,
  double borderWidth = 0,
  Color? borderColor,
  double shadowOffset = 4,
}) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [strategyLighten(fill, 0.16), fill],
  ),
  borderRadius: BorderRadius.circular(radius),
  border: borderWidth > 0
      ? Border.all(color: borderColor ?? Strategy.outline, width: borderWidth)
      : null,
  boxShadow: [
    BoxShadow(
      color: deep ?? strategyDarken(fill),
      offset: Offset(0, shadowOffset),
      blurRadius: 0,
    ),
  ],
);

/// A bevelled 3D button — the screen's one pressable shape, coloured per
/// action. Disabled falls back to [Strategy.locked] rather than a dimmed
/// opacity of whatever colour it would otherwise be, so "can't" always
/// reads as its own state. Wraps [Pressable] for the press-travel feel
/// every button in the app already shares — this does not reinvent that.
class ChunkyButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color fill;
  final Color? deep;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double shadowOffset;
  final double borderWidth;
  final bool expand;

  const ChunkyButton({
    super.key,
    required this.child,
    required this.onTap,
    this.fill = Strategy.cyan,
    this.deep,
    this.radius = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.shadowOffset = 4,
    this.borderWidth = 0,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final effectiveFill = enabled ? fill : Strategy.locked;
    final effectiveDeep = enabled
        ? (deep ?? strategyDarken(fill))
        : Strategy.lockedDeep;
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          width: expand ? double.infinity : null,
          clipBehavior: Clip.antiAlias,
          decoration: chunkyDecoration(
            fill: effectiveFill,
            deep: effectiveDeep,
            radius: radius,
            shadowOffset: shadowOffset,
            borderWidth: borderWidth,
          ),
          child: Stack(
            children: [
              Padding(
                padding: padding,
                child: Center(child: child),
              ),
              // The glossy top-highlight sheen — a plain gradient overlay
              // covering the top ~46%, exactly the CSS `.chunky::after`
              // technique the HTML mockups used, ported to a Positioned
              // child since Flutter has no pseudo-elements.
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FractionallySizedBox(
                      heightFactor: 0.46,
                      widthFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(radius),
                            topRight: Radius.circular(radius),
                            bottomLeft: Radius.circular(radius * 0.4),
                            bottomRight: Radius.circular(radius * 0.4),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: 0.55),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A circular resource/count badge with a radial highlight and a ring
/// border — the gem icons on the resource bar, a stock count on a target
/// tile, a slot readout.
class GemBadge extends StatelessWidget {
  final Widget child;
  final double size;
  final Color color;
  final Color? ringColor;

  const GemBadge({
    super.key,
    required this.child,
    this.size = 32,
    this.color = Strategy.gold,
    this.ringColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.35, -0.4),
        radius: 0.9,
        colors: [
          strategyLighten(color, 0.6),
          color,
          strategyDarken(color, 0.2),
        ],
        stops: const [0, 0.55, 1],
      ),
      border: Border.all(
        color: ringColor ?? strategyDarken(color, 0.5),
        width: size * 0.09,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          offset: Offset(0, size * 0.09),
          blurRadius: 0,
        ),
      ],
    ),
    child: child,
  );
}

/// The tiny gold corner accent marking a chunky card's corners — purely
/// decorative, no interaction.
class Rivet extends StatelessWidget {
  final double size;

  const Rivet({super.key, this.size = 6});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        center: const Alignment(-0.4, -0.4),
        colors: [
          strategyLighten(Strategy.gold, 0.6),
          strategyDarken(Strategy.gold, 0.35),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          offset: const Offset(0, 1),
          blurRadius: 0,
        ),
      ],
    ),
  );
}

/// A pointed-flag banner — the title ribbon every screen's header now wears.
/// Two nested clips of the same hexagon shape, the outer slightly bigger and
/// filled with [trim] (reading as a border), the inner filled with [fill] —
/// the same "trim shape behind a smaller fill shape" trick the HTML mockups
/// used via two CSS `clip-path`s, since Flutter has no border-on-a-clip-path
/// shorthand.
class RibbonBanner extends StatelessWidget {
  final Widget child;
  final Color fill;
  final Color trim;

  const RibbonBanner({
    super.key,
    required this.child,
    this.fill = Strategy.outline,
    this.trim = Strategy.gold,
  });

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: ClipPath(
          clipper: const _RibbonClipper(pointInset: 0.02),
          child: ColoredBox(color: trim),
        ),
      ),
      Positioned.fill(
        child: ClipPath(
          clipper: const _RibbonClipper(pointInset: 0.03, verticalInset: 0.08),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill),
            child: Center(child: child),
          ),
        ),
      ),
    ],
  );
}

class _RibbonClipper extends CustomClipper<Path> {
  /// Fraction of WIDTH the flat top/bottom edges are inset from each side
  /// before the shape points to the true edge at mid-height.
  final double pointInset;

  /// Fraction of HEIGHT the top/bottom edges are inset from the full box —
  /// 0 for the outer trim (spans the full height), >0 for the inner fill
  /// (leaves the trim visible as a ring).
  final double verticalInset;

  const _RibbonClipper({required this.pointInset, this.verticalInset = 0});

  @override
  Path getClip(Size size) {
    final left = size.width * pointInset;
    final right = size.width * (1 - pointInset);
    final top = size.height * verticalInset;
    final bottom = size.height * (1 - verticalInset);
    final midY = (top + bottom) / 2;
    return Path()
      ..moveTo(left, top)
      ..lineTo(right, top)
      ..lineTo(size.width, midY)
      ..lineTo(right, bottom)
      ..lineTo(left, bottom)
      ..lineTo(0, midY)
      ..close();
  }

  @override
  bool shouldReclip(covariant _RibbonClipper oldClipper) =>
      oldClipper.pointInset != pointInset ||
      oldClipper.verticalInset != verticalInset;
}

/// The screen's own chrome — a header band (back arrow, ribbon title, an
/// optional trailing readout) over a flat navy page. Shared here so every
/// migrated screen gets it once, replacing the per-feature scaffolds
/// (`ParchmentPage`, the old `management_theme.dart`'s own `MgmtScaffold`)
/// each screen used to build its own copy of.
class StrategyScaffold extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? floatingActionButton;

  const StrategyScaffold({
    super.key,
    required this.title,
    this.trailing,
    required this.child,
    this.showBack = true,
    this.onBack,
    this.floatingActionButton,
  });

  // Every screen built on this now wears the building dialog's template (user
  // 2026-09-18: "das gesamte UI an den Gebäudedetailscreen anpassen"): a navy
  // ground, a cream title card, a gold close button — see [MenuScaffold] in
  // cream_kit.dart, which owns the look so there is one copy of it.
  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: title,
    trailing: trailing,
    showClose: showBack,
    onClose: onBack,
    floatingActionButton: floatingActionButton,
    child: child,
  );
}

/// The strategy-HUD title bar (back arrow + ribbon title + trailing), public so
/// screens that are not a plain scaffold page (a map with a floating bar) can
/// wear it too.
class StrategyHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool showBack;
  final VoidCallback? onBack;

  const StrategyHeader({
    super.key,
    required this.title,
    this.trailing,
    required this.showBack,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: const BoxDecoration(color: Strategy.outline),
    child: Row(
      children: [
        if (showBack)
          ChunkyButton(
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            fill: FoE.panelLight,
            deep: strategyDarken(FoE.panelLight),
            radius: 12,
            padding: const EdgeInsets.all(6),
            shadowOffset: 3,
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 16,
              color: Colors.white,
            ),
          )
        else
          const SizedBox(width: 32),
        const SizedBox(width: 10),
        Expanded(
          child: RibbonBanner(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFE9B0),
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    ),
  );
}

/// A small filled pill for a count or a countdown — the slot readout, a
/// stock number, "READY".
class PillBadge extends StatelessWidget {
  final String text;
  final Color color;
  final Color? textColor;

  const PillBadge({
    super.key,
    required this.text,
    this.color = Strategy.outline,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Strategy.outline, width: 2),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: textColor ?? strategyTextOn(color),
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  );
}

/// The flat progress bar every trip/spot uses: a white outlined trough, a
/// solid colour fill that glides to its new width.
class ChunkyBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const ChunkyBar({
    super.key,
    required this.value,
    this.color = Strategy.cyan,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Strategy.outline, width: 2),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: v),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          builder: (context, val, _) => FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: val,
            child: DecoratedBox(decoration: BoxDecoration(color: color)),
          ),
        ),
      ),
    );
  }
}

/// A filter chip: an emoji, its label and a live count riding together in
/// one flat pill — an active/inactive toggle with its own count so
/// switching drawers tells you whether it's worth switching at all.
class SelectChip extends StatelessWidget {
  final String emoji;
  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  const SelectChip({
    super.key,
    required this.emoji,
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ChunkyButton(
    onTap: onTap,
    fill: active ? Strategy.gold : Strategy.tan,
    deep: active ? Strategy.goldDeep : strategyDarken(Strategy.tan),
    radius: 20,
    shadowOffset: 3,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: strategyTextOn(active ? Strategy.gold : Strategy.tan),
          ),
        ),
        const SizedBox(width: 5),
        PillBadge(
          text: '$count',
          color: active
              ? Strategy.outline
              : Strategy.outline.withValues(alpha: 0.7),
        ),
      ],
    ),
  );
}

/// A circular countdown dial — a mobile strategy game times things with a
/// filling ring far more often than a linear bar (a clock, not a loading
/// screen); it also costs less width than a bar+label stack, which is what
/// lets several of these sit side by side.
class RadialTimer extends StatelessWidget {
  final double value;
  final String emoji;
  final bool ready;
  final double size;

  const RadialTimer({
    super.key,
    required this.value,
    required this.emoji,
    this.ready = false,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: v),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        builder: (context, val, _) => CustomPaint(
          painter: _RadialPainter(
            value: val,
            trackColor: Strategy.outline.withValues(alpha: 0.15),
            fillColor: ready ? Strategy.gold : Strategy.cyan,
          ),
          child: Center(
            child: Text(emoji, style: TextStyle(fontSize: size * 0.4)),
          ),
        ),
      ),
    );
  }
}

class _RadialPainter extends CustomPainter {
  final double value;
  final Color trackColor;
  final Color fillColor;

  _RadialPainter({
    required this.value,
    required this.trackColor,
    required this.fillColor,
  });

  static const double _start = -math.pi / 2;
  static const double _full = math.pi * 2;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.14;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawArc(
      rect,
      0,
      _full,
      false,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        _start,
        _full * value,
        false,
        Paint()
          ..color = fillColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawCircle(
      rect.center,
      rect.width / 2 + stroke / 2,
      Paint()
        ..color = Strategy.outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _RadialPainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.fillColor != fillColor;
}
