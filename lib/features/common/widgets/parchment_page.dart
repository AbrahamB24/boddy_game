import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/theme/strategy_theme.dart';
import '../../settlement/widgets/scroll_paper.dart'
    show
        kPageShadow,
        kParchmentDeep,
        kParchmentInk,
        kParchmentLight,
        kParchmentMid;
import 'app_back_button.dart';
import '../../../core/ui/game_text.dart';

/// THE PAGE'S SHARED MEASURES (was the page every screen is printed on, until
/// every screen moved to [MenuScaffold] — user 2026-09-22 removed the dead widget
/// and its old navy [StrategyScaffold] chrome). What is left is what other files
/// still read: the content inset and the page gradient.
abstract final class ParchmentPage {
  /// Side padding for content that lines up from one screen to the next.
  static const double kParchmentPagePad = 18;

  /// Ornament ink — a shade you notice only when you look for it. Anything
  /// stronger and the border competes with the content.
  static final Color ornament = kParchmentInk.withValues(alpha: 0.22);

  /// The sheet-into-shade transition behind a dialog or sheet (user 2026-09-05:
  /// "Dieser Farbübergang soll der background für jedes Menü sein").
  static const Gradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [kParchmentLight, kParchmentMid],
  );
}

/// The bar at the top of a [ParchmentPage].
///
/// It was a flat 48-px box of one colour with a back arrow and a word in it —
/// correct, and completely inert. What it is now (user 2026-07-27: "bitte den
/// Header noch schöner gestalten"):
///
///  • a LIT BAND rather than a fill: a top-to-bottom gradient with a hairline
///    of white along its top edge, so it reads as a raised strip of the same
///    paper catching the light;
///  • a double rule underneath — a dark line and a light one — which is how a
///    printed page separates a running head from the text;
///  • a soft shadow, so the content scrolls UNDER the bar instead of stopping
///    at an arbitrary line.
///
/// Split out from [ParchmentPage] because the settlement's own screens are not
/// pages (they are a map with a scroll for a nav bar) but still want this bar.
class ParchmentHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final bool showBack;
  final VoidCallback? onBack;

  const ParchmentHeader({
    super.key,
    required this.title,
    this.trailing,
    this.showBack = true,
    this.onBack,
  });

  static const double height = 52;

  /// THE BAND'S FILL — one flat colour (user 2026-07-31: "alle header sollen
  /// keine Farbverlauf haben").
  ///
  /// It was a three-stop gradient with a gloss over its top third: a lit strip
  /// of paper curving under a light. That is a lot of modelling for a bar whose
  /// job is to hold a word and seven numbers, and on dark stock the same
  /// modelling reads as a smear rather than as a surface.
  ///
  /// Exposed (user 2026-07-29: "die Buttons sollen den gleichen Stil haben wie
  /// der Header") so a control that should look cut from this band — the
  /// settlement's corner buttons, the eras pull — uses this exact value instead
  /// of a paler paper that reads as a different material.
  ///
  /// [kParchmentLight], not [kParchmentDeep] (2026-09-05 fix): the blue/warm
  /// reskin spread its three surface steps across a much wider range than the
  /// old graphite ladder ever did, so the "raised" step that used to read as
  /// a subtly lighter shade of the SAME material now reads as a whole
  /// different, washed-out blue next to [ParchmentPage.pageGradient]'s own
  /// teal top stop — user: "der Header und die Buttons haben nicht den
  /// gleichen Blauton wie der Gebäudedetailscreen" (that dialog's card is
  /// exactly [pageGradient]). Matching its top stop here is what makes the
  /// main menu's opaque header/buttons read as the same blue everywhere else
  /// gets it from a gradient instead.
  static const Color bandFill = kParchmentLight;

  /// The band's lit top edge, for a control that draws its own.
  ///
  /// The band itself no longer uses it: it has two real facet edges now — a lit
  /// plane on top, a shaded one at the foot (see [band]) — and a white hairline
  /// over those was the gradient's finishing move, not a facet's.
  static Color get bandHighlight => FoE.lit(bandFill);

  /// The colour a letter or a glyph is CUT INTO the band with — the band's own
  /// material, taken well down towards ink so the recess has a floor.
  ///
  /// Not a text colour in the usual sense: paired with [engraved] it is what
  /// makes lettering read as pressed into the surface rather than printed on
  /// it. A saturated ink here, however deep the shadows, stays a mark lying on
  /// top. Shared with the settlement's corner keys so the two match exactly.
  /// The band's material taken well towards what you write on it with. On dark
  /// stock that means UP, not down — but it is the same rule and the same 0.62,
  /// because [kParchmentInk] flipped with the theme.
  static final Color engravedInk = Color.lerp(
    kParchmentDeep,
    kParchmentInk,
    0.62,
  )!;

  /// The two hairlines that make a cut: the wall in shadow along the top, the
  /// far wall catching the light along the bottom. [depth] scales with the
  /// glyph — a 9px caption cannot carry the offset a 34px icon can.
  ///
  /// Un-blurred since the low-poly pass (2026-07-31): a carved edge in a faceted
  /// world is two hard lines, which is what these were always meant to be.
  /// Re-tuned when the theme went dark (2026-07-31). The GRAMMAR is unchanged —
  /// a wall in shadow above the glyph, a lit wall below it — but the strengths
  /// are not: on paper the shadow does the work and the highlight finishes it,
  /// while on graphite a 0.75 white line under every letter is a neon sign. So
  /// the shadow stays strong (there is plenty of room below black) and the
  /// highlight drops to a hint.
  static List<Shadow> engraved({double depth = 1}) => [
    Shadow(
      color: kPageShadow.withValues(alpha: 0.85),
      offset: Offset(0, -depth),
    ),
    Shadow(
      color: Colors.white.withValues(alpha: 0.16),
      offset: Offset(0, depth),
    ),
  ];

  /// The band's own edge tone. A control CUT from the band still needs an
  /// outline, and the corner keys take theirs from here.
  static final Color bandRule = kParchmentInk.withValues(alpha: 0.28);

  /// What ENDS the band — NOTHING now (user 2026-08-31: "überall diesen
  /// kleinen Schatten unter dem Header entfernen").
  ///
  /// It used to end in a printed double rule, then (2026-07-29) a cast
  /// shadow instead ("der Strich im Header löschen, dafür den Schatten
  /// einfügen") — the band's own [top]/[bottom] BorderSides already say
  /// "raised strip" on their own; the shadow under it turned out to be one
  /// more thing than the header needed.
  static const List<BoxShadow> bandShadow = [];

  /// The band on dark stock: the same three-stop shape, cut from FoE's panels.
  ///
  /// [fill] defaults to the flat [bandFill] every standalone caller (the
  /// battle screen's own bar) still wants. [ParchmentHeader] itself is the
  /// one caller that passes `Colors.transparent`: it sits directly on
  /// [ParchmentPage.pageGradient] now (user 2026-09-05: the page background
  /// gradient runs "inkl. header"), so its own band must let that show
  /// through rather than paint a third, flat tone over it.
  ///
  /// [gradient], when given, OVERRIDES [fill] with a real gradient rather
  /// than showing one through from behind — for a screen that draws its own
  /// band directly on a plain background (the settlement's, user
  /// 2026-09-06: "nimm ... den genau gleichen Hintergrund wie für den
  /// Gebäudedetailscreen" — matching [ParchmentPage.pageGradient] pixel for
  /// pixel rather than [bandFill]'s flat approximation of its top stop).
  /// Same seamless treatment as the transparent case: no facet border lines,
  /// since those draw a seam that only makes sense cutting a flat band off
  /// from a flat page.
  static Widget band({
    required Widget child,
    double? height,
    Color? fill,
    Gradient? gradient,
    // Overrides [bandShadow] (empty everywhere by default, user 2026-08-31).
    // The settlement's own top bar passes a real one (user 2026-09-06: "beim
    // header im hauptscreen noch einen Schatten hinzufügen, damit sich dieser
    // besser von der Map abhebt") — every OTHER caller sits on the flat
    // parchment page, but this one floats directly over the busy isometric
    // map with nothing but colour to separate them.
    List<BoxShadow>? shadow,
  }) {
    final seamless = fill == Colors.transparent || gradient != null;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: gradient == null ? (fill ?? bandFill) : null,
        gradient: gradient,
        boxShadow: shadow ?? bandShadow,
        // The edges come from the band's OWN fill (user 2026-09-20: a teal line
        // still framed the wood bands) — they used to be cut from [bandFill],
        // so any band with another fill got the old blue as its outline.
        // TWO FACETS, no gradient (user 2026-07-31, low poly): the band's top
        // plane catches the light and its foot turns away from it. A border does
        // this in flat colour, where a gradient would have blended the two.
        border: seamless
            ? null
            : Border(
                top: BorderSide(color: FoE.lit(fill ?? bandFill), width: 2),
                bottom: BorderSide(
                  color: FoE.shade(fill ?? bandFill),
                  width: 2,
                ),
              ),
      ),
      child: child,
    );
  }

  /// The band's title, CUT INTO IT. Exposed so a screen that supplies its own
  /// bar content names things in the same hand.
  ///
  /// It was embossed before — ink with a white shadow under it, which raises
  /// lettering off the paper. Engraving is the exact inverse, and it is the
  /// treatment the whole app's chrome now wears.
  static TextStyle titleStyle({double size = 15}) =>
      FoE.title(size: size).copyWith(
        color: engravedInk,
        letterSpacing: 0.3,
        shadows: engraved(depth: 1),
      );

  @override
  Widget build(BuildContext context) => band(
    height: height,
    fill: Colors.transparent,
    child: Padding(
      // 30, not 8 (user 2026-09-06: "auch im header keine Kollisionen mit
      // dem Mäanderband") — the bands now run full page height BEHIND this
      // band too (2026-08-31) and show straight through its transparent
      // fill, so the back arrow and trailing icons sat half inside the
      // band's own 14-30 span at the old 8px inset. 30 clears its outer
      // edge exactly, same as [ParchmentPage.kParchmentPagePad] does for
      // the body below it.
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Row(
        children: [
          if (showBack)
            _BackArrow(onTap: onBack ?? () => Navigator.of(context).pop())
          else
            const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle(),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
            const SizedBox(width: 4),
          ],
        ],
      ),
    ),
  );
}

