import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the whole game. **This file IS the design system** — the
/// class name and member API are deliberately frozen so a restyle lands
/// everywhere without touching a single screen. It has been rewritten in place
/// twice now (Forge-of-Empires gold → pixel-art → this) and no screen changed.
///
/// ── Current direction: MODERN MOBILE, PIXEL SPRITES (2026-07) ──
/// The chrome is a contemporary phone-game UI: deep neutral background,
/// elevated surfaces, soft blurred shadows, generous rounding, one geometric
/// sans (Outfit) across the board. The creature sprites stay hard pixel art —
/// every Image widget showing one sets `filterQuality: FilterQuality.none`.
///
/// That pairing is the whole point, not a compromise: a clean, quiet frame
/// makes pixel sprites read as deliberate craft. The previous pass styled the
/// CHROME pixel too (Silkscreen caps, 2px borders, hard offset shadows), which
/// made the sprites compete with their own container and the whole thing look
/// like an unfinished emulator.
///
/// Rules when extending this:
///   • Never put a hard offset shadow on UI chrome again — depth comes from
///     surface elevation + soft shadow.
///   • Never render sprite art through these tokens' smoothing; pixels stay
///     sharp (FilterQuality.none at the Image, not here).
///   • Touch targets are >= [tapTarget]. This is a phone game; there is no
///     hover and no mouse precision.
class FoE {
  FoE._();

  // ── Colours ───────────────────────────────────────────────
  // THE app palette. DARK since 2026-07-31 (user: "setzte das ganze app in den
  // darkmode") — it was the parchment scroll of the Build menu rolled out
  // everywhere, and it is now the same design on dark stock:
  //
  //   Graphite     #161B20 … #2A333A   the surfaces
  //   Cream        #EDE3CB             text and hairlines (the old ink, flipped)
  //   Lawn Green   #A8B84A             primary accent / "good" / actions
  //   Amber        #D9A93C             secondary accent, highlights
  //   Red          #E05548             danger
  //
  // ONE PLACE. The theme is flipped HERE, in the constants, rather than by
  // giving every screen a dark variant: the names carry the ROLE (bg, panelMid,
  // border, textDim) and always did, so a screen that asked for "the card
  // surface" gets the dark card surface without knowing a thing about it. The
  // handful of names that describe the old material rather than the role —
  // `parchment` for the body text — are kept for API stability and say so.
  //
  // Surfaces are STEPS OF GRAPHITE — the page, one step up for cards, another
  // for raised/active — the same hue, not new colours. The creature ELEMENT
  // colours (fire/water/plant/…) are NOT part of this and stay as they are: they
  // encode game meaning, not chrome.
  static const bg = Color(0xFF161B20); // the page

  /// Backdrops for a TILE, in the two states it has — kept as image assets for
  /// the few places that still paint a tile; most surfaces use the parchment
  /// steps below now.
  static const tileActive = 'assets/images/tile_active.jpg';
  static const tileInactive = 'assets/images/tile_inactive.jpg';
  static const panelDark = Color(0xFF1B2126); // recessed / bars
  static const panelMid = Color(0xFF1F262C); // the card surface
  static const panelLight = Color(0xFF2A333A); // raised / active
  static const border = Color(0x33EDE3CB); // hairline

  /// Dim accent hairline — amber taken down, so an accented edge belongs to the
  /// accent rather than becoming a new colour.
  static const borderGold = Color(0x66D9A93C);

  // Amber, lifted off the paper tuning: the old burnt #9A6A18 was picked to
  // read on cream and turns to mud on graphite.
  static const gold = Color(0xFFD9A93C);
  static const goldBright = Color(0xFFF0C25A);
  static const accentBlue = Color(0xFFA8B84A); // lawn green — secondary/actions

  /// Primary body text. Named `parchment` from the old fantasy palette, then the
  /// ink of the light theme, and now the cream that ink was written on — the
  /// name has outlived two palettes and is kept for API stability. It has always
  /// meant "the colour text is".
  static const parchment = Color(0xFFEDE3CB);
  static const textDim = Color(0xFFA79B82); // faded — secondary text
  static const textMuted = Color(0xFF7A7263); // dimmer — disabled

  static const mapBase = Color(0xFF1C2429);
  static const mapAlt = Color(0xFF222B31);
  static const mapGrid = Color(0x14FFFFFF);
  static const danger = Color(0xFFE05548); // red, lifted to read on graphite

  /// "Good" — full HP, gains, ready states: the lawn green.
  static const positive = Color(0xFFA8B84A);

  // ── Shape & metrics ───────────────────────────────────────
  // ── LOW POLY (user 2026-07-31) ──
  // "alles soll im low poly flatdesign sein, so wie dieses Monster … wobei der
  //  dark mode bleibt."
  //
  // The monsters are faceted: flat fills, hard angles, and shading done by
  // NEIGHBOURING FACETS rather than by a gradient or a blur. The chrome now says
  // the same thing, and it says it in these tokens so a screen does not have to
  // know about it.
  //
  // [radius] is a CUT, not a curve. Flutter's BeveledRectangleBorder takes the
  // same number a rounded corner would and slices the corner off instead —
  // which is the single most recognisable low-poly move, and it costs every
  // caller nothing because they already pass a radius.
  //
  // The numbers are smaller than the rounded ones they replace: a 16-px cut is a
  // dramatic chamfer where a 16-px round was a soft pill.
  static const double radius = 10;
  static const double radiusSmall = 7;

