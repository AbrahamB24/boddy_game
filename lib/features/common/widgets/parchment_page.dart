import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/meander_strip.dart';
import '../../settlement/widgets/scroll_paper.dart'
    show kPageShadow, kParchmentDeep, kParchmentInk, kParchmentMid;

/// THE PAGE EVERY SCREEN IS PRINTED ON (user 2026-07-27: "der Hintergrund soll
/// bei allen Screens so sein wie bei monsters" + "bitte den Header noch schöner
/// gestalten bei allen screens").
///
/// Eight screens had grown their own copy of the same three things — the
/// parchment gradient, the meander bands down the edges, a 48-px band with a
/// back button — and half a dozen more were still on the flat [FoE.bg] with no
/// page treatment at all. Copies drift: the bands sat at different insets, the
/// bars were different heights, and a change to "the look" meant eight edits
/// and remembering all eight.
///
/// This is that sheet of paper, once. A screen supplies its title, whatever
/// belongs on the right of the bar, and its body.
///
/// The BODY is laid over the bands, not beside them: they are the page's
/// printed border, and the body's own side padding ([kParchmentPagePad]) is
/// what keeps content off them.
///
/// The page went DARK on 2026-07-31 (user: "setzte das ganze app in den
/// darkmode"), and it did so in the palette rather than here — see the tone
/// ladder in scroll_paper.dart. This widget asks for "the sheet" and "the
/// shade" exactly as it always did; there is no light/dark branch in it,
/// because there is no light page left to branch to.
class ParchmentPage extends StatelessWidget {
  /// Names the page, in the bar.
  final String title;

  /// The page's content. Usually a scrollable padded with
  /// [kParchmentPagePad] horizontally.
  final Widget child;

  /// Sits at the right end of the bar — a count, a purse, a row of icons.
  final Widget? trailing;

  /// Back arrow + its action. Omitting [onBack] pops the route.
  final bool showBack;
  final VoidCallback? onBack;

  /// The meander bordure. Off for pages whose content runs edge to edge.
  final bool bands;

  /// Passed straight to the [Scaffold] — the Teams page's "New team".
  final Widget? floatingActionButton;

  const ParchmentPage({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.showBack = true,
    this.onBack,
    this.bands = true,
    this.floatingActionButton,
  });

  /// Side padding that clears the bands. Every page's content uses it, so the
  /// left edge of a grid on one screen lines up with the next.
  static const double kParchmentPagePad = 24;

  /// Ornament ink — a shade you notice only when you look for it. Anything
  /// stronger and the border competes with the content.
  static final Color ornament = kParchmentInk.withValues(alpha: 0.22);

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kParchmentMid,
    floatingActionButton: floatingActionButton,
    body: DecoratedBox(
      // ONE FLAT SHEET (user 2026-07-31: low poly). The page was a gradient
      // from the lit sheet into its shade — the airbrush a faceted world does
      // not have. Depth is carried by the STEP between surfaces instead: the
      // page is [kParchmentMid], everything laid on it is [kParchmentLight].
      decoration: const BoxDecoration(color: kParchmentMid),
      child: SafeArea(
        child: Column(
          children: [
            ParchmentHeader(
              title: title,
              trailing: trailing,
              showBack: showBack,
              onBack: onBack ?? () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: bands
                  ? Stack(
                      children: [
                        Positioned(
                          left: 4,
                          top: 0,
                          bottom: 0,
                          width: 14,
                          child: MeanderStrip(color: ornament),
                        ),
                        Positioned(
                          right: 4,
                          top: 0,
                          bottom: 0,
                          width: 14,
                          child: MeanderStrip(color: ornament, flip: true),
                        ),
                        child,
                      ],
                    )
                  : child,
            ),
          ],
        ),
      ),
    ),
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

  /// THE BAND ITSELF, WITHOUT THE TITLE ROW — the gradient, the lit top edge,
  /// the double rule and the shadow, wrapped around whatever a screen puts in
  /// it (user 2026-07-29: "bitte auch die Optik an die anderen Header
  /// anpassen").
  ///
  /// Split out because the settlement's top bar is not a running head: it is a
  /// resource strip, two rows tall, and it has to wear this exact band rather
  /// than a hand-rolled lookalike that drifts the next time the band changes.
  /// Pass no [height] and the band takes the height of its child.
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
  static const Color bandFill = kParchmentDeep;

  /// The lit top edge — the same hairline the scroll's roller uses to read as
  /// a cylinder.
  /// The lit top EDGE — a hairline, not a wash. It survives the gradient's
  /// removal because it is what stops a flat bar from reading as a rectangle
  /// somebody forgot to finish, and a line is not a Farbverlauf.
  ///
  /// Turned right down when the theme went dark (2026-07-31): white over a dark
  /// surface climbs in contrast far faster than white over paper, and the 0.55
  /// this used to be was a strip light along the top of the bar.
  static final Color bandHighlight = Colors.white.withValues(alpha: 0.14);

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

  /// The band's own edge tone. The band itself no longer draws a rule — it
  /// casts instead (see [bandShadow]) — but a control CUT from the band still
  /// needs an outline, and the corner keys take theirs from here.
  static final Color bandRule = kParchmentInk.withValues(alpha: 0.28);

  /// What ENDS the band (user 2026-07-29: "der Strich im Header löschen, dafür
  /// den Schatten einfügen").
  ///
  /// It used to end in a printed double rule — a dark hairline with a light one
  /// under it, the way a page separates a running head from its text. That is a
  /// flat, typographic device, and it was the last thing on the band still
  /// pretending the header is ink on paper while everything on it had become a
  /// surface with a light on it. A raised strip does not need a line drawn under
  /// it; it needs to CAST. Two shadows, as on the corner keys: a tight one for
  /// contact, a wide one for height.
  /// FACETED (user 2026-07-31): one hard-edged offset instead of two blurs. A
  /// flat-shaded object does not cast fog — it casts its own silhouette, one
  /// step down and to the side.
  static List<BoxShadow> get bandShadow => FoE.drop(dy: 4, alpha: 0.5);

  /// The band on dark stock: the same three-stop shape, cut from FoE's panels.
  static Widget band({required Widget child, double? height}) => Container(
    height: height,
    decoration: BoxDecoration(color: bandFill, boxShadow: bandShadow),
    child: Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(height: 1.5, color: bandHighlight),
        ),
        child,
      ],
    ),
  );

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
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
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

/// The bar's back arrow: the app's own [AppBackButton] shape, in the ink the
/// band is printed with. Kept private so a page cannot accidentally give its
/// bar a differently-sized one.
class _BackArrow extends StatelessWidget {
  final VoidCallback onTap;

  const _BackArrow({required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 40,
        height: 40,
        // Cut into the band like everything else on it.
        child: Icon(
          Icons.chevron_left,
          size: 26,
          color: ParchmentHeader.engravedInk,
          shadows: ParchmentHeader.engraved(depth: 1.2),
        ),
      ),
    ),
  );
}