/// A centred [Dialog] on [ParchmentPage.pageGradient] — the shape a growing
/// list of settlement popups converged on by hand (the building detail
/// dialog, its upgrade preview, Today's Goals) before this pulled the
/// repeated Dialog/Container/ClipRRect/meander-band/header-band scaffolding
/// out once (user 2026-09-06: "was happened ... soll genau so gestaltet
/// sein ... wie todays goals" — a fourth hand-copy of the same ~40 lines was
/// the point this stopped being worth doing per screen).
///
/// [child] is the body — wrap it in a scrollable yourself if it can run
/// long (a `ListView` needs no extra wrapper; a `Column` of variable-length
/// content wants its own `SingleChildScrollView`). This widget only
/// [Flexible]s it so it never forces the dialog past [maxHeightFraction] of
/// the screen.
///
/// Deliberately NOT what building_detail_dialog.dart/building_upgrade_sheet
/// .dart use — both predate this and have a hero/art masthead this generic
/// title-band shape doesn't fit; converting them is a separate, bigger job
/// than pulling out what Today's Goals and this already agreed on by
/// coincidence.
class ParchmentDialog extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;

  /// Fraction of the screen height the dialog may grow to before [child]
  /// (via the [Flexible] wrapping it) has to scroll internally instead.
  final double maxHeightFraction;

  /// False for a caller whose own content already ends in its own exit
  /// action (none do yet, but the option costs nothing to leave open).
  final bool showCloseButton;

  /// A wider card than the default (the away digest lays two columns side by
  /// side); still capped to the screen.
  final double? maxWidth;

  /// The exit button's words ("Continue" on the away digest).
  final String closeLabel;

  /// Runs just before the dialog closes with its exit button.
  final VoidCallback? onClose;

  const ParchmentDialog({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    // Raised from 0.8 (2026-09-18, landscape switch): a fraction of the
    // SHORT axis now (≤430px) rather than a tall portrait screen's height,
    // so the same fraction leaves far fewer absolute pixels than before.
    this.maxHeightFraction = 0.9,
    this.showCloseButton = true,
    this.maxWidth,
    this.closeLabel = 'Close',
    this.onClose,
  });

  // The building dialog's template (user 2026-09-18): a cream card with a flat
  // heading and a gold Close button, no plate behind it. Width is capped against
  // the (short) landscape axis instead of a fixed portrait 400.
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            maxWidth ?? (size.width * 0.62).clamp(360.0, 560.0),
            size.width - 32,
          ),
          maxHeight: size.height * maxHeightFraction,
        ),
        // Fachwerk (2026-11-02): a dialog is a framed wall under a roof.
        child: creamCard(
          framed: true,
          roof: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                // The kit's ONE leaving button, at the right end of the heading
                // (user 2026-09-22: "Zurück und Schliessenbutton vereinheitlichen").
                child: CreamHeading(
                  title: title,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (trailing != null) ...[
                        trailing!,
                        const SizedBox(width: 8),
                      ],
                      if (showCloseButton)
                        KitCloseButton(
                          onTap: () {
                            onClose?.call();
                            Navigator.pop(context);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              Flexible(child: child),
              // A labelled button at the foot only when the dialog has a real action
              // to take ("Continue"); a plain "Close" is the cross above.
              if (showCloseButton && closeLabel != 'Close')
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: ChunkyButton(
                    onTap: () {
                      onClose?.call();
                      Navigator.pop(context);
                    },
                    fill: Strategy.gold,
                    deep: Strategy.goldDeep,
                    expand: true,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      closeLabel,
                      textAlign: TextAlign.center,
                      style: FoE.label(
                        size: 14,
                      ).copyWith(color: Strategy.outline),
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

/// The bar's back arrow: THE APP'S OWN [AppBackButton], not a shape that
/// merely claimed to match it (2026-08-31 audit) — this used to draw its own
/// chevron at its own size (26px `Icons.chevron_left` in a 40×40 tap target),
/// which drifted from [AppBackButton]'s 22px `arrow_back_ios_new` despite
/// this class's own doc comment insisting the two were the same shape. Cut
/// into the band like everything else on it, via [AppBackButton.shadows].
class _BackArrow extends StatelessWidget {
  final VoidCallback onTap;

  const _BackArrow({required this.onTap});

  @override
  Widget build(BuildContext context) => AppBackButton(
    onTap: onTap,
    color: ParchmentHeader.engravedInk,
    shadows: ParchmentHeader.engraved(depth: 1.2),
  );
}
