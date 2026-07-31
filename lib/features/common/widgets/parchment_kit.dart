import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../settlement/widgets/parchment_sheet.dart';
import '../../settlement/widgets/scroll_paper.dart'
    show
        kActionGreen,
        kParchmentInk,
        kParchmentLight,
        kParchmentMid,
        parchmentButton,
        parchmentButtonInk;
import 'parchment_page.dart';

// ── The pieces a parchment SCREEN is made of ───────────────────────────────
//
// ParchmentPage gave every screen the same sheet of paper and the same running
// head; ParchmentSheet did it for the bottom sheets. What neither covered is
// what goes ON the paper — the section rules, the cards, the buttons — so each
// screen grew its own, and several never converted at all: the expeditions hub
// was still printing DARK panels and dark buttons onto a light page, which is
// two materials in one frame.
//
// These are those pieces, once. Nothing here is novel: every value is lifted
// from the screens that were already right (the building dialog, the healing
// hut, the market), so adopting the kit changes nothing visually on them and
// fixes the ones that drifted.

/// Ink at its three strengths — the same trio every parchment surface uses.
/// Re-exported from [ParchmentSheet] so a screen needs one import, not two.
const Color kInk = ParchmentSheet.ink;
Color get kInkSoft => ParchmentSheet.inkSoft;
Color get kInkFaint => ParchmentSheet.inkFaint;

/// The warm accent that marks a value worth looking at.
const Color kAccent = ParchmentSheet.accent;

/// A heading with its one-line status, and a rule running to the edge.
///
/// The rule is what makes a long scroll readable: without it the sections run
/// together and the eye has nothing to catch on the way down.
class ParchmentSectionHeader extends StatelessWidget {
  final String title;

  /// What this section is currently worth reading for — "2 on the road".
  final String? hint;

  /// A control at the far right — usually an [ParchmentInfoButton] holding the
  /// reference material the section itself is better off without.
  final Widget? trailing;

  const ParchmentSectionHeader({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title.toUpperCase(),
          style: FoE.label(size: 11).copyWith(
            color: kAccent,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: kParchmentInk.withValues(alpha: 0.18)),
        ),
        if (hint != null) ...[
          const SizedBox(width: 10),
          Text(hint!, style: FoE.dim(size: 10).copyWith(color: kInkFaint)),
        ],
        if (trailing != null) ...[
          const SizedBox(width: 6),
          trailing!,
        ],
      ],
    ),
  );
}

/// A small ⓘ that opens reference material.
///
/// The point is what it lets a screen NOT show (user 2026-07-30, on the hunt
/// sheet: "Seltenheit kann in ein kleines 'i' gepackt werden"). Odds tables and
/// timing tables never change with the choice being made, so on the page they
/// are a wall between the player and the decision; behind an ⓘ they are still
/// one tap away for whoever wants them.
class ParchmentInfoButton extends StatelessWidget {
  final String title;

  /// Built when opened, so a table that depends on the current selection is
  /// computed fresh rather than captured stale.
  final List<Widget> Function(BuildContext context) content;

  const ParchmentInfoButton({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => showDialog<void>(
      context: context,
      builder: (dctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [kParchmentLight, kParchmentMid],
            ),
            border: Border.all(color: kParchmentInk.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: FoE.title(size: 15).copyWith(color: kInk)),
              const SizedBox(height: 10),
              ...content(dctx),
              const SizedBox(height: 14),
              ParchmentButton(
                label: 'Close',
                expand: true,
                onTap: () => Navigator.pop(dctx),
              ),
            ],
          ),
        ),
      ),
    ),
    child: Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kAccent.withValues(alpha: 0.6)),
      ),
      child: Text(
        'i',
        style: FoE.label(size: 11).copyWith(color: kAccent),
      ),
    ),
  );
}