  /// A faceted corner — the app's one shape. Pass it to [ShapeDecoration] or to
  /// any Material `shape:`.
  static BeveledRectangleBorder facet({
    double radius = FoE.radius,
    BorderSide side = BorderSide.none,
  }) => BeveledRectangleBorder(
    borderRadius: BorderRadius.circular(radius),
    side: side,
  );

  /// The same cut as a [BorderRadius], for the many places that take one
  /// directly (ClipRRect, InkWell, BoxDecoration). A BorderRadius cannot bevel
  /// on its own — this keeps the RADIUS consistent so a clip lines up with the
  /// shape under it.
  static BorderRadius cut([double r = FoE.radius]) => BorderRadius.circular(r);

  /// A HARD shadow: the offset facet a flat-shaded object casts. No blur, ever —
  /// a blur is the one thing that cannot happen in a faceted world, and it is
  /// what made the old chrome read as soft plastic.
  static List<BoxShadow> drop({double dy = 3, double alpha = 0.45}) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: alpha),
      offset: Offset(dy * 0.6, dy),
      blurRadius: 0,
    ),
  ];

  /// Minimum comfortable touch size. Anything tappable should reach this —
  /// the old layout had 20-24px emoji buttons that are a coin flip on glass.
  static const double tapTarget = 48;

  /// The design viewport. Phone-first: on a wide screen the app is framed to
  /// this width rather than stretched (see PhoneFrame in main.dart), so what
  /// you see while testing in a browser is what ships.
  static const double phoneMaxWidth = 430;

  // ── Gradients ─────────────────────────────────────────────
  // KEPT AS TOKENS, FLATTENED IN VALUE (user 2026-07-31: low poly). Each is now
  // one colour repeated: callers that still ask for a gradient get a flat fill,
  // so nothing had to be rewritten to stop the app looking airbrushed, and a
  // grep for `Gradient` finds the places that should eventually take a plain
  // colour instead.
  static const panelGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [panelMid, panelMid],
  );

  static const topBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [panelDark, panelDark],
  );

  /// Accent fill for primary actions — the lawn green.
  static const goldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [positive, positive],
  );

  // ── Decorations ───────────────────────────────────────────
  /// A panel: one FLAT facet with a cut corner (user 2026-07-31).
  ///
  /// It used to carry [panelGradient]. A gradient is the opposite of flat
  /// shading — in a faceted world a surface is one tone and the next surface is
  /// another, which is why [panelMid] and [panelLight] exist as separate steps.
  /// [glow] is kept for API compatibility and paints nothing.
  static ShapeDecoration panel({
    double radius = FoE.radius,
    Color? overrideBorder,
    bool glow = false,
  }) => ShapeDecoration(
    color: panelMid,
    shape: facet(
      radius: radius,
      side: BorderSide(color: overrideBorder ?? border, width: 1),
    ),
  );

  /// [active] = the primary/selected state: the lawn green, so the important
  /// button reads at a glance on a phone. Flat, borderless (user 2026-07-23),
  /// faceted (2026-07-31).
  static ShapeDecoration btn({bool active = false}) => ShapeDecoration(
    color: active ? positive : panelLight,
    shape: facet(radius: radiusSmall + 3),
  );

  // Seamless header: the same colour as the page background with NO edge, so
  // there is no transition from the status-bar area into the header.
  static const topBarDecor = BoxDecoration(color: bg);

  /// [topBarDecor] mirrored for a bar FIXED to the bottom edge: same flat
  /// surface, hairline on the top side.
  static const bottomBarDecor = BoxDecoration(
    color: panelDark,
    border: Border(top: BorderSide(color: border, width: 1)),
  );

  static BoxDecoration sideBarDecor = const BoxDecoration(
    color: panelDark,
    border: Border(left: BorderSide(color: border, width: 1)),
  );

  // ── Typography ────────────────────────────────────────────
  // One geometric sans everywhere (Outfit): friendly, tight, and legible at
  // 11px on a phone — which the pixel fonts were not. Sizes are passed through
  // as-is; the old title() shaved a point off to compensate for Silkscreen's
  // width, and that hack is gone.
  static TextStyle title({double size = 14}) => GoogleFonts.outfit(
    color: parchment,
    fontSize: size + 2,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    height: 1.2,
  );

  static TextStyle value({double size = 13}) => GoogleFonts.outfit(
    color: parchment, // ink on the parchment (was white on the dark theme)
    fontSize: size + 1,
    fontWeight: FontWeight.w600,
    height: 1.25,
  );

  static TextStyle label({double size = 11}) => GoogleFonts.outfit(
    color: parchment,
    fontSize: size + 1,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static TextStyle dim({double size = 10}) => GoogleFonts.outfit(
    color: textDim,
    fontSize: size + 1,
    fontWeight: FontWeight.w400,
    height: 1.35,
  );

  // ── Divider ───────────────────────────────────────────────
  static Widget divider({double vPad = 4}) => Padding(
    padding: EdgeInsets.symmetric(vertical: vPad + 2, horizontal: 8),
    child: Container(height: 1, color: border),
  );
}
