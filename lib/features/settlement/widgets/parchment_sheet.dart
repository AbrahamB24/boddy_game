import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';

/// The bottom sheet every settlement menu wears (user 2026-07-27: "Bag und
/// Energy sollen im gleichen Stil gestaltet werden wie die anderen neueren
/// menüs").
///
/// Now the building dialog's template (user 2026-09-18: "das gesamte UI an den
/// Gebäudedetailscreen anpassen ... auch die ausklappbaren Menüs"): a cream
/// surface with the map's iso grid faintly in it, a flat heading with a hairline
/// under it, dark navy ink. The [ink] family below is therefore the ink for text
/// ON THIS CREAM — it is navy, whatever the rest of the app's palette does.
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
    // Fractions of the SHORT axis (≤430px): a floor high enough that the title
    // does not crowd out every sheet's content at its default/minimum size.
    this.initialSize = 0.72,
    this.minSize = 0.55,
    this.maxSize = 0.92,
  });

  static const Color ink = kBoxInk;
  static Color get inkSoft => kBoxInkSoft;
  static Color get inkFaint => kBoxInkFaint;
  static const Color accent = kBoxAccent;

  /// A card standing on this cream: the light raised tile every card in the
  /// template uses.
  static Decoration get card => raisedTile(radius: 10);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: initialSize,
      minChildSize: minSize,
      maxChildSize: maxSize,
      builder: (_, scrollCtrl) => creamSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The drag handle: a short bar, so it is clear the sheet moves.
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kBoxInkFaint.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              // The kit's one leaving button at the right end of the heading (user
              // 2026-09-22) — a sheet can still be swiped away, but it can be closed
              // the way every other screen is.
              child: CreamHeading(
                title: title,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailing != null) ...[
                      trailing!,
                      const SizedBox(width: 8),
                    ],
                    const KitCloseButton(),
                  ],
                ),
              ),
            ),
            Expanded(child: builder(context, scrollCtrl)),
          ],
        ),
      ),
    );
  }
}