/// A card on the paper: the shallow recess the building dialog and the breeding
/// screen use, with an optional accent border for the one that wants attention.
class ParchmentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;

  /// Marks the card as the one to act on — a landed trip, a ready egg.
  final bool highlight;

  /// Dims the whole card: a target that can't be sent right now.
  final bool muted;

  final VoidCallback? onTap;

  const ParchmentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.highlight = false,
    this.muted = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final card = AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: muted ? 0.55 : 1,
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: ShapeDecoration(color: highlight
              ? kAccent.withValues(alpha: 0.12)
              : kParchmentInk.withValues(alpha: 0.06), shape: FoE.facet(radius: 10, side: BorderSide(color: highlight
                ? kAccent.withValues(alpha: 0.55)
                : kParchmentInk.withValues(alpha: 0.18),
            width: highlight ? 1.4 : 1))),
        child: child,
      ),
    );
    if (onTap == null) return card;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: card,
    );
  }
}

/// The button every parchment screen presses.
///
/// One shape, four moods: the plain paper key, the [primary] one that carries
/// the screen's action, a [danger] one, and disabled. It used to be
/// hand-rolled per screen — and on the expeditions hub it was the DARK
/// [FoE.btn], which is a control from a different app.
class ParchmentButton extends StatelessWidget {
  final String label;

  /// A second, quieter line — a cost, a duration, a count.
  final String? sub;

  final VoidCallback? onTap;
  final bool primary;
  final bool danger;

  /// Fills the width. Off by default so buttons can sit in a row.
  final bool expand;

  const ParchmentButton({
    super.key,
    required this.label,
    this.sub,
    this.onTap,
    this.primary = false,
    this.danger = false,
    this.expand = false,
  });

  bool get _enabled => onTap != null;

  @override
  Widget build(BuildContext context) {
    final ink = danger
        ? (_enabled ? const Color(0xFF9B3B22) : kInkFaint)
        : parchmentButtonInk(active: primary && _enabled);
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: _enabled ? 1 : 0.5,
        child: Container(
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          alignment: Alignment.center,
          decoration: parchmentButton(active: primary && _enabled),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(size: 13).copyWith(color: ink),
              ),
              if (sub != null) ...[
                const SizedBox(height: 2),
                Text(
                  sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10).copyWith(color: ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A readout CUT INTO the running head — the slot count, a purse, a tally.
///
/// The header band is a raised strip of parchment with everything on it
/// engraved; a filled chip with a coloured border sits ON it instead, which is
/// the one thing that made the expeditions bar look bolted together.
class ParchmentHeaderChip extends StatelessWidget {
  final String text;

  /// Marks the count as spent — nothing left, everything busy.
  final bool alert;

  const ParchmentHeaderChip({super.key, required this.text, this.alert = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      text,
      style: FoE.value(size: 12).copyWith(
        color: alert
            ? const Color(0xFF9B3B22)
            : ParchmentHeader.engravedInk,
        shadows: ParchmentHeader.engraved(depth: 1),
      ),
    ),
  );
}

/// A small labelled figure — "3 🐾  ·  Danger 2". Used in card headers where a
/// full row per fact would be three rows of almost nothing.
class ParchmentFact extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const ParchmentFact({
    super.key,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        value,
        style: FoE.value(size: 14).copyWith(color: color ?? kInk),
      ),
      Text(label, style: FoE.dim(size: 9).copyWith(color: kInkFaint)),
    ],
  );
}

/// The app's own confirm box, on paper.
///
/// [showDialog] with Material's AlertDialog was the last dark surface the
/// expeditions hub put on screen: a near-black panel over a parchment page,
/// for the one moment the player is being asked to be sure.
Future<bool> parchmentConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Keep',
  bool danger = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kParchmentLight, kParchmentMid],
          ),
          border: Border.all(color: kParchmentInk.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: FoE.title(size: 16).copyWith(color: kInk)),
            const SizedBox(height: 8),
            Text(
              message,
              style: FoE.label(size: 12).copyWith(color: kInkSoft),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ParchmentButton(
                    label: cancelLabel,
                    expand: true,
                    onTap: () => Navigator.pop(dctx, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ParchmentButton(
                    label: confirmLabel,
                    expand: true,
                    danger: danger,
                    primary: !danger,
                    onTap: () => Navigator.pop(dctx, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return ok ?? false;
}

/// The colour a positive/"go" state is drawn in on paper — the action green
/// the parchment buttons already use, so a progress bar and the button that
/// starts it agree.
const Color kParchmentGo = kActionGreen;
