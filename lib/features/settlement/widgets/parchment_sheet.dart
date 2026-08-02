import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart';
import 'meander_strip.dart';
import 'scroll_paper.dart'
    show kParchmentInk, kParchmentMid;

/// The bottom sheet every settlement menu wears (user 2026-07-27: "Bag und
/// Energy sollen im gleichen Stil gestaltet werden wie die anderen neueren
/// menüs").
///
/// The build menu, the building dialog, the worker picker and the breeding
/// screen are all one sheet of paper with meander bands down the sides; the Bag
/// and the Energy sheet were the last two dark panels left, and they are opened
/// from the same bar as the rest. This is that surface, so the next sheet does
/// not have to rebuild it a third time.
///
/// [builder] gets the sheet's own [ScrollController] — hand it to the scrollable
/// inside, or the sheet cannot be dragged by its content.
class ParchmentSheet extends StatelessWidget {
  final String title;

  /// Right-hand side of the header — a count, a total, a small action.
  final Widget? trailing;

  final double initialSize;
  final double minSize;
  final double maxSize;

  final Widget Function(BuildContext context, ScrollController scrollCtrl)
  builder;

  const ParchmentSheet({
    super.key,
    required this.title,
    required this.builder,
    this.trailing,
    this.initialSize = 0.6,
    this.minSize = 0.4,
    this.maxSize = 0.92,
  });

  static const Color ink = kParchmentInk;
  static Color get inkSoft => kParchmentInk.withValues(alpha: 0.78);
  static Color get inkFaint => kParchmentInk.withValues(alpha: 0.55);
  static const Color accent = FoE.gold;

  /// The recess a card sits in on this paper — the same one the building dialog
  /// and the breeding screen use.
  static ShapeDecoration get card => ShapeDecoration(
    color: kParchmentInk.withValues(alpha: 0.06),
    shape: FoE.facet(
      radius: 10,
      side: BorderSide(color: kParchmentInk.withValues(alpha: 0.18)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ornament = kParchmentInk.withValues(alpha: 0.22);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      builder: (_, scrollCtrl) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        child: Container(
          decoration: BoxDecoration(
            // ONE TONE with a lit top edge (2026-07-31, low poly): a sheet is
            // a slab pushed up over the page, and the plane that catches the
            // light is its near edge — not a wash down its whole height.
            color: kParchmentMid,
            border: Border(
              top: BorderSide(color: FoE.lit(kParchmentMid), width: 2),
            ),
          ),
          child: Column(
            children: [
              // ── The BAND stays, the handle goes (user 2026-08-01: "lösche
              //    den oberen Balken und den hellen grauen", then "Das Header
              //    Band wollte ich behalten") ──
              //
              // There were two bars stacked over the title: a light grey grab
              // handle and, under it, the app's header band. The handle was the
              // one to lose — it hints at a gesture that works anywhere on the
              // sheet, so it spends a row saying what the whole surface already
              // does. The band is how every titled thing in the app names
              // itself, and a sheet is no exception.
              ParchmentHeader.band(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(title, style: ParchmentHeader.titleStyle()),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    // Wallpaper first, so a band can never land over a card.
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
                    builder(context, scrollCtrl),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
