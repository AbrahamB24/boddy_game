import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart' show vr;

/// THE left-hand detail card every monster picker shares now (user
/// 2026-10-05, "Konzept 4": a filter bar on top, a fixed detail panel on the
/// left, the roster on the right — everywhere a monster can be picked, and
/// tapping a candidate only PREVIEWS it here. Nothing is picked until
/// [action] is pressed, so the panel is always the full story before you
/// commit).
///
/// What fills [rows] differs by screen — combat stats for a battle pick,
/// genes for a breeding parent, the trip stat for an expedition seat — only
/// this frame (and [pickerChooseButton] for the commit itself) is shared.
class PickerDetailPanel extends StatelessWidget {
  final double width;

  /// Null shows [placeholder] instead — nothing has been tapped yet.
  final Widget? art;

  /// FIXED, not aspect-driven (user-visible bug, 2026-10-05 QA pass: the
  /// grid tile's own 0.6 width:height ratio, applied to this panel's narrow
  /// ~128px content width, demanded a ~210px-tall art box — which alone ate
  /// almost every pixel some of these pickers' tight sheets had to give the
  /// whole panel, pushing the stats and even the commit BUTTON off-screen
  /// and partly un-tappable). A modest fixed height leaves the rest of the
  /// panel's real job — the stats, the button — the room it needs.
  final double artHeight;
  final String? title;
  final String? subtitle;
  final List<Widget> rows;
  final Widget? action;
  final String placeholder;

  const PickerDetailPanel({
    super.key,
    this.width = 148,
    this.art,
    this.artHeight = 64,
    this.title,
    this.subtitle,
    this.rows = const [],
    this.action,
    this.placeholder = 'Tap a monster to see its details.',
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: zoneBox(
      padding: const EdgeInsets.all(10),
      child: title == null
          ? Center(
              child: Text(
                placeholder,
                textAlign: TextAlign.center,
                style: FoE.dim(size: 11.5).copyWith(color: kBoxInkFaint),
              ),
            )
          // ONE scroll area for art/title/stats, the commit BUTTON pinned
          // outside and below it (user-visible bug, 2026-10-05 QA pass: a
          // plain Column here overflowed on more than one picker whose
          // sheet gives this panel very little height — e.g. the Team
          // Editor sheet on a short landscape viewport — hiding the stats
          // behind Flutter's overflow banner and leaving the button only
          // PARTLY clickable, since the part of it past the Column's real
          // bounds never participates in hit-testing). Whatever doesn't fit
          // now scrolls instead of overflowing, and the button — the one
          // thing that actually commits a pick — always has its own full,
          // tappable row no matter how cramped the rest gets.
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (art != null) ...[
                          SizedBox(height: artHeight, child: art!),
                          const SizedBox(height: 6),
                        ],
                        Text(
                          title!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.title(size: 13).copyWith(color: kBoxInk),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FoE.dim(size: 10.5).copyWith(
                              color: kBoxAccent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        if (rows.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...rows,
                        ],
                      ],
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action!,
                ],
              ],
            ),
    ),
  );
}

/// One label/value line in a [PickerDetailPanel] — the "necessary
/// information" that differs per task area (power & HP for a battle pick,
/// genes for breeding, the trip stat for an expedition seat).
Widget pickerStatRow(String label, String value, {Color? valueColor}) =>
    Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.value(size: 12).copyWith(color: valueColor ?? kBoxInk),
          ),
        ],
      ),
    );

/// The one commit button every detail panel ends with — gold when [onTap] is
/// set, the kit's own disabled grey otherwise. This is the ONLY thing that
/// actually picks a monster now; tapping a tile just previews it.
Widget pickerChooseButton({required String label, required VoidCallback? onTap}) =>
    Pressable(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: goldButton(active: onTap != null),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.title(
            size: 12,
          ).copyWith(color: goldButtonInk(active: onTap != null)),
        ),
      ),
    );

/// Frames a grid tile in gold while it is the one currently PREVIEWED (not
/// yet chosen) in the detail panel beside it.
Widget pickerPreviewFrame({required Widget child, required bool active}) =>
    !active
        ? child
        : Container(
            decoration: BoxDecoration(
              borderRadius: vr(20),
              border: Border.all(color: CreamPalette.gold, width: 2.5),
            ),
            child: child,
          );
