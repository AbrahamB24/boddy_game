import 'package:flutter/material.dart';
import 'voxel_kit.dart';

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
  // THE app palette. Blue/warm reskin since 2026-09-05 (user handed over 6
  // hex codes as "die neue Color Palette für das ganze UI") — replacing the
  // 2026-07-31 graphite/lawn-green/amber/red set with a cool NAVY→TEAL
  // surface ramp and a warm CORAL/RED-ORANGE accent pair. Per the user's own
  // role split: the 3 cool tones become the surfaces, the 3 warm tones
  // become accent + danger — and, deliberately, danger and the old amber
  // "secondary accent" collapse into the SAME red-orange rather than staying
  // two separate hues:
  //
  //   Navy         #11395D … #036989 … #5999AF   the surfaces (dark → light)
  //   Cream        #EDE3CB             text and hairlines — UNCHANGED
  //   Coral        #FD9B6C             primary accent / "good" / actions
  //   Red-orange   #DA3D27             secondary accent AND danger, merged
  //   Brick        #8D2F18             shade of the accent / dim hairline
  //
  // ONE PLACE. The theme is flipped HERE, in the constants, rather than by
  // giving every screen a dark variant: the names carry the ROLE (bg, panelMid,
  // border, textDim) and always did, so a screen that asked for "the card
  // surface" gets the dark card surface without knowing a thing about it. The
  // handful of names that describe the old material rather than the role —
  // `parchment` for the body text, `accentBlue` for what is now coral — are
  // kept for API stability and say so.
  //
  // Surfaces are STEPS, not new colours per step: [bg]/[panelMid]/[panelLight]
  // are the 3 given navy tones directly; [panelDark] and the map tones are
  // interpolated between them, same spacing the old graphite ramp used. The
  // creature ELEMENT colours (fire/water/plant/…) are NOT part of this and
  // stay as they are: they encode game meaning, not chrome.
  // BLUE IS GONE (user 2026-09-22: "Alle blauen Reste im UI ersetzen. Bsp HP
  // Balken"). The navy/teal surfaces and the cyan accent are now the kit's own
  // wood browns, gold and green, so any screen still painted from these tokens
  // (battle chrome, the dev tools) matches the cream kit around it. Names and
  // roles are unchanged; only the values moved. Element colours (water, ice) and
  // the energy bar's 100–125 % cyan stay: they carry meaning.
  static const bg = Color(
    0xFF12313C,
  ); // the page (Fachwerk 2026-11-02: timber in shade)

  static const panelDark = Color(
    0xFF1B4756,
  ); // recessed / bars — bg→panelMid, closer to bg
  static const panelMid = Color(0xFF25596B); // the card surface

  static const panelLight = Color(0xFF3A7F96); // raised / active
  static const border = Color(0x33EDE3CB); // hairline

  /// Dim accent hairline — the accent taken down, so an accented edge belongs
  /// to the accent rather than becoming a new colour.
  static const borderGold = Color(0x66F5B83A);

  // Cyan-blue (2026-09-05, third pass) — coral turned out to be the wrong
  // call too: it read fine as a swatch but clashed as an actual highlight
  // against the navy/teal chrome once seen in the app (user, on the Build
  // menu's active tab and card: "bitte nicht koralle nehmen als Farbe,
  // sondern einen anderen Blauton"). A bright, more SATURATED blue than the
  // surface ladder (bg/panelMid/panelLight are all fairly desaturated navy
  // and steel) is what actually reads as "active" against them — the same
  // hue family instead of a warm one, but distinct in saturation/lightness
  // rather than in hue. [danger] is unaffected either time — still its own
  // red-orange, for alerts only.
  static const gold = Color(0xFF3FD0D0); // the kit's gold (was cyan-blue)
  static const goldBright = Color(0xFF7FE8E8); // lit version of gold
  static const accentBlue = Color(0xFF3FD0D0); // name kept; it is gold now

  /// Primary body text. Named `parchment` from the old fantasy palette, then the
  /// ink of the light theme, and now the cream that ink was written on — the
  /// name has outlived two palettes and is kept for API stability. It has always
  /// meant "the colour text is".
  static const parchment = Color(0xFFF1F6F8);
  static const textDim = Color(0xFFB4CEDB); // faded — secondary text
  static const textMuted = Color(0xFF8FAEBD); // lifted for the pixel face (2026-11-03) // dimmer — disabled

  static const mapBase = Color(0xFF1B4756); // == panelDark
  static const mapAlt = Color(0xFF21505F); // panelDark→panelMid midpoint
  static const mapGrid = Color(0x14FFFFFF);
  // Coral now (user 2026-09-06: "alle Warnhinweise sollen in der Farbe
  // Koralle sein"), not its own red-orange — every alert in the app reads
  // [danger], so this is the one place that recolours all of them at once.
  // Same hex as [coral] below (0xFFFD9B6C); written out rather than aliased
  // to it because [coral] is declared later in this file and a `const`
  // can't forward-reference.
  static const danger = Color(0xFFFF8A5C);

  /// "Good" — full HP, gains, ready states: green (was the accent's cyan-blue).
  /// The same green the type chart's bonus arrows use.
  static const positive = Color(0xFF2FCB86);

  /// A resource sitting AT or OVER its storage cap — not [positive]/[gold] (a
  /// ready/active state): a full store is neither, it is a ceiling worth
  /// noticing so you build more storage or spend the surplus down. The
  /// original pre-reskin accent (see this file's own palette history above),
  /// retired everywhere else on 2026-09-05.
  ///
  /// Same hex as [danger] since later that day ("alle Warnhinweise sollen in
  /// der Farbe Koralle sein") — this stopped being a hue that set warnings
  /// apart from real alerts the moment [danger] itself became this colour;
  /// the two names now just mark two different REASONS to reach for the
  /// identical value.
  static const coral = Color(0xFFFF8A5C);

  // A warm cream→tan pair (user 2026-09-05), for surfaces that want to read
  // as a light card against the navy/teal chrome rather than another step of
  // it — the expedition target tiles were tinted per-resource (brown for
  // Wood, grey for Stone, gold for Gold) before this; now every tile shares
  // this same pair regardless of what it targets. Dark ink ([bg]) belongs on
  // both, the same rule [parchmentButtonInk] uses for a fill this light.
  static const cream = Color(0xFF1F4E63);
  static const tan = Color(0xFF4C8CA6);

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
  // ── ROUNDED AGAIN (user 2026-08-04: "bringe wieder mehr Rundungen ins UI,
  //    so ist es zu extrem") ──
  // The corners were CUT — BeveledRectangleBorder, which takes the number a
  // rounded corner would and slices the corner off instead. On a monster that
  // chamfer is one facet among dozens and reads as carved. On a full-width
  // panel it is two long diagonals across the screen, and every stacked card
  // repeats them until the layout looks like it was trimmed with scissors.
  //
  // Low poly still holds where it belongs: flat fills, hard drop shadows, and
  // shading by neighbouring facets ([lit]/[shade]) — none of that changed. Only
  // the outline is soft again.
  //
  // The numbers go back UP with the shape. A 10-px cut is a dramatic chamfer;
  // a 10-px round is barely visible, so keeping the bevel's radii would have
  // read as square rather than as soft.
  static const double radius = 16;
  static const double radiusSmall = 11;

  /// The app's one shape. Pass it to [ShapeDecoration] or any Material
  /// `shape:`. Still called `facet` because every caller says `FoE.facet(...)`
  /// and the name is about WHICH shape, not about its corners.
  static OutlinedBorder facet({
    double radius = FoE.radius,
    BorderSide side = BorderSide.none,
  }) => VoxelShape(
    notch: radius >= 14 ? 3 : (radius >= 8 ? 2 : 1),
    // A near-opaque side (a selection ring, a gold edge) keeps its colour as
    // the block outline; a faint hairline just means "an edge" and gets the
    // kit's dark outline, which is what reads on both cream and navy.
    edge: (side.style != BorderStyle.none && side.color.a >= 0.85)
        ? side.color
        : null,
  );

  /// The same corner as a [BorderRadius], for the many places that take one
  /// directly (ClipRRect, InkWell, BoxDecoration). Keeps the RADIUS consistent
  /// so a clip lines up with the shape under it.
  static BorderRadius cut([double r = FoE.radius]) => vr(r);

  /// ── THE FACET STEPS ──
  /// A faceted object is shaded by ITS NEIGHBOURS: one plane catches the light,
  /// the next one does not, and the edge between them is the whole effect. These
  /// two make that edge from any colour, so a surface can have a lit side and a
  /// shaded side without a gradient anywhere.
  ///
  /// The amounts are deliberately blunt. A 4 % lift is a gradient's idea of a
  /// facet; 14 % is a plane turning away from a light.
  static Color lit(Color c) => Color.lerp(c, Colors.white, 0.14)!;
  static Color shade(Color c) => Color.lerp(c, Colors.black, 0.22)!;

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

  /// The design viewport's SHORT axis — a landscape phone's height (2026-09-18:
  /// the app-wide switch to landscape). On a bigger screen the app is framed
  /// to this instead of stretched (see PhoneFrame), so what you see while
  /// testing in a browser is what ships.
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
  //
  // decoration: TextDecoration.none is explicit on every one of these (user
  // 2026-09-06: "nie mit Unterstrich", after a tutorial hint bubble rendered
  // underlined) — none of these four ever left it unset before, which meant
  // whatever ambient DefaultTextStyle a widget happened to inherit (Flutter's
  // own no-DefaultTextStyle-ancestor fallback carries an underline) could
  // survive the merge into Text's actual style. Setting it here, once, wins
  // that merge everywhere these are used instead of it being one more thing
  // every call site has to remember to override for itself.
  static final Map<double, TextStyle> _titleCache = {};
  static TextStyle title({double size = 14}) =>
      _titleCache[size] ??= TextStyle(
        fontFamily: Voxel.font,
        color: parchment,
        fontSize: (size + 2).roundToDouble(),
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.2,
        decoration: TextDecoration.none,
      );

  static final Map<double, TextStyle> _valueCache = {};
  static TextStyle value({double size = 13}) =>
      _valueCache[size] ??= TextStyle(
        fontFamily: Voxel.font,
        color: parchment, // ink on the parchment (was white on the dark theme)
        fontSize: (size + 1).roundToDouble().clamp(12.0, 99.0),
        fontWeight: FontWeight.w400,
        height: 1.25,
        decoration: TextDecoration.none,
      );

  static final Map<double, TextStyle> _labelCache = {};
  static TextStyle label({double size = 11}) =>
      _labelCache[size] ??= TextStyle(
        fontFamily: Voxel.font,
        color: parchment,
        fontSize: (size + 1).roundToDouble().clamp(12.0, 99.0),
        fontWeight: FontWeight.w400,
        height: 1.4,
        decoration: TextDecoration.none,
      );

  static final Map<double, TextStyle> _dimCache = {};
  static TextStyle dim({double size = 10}) =>
      _dimCache[size] ??= TextStyle(
        fontFamily: Voxel.font,
        color: textDim,
        fontSize: (size + 1).roundToDouble().clamp(12.0, 99.0),
        fontWeight: FontWeight.w400,
        height: 1.35,
        decoration: TextDecoration.none,
      );
}
