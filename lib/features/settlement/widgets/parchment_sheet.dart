import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../common/widgets/parchment_page.dart';
import 'meander_strip.dart';
import 'scroll_paper.dart' show kParchmentInk;

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
          decoration: const BoxDecoration(
            // [ParchmentPage.pageGradient], verbatim — the same body the
            // building detail dialog uses (user 2026-09-05: "genau gleich
            // aufgemaut sein wie der Gebäude detailscreen"), replacing the
            // flat single-tone fill this used to be a lit top edge stood in
            // for.
            gradient: ParchmentPage.pageGradient,
          ),
          // The bands run the FULL sheet height now, behind the title band
          // too (user 2026-08-31: "das Mäanderband soll oben weitergehen
          // und 'unter' den Header auf allen Screens") — they used to sit
          // only in the body's own Stack, starting exactly where the title
          // band ends, so the border was a strip down the CONTENT, not down
          // the sheet. The title band (opaque, full width) still covers its
          // own row of it exactly as before.
          child: Stack(
            children: [
              // Wallpaper first, so a band can never land over a card.
              //
              // 14px inset / 16px wide (user 2026-09-06: "das Mäanderband so
              // viel Abstand zum Rand haben wie beim Gebäudedetailscreen"),
              // superseding the 2026-08-30 flush-to-edge decision below — a
              // blanket app-wide rule now, matching building_detail_dialog
              // .dart's own geometry exactly rather than running each sheet's
              // edge to the true edge.
              Positioned(
                left: 14,
                top: 0,
                bottom: 0,
                width: 16,
                // fillHeight (user 2026-09-06: "oben und unten bis zur
                // Kante") — flush top-to-bottom everywhere now.
                child: MeanderStrip(color: ornament, fillHeight: true),
              ),
              Positioned(
                right: 14,
                top: 0,
                bottom: 0,
                width: 16,
                child: MeanderStrip(
                  color: ornament,
                  flip: true,
                  fillHeight: true,
                ),
              ),
              Column(
                // STRETCH (user 2026-08-30: "die Deko an den Rand nehmen") —
                // was the Column default (centre), which gives a loose-width
                // child its own preferred width and then centres the
                // RESULT. The header's Row survives that by accident (an
                // Expanded inside it forces a finite width), but a shrunk
                // child here would get centred, carrying the meander
                // strips in from the true edge with it — not a fixed inset,
                // but drifting with however wide the content happened to be.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── The BAND stays, the handle goes (user 2026-08-01:
                  //    "lösche den oberen Balken und den hellen grauen",
                  //    then "Das Header Band wollte ich behalten") ──
                  //
                  // There were two bars stacked over the title: a light
                  // grey grab handle and, under it, the app's header band.
                  // The handle was the one to lose — it hints at a gesture
                  // that works anywhere on the sheet, so it spends a row
                  // saying what the whole surface already does. The band is
                  // how every titled thing in the app names itself, and a
                  // sheet is no exception.
                  ParchmentHeader.band(
                    child: Padding(
                      // +16/+16 (2026-09-06): the band moved from flush
                      // (edge at 14) to a 14px inset/16px wide band (edge
                      // at 30), matching building_detail_dialog.dart.
                      padding: const EdgeInsets.fromLTRB(36, 10, 32, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: ParchmentHeader.titleStyle(),
                            ),
                          ),
                          if (trailing != null) trailing!,
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: builder(context, scrollCtrl)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
