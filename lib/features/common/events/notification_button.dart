import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart' show pushMenu;
import '../../../core/theme/foe_theme.dart';
import '../../../core/ui/feel.dart';
import '../../creatures/collection_screen.dart';
import '../../creatures/creature_detail_screen.dart';
import '../../creatures/expeditions_screen.dart';
import '../../creatures/hatchery_screen.dart';
import '../../creatures/services/creatures_controller.dart';
import '../../settlement/crafting_screen.dart';
import '../../settlement/settlement_controller.dart';
import '../../settlement/sheets/building_detail_dialog.dart';
import '../../settlement/widgets/parchment_sheet.dart';
import '../widgets/parchment_page.dart';
import 'game_events.dart';
import '../../../core/ui/pressable.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

/// The bell: how many things happened that you haven't looked at, and what.
///
/// Most of this game happens while you are elsewhere — expeditions resolve
/// offline, research finishes on a timer, stationed monsters level up on their
/// own. Without this, those outcomes were either a SnackBar on whatever screen
/// you happened to have open, or nothing at all.
class NotificationButton extends StatelessWidget {
  const NotificationButton({super.key});

  @override
  Widget build(BuildContext context) => NotificationBadge(
    builder: (context, unread, open) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: open,
        borderRadius: vr(FoE.radiusSmall),
        child: SizedBox(
          width: FoE.tapTarget,
          height: FoE.tapTarget,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PixelIcon(
                unread > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: unread > 0 ? FoE.gold : FoE.textDim,
                size: 22,
              ),
              if (unread > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: ShapeDecoration(
                      color: FoE.danger,
                      shape: FoE.facet(
                        radius: 8,
                        side: BorderSide(color: FoE.panelDark, width: 1.5),
                      ),
                    ),
                    child: Text(
                      // Caps the badge: "99+" keeps the header stable no matter
                      // how long you were away.
                      unread > 99 ? '99+' : '$unread',
                      textAlign: TextAlign.center,
                      style: FoE.dim(size: 8).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// THE BELL WITHOUT A SHAPE: how many events are unread, and the action that
/// opens them — nothing about how it looks.
///
/// Split out (user 2026-07-29) because the bell now appears in two very
/// different bodies: the header's flat icon and the settlement's corner pad
/// tile. Both need the same live count and the same "mark read on open" rule,
/// and neither should own a second copy of the listener.
class NotificationBadge extends StatefulWidget {
  final Widget Function(BuildContext context, int unread, VoidCallback open)
  builder;

  const NotificationBadge({super.key, required this.builder});

  @override
  State<NotificationBadge> createState() => _NotificationBadgeState();
}

class _NotificationBadgeState extends State<NotificationBadge> {
  final _log = GameEventLog();

  @override
  void initState() {
    super.initState();
    _log.addListener(_rebuild);
  }

  @override
  void dispose() {
    _log.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _log.unread, () => _open(context));

  void _open(BuildContext context) => showEventSheet(context);
}

/// Opens "What happened". Public so a caller that draws its own bell — the
/// settlement's corner pad — lands in exactly the same sheet, marked read the
/// same way, instead of growing a second copy of this.
void showEventSheet(BuildContext context) {
  // Read on open, not on close: you've seen the count, and leaving it unread
  // would make the badge nag about things already on screen.
  GameEventLog().markAllRead();
  showDialog<void>(context: context, builder: (_) => const _EventSheet());
}

/// WHERE tapping [e] leads — so the feed is a set of doors, not a set of
/// receipts (user 2026-07-30), and each door opens the THING the event is about
/// (user 2026-09-28: a finished building opens that building, a level-up opens
/// that monster). Null when there is nowhere to go.
///
/// Every line here used to be a dead `Container`: "Hunt over" told you and then
/// left you to close the sheet and find the Scout Post yourself.
void Function(BuildContext context)? _eventTarget(GameEvent e) {
  final ref = e.ref;
  switch (e.kind) {
    case GameEventKind.building:
      if (ref == null) return null;
      final ctrl = SettlementController();
      final b = ctrl.buildings.where((b) => b.id == ref).firstOrNull;
      // A building that was deleted since has nothing left to open.
      if (b == null) return null;
      return (context) => showBuildingDetailDialog(context, ctrl, b);
    case GameEventKind.levelUp || GameEventKind.caught:
      if (ref != null &&
          CreaturesController().creatures.any((c) => c.id == ref)) {
        return (context) => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CreatureDetailScreen(creatureId: ref)),
        );
      }
      // No monster behind it (or it is gone): the collection is where they all
      // are, and it is the screen that shows what changed.
      return (context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CollectionScreen()),
      );
    // A menu screen (the expeditions hub) is laid over the map; every other
    // destination is still a full page.
    case GameEventKind.expedition:
      return (context) => pushMenu(context, const ExpeditionsScreen());
    case GameEventKind.breeding:
      return (context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HatcheryScreen()),
      );
    case GameEventKind.craft:
      return (context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CraftingScreen()),
      );
    case GameEventKind.research:
      return null;
  }
}

/// Whether tapping [e] goes anywhere — what decides a row's chevron.
bool gameEventHasDestination(GameEvent e) => _eventTarget(e) != null;

/// Opens what [e] is about. Closes the dialog it was tapped in first: coming
/// back from the screen to a list you have already acted on is a step nobody
/// wants. Shared by the bell and the welcome-back digest.
void openGameEvent(BuildContext context, GameEvent e) {
  final target = _eventTarget(e);
  if (target == null) return;
  Feel.tap();
  final nav = Navigator.of(context);
  nav.pop();
  // The navigator's own context outlives the dialog that was just closed.
  target(nav.context);
}

class _EventSheet extends StatefulWidget {
  const _EventSheet();

  @override
  State<_EventSheet> createState() => _EventSheetState();
}

class _EventSheetState extends State<_EventSheet> {
  final _log = GameEventLog();

  @override
  void initState() {
    super.initState();
    // Live: an expedition can land while the sheet is open.
    _log.addListener(_rebuild);
  }

  @override
  void dispose() {
    _log.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() => _log.markAllRead());
  }

  @override
  Widget build(BuildContext context) => ParchmentDialog(
    title: 'Welcome back',
    child: _log.events.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Nothing yet.\n\nExpeditions, research and your monsters '
                'levelling up will show up here.',
                textAlign: TextAlign.center,
                style: FoE.dim(
                  size: 12,
                ).copyWith(color: ParchmentSheet.inkSoft),
              ),
            ),
          )
        : ListView.separated(
            // +12/+12 (2026-09-06): ParchmentDialog's own bands widened by
            // that on each side.
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: _log.events.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _row(context, _log.events[i]),
          ),
  );

  Widget _row(BuildContext context, GameEvent e) {
    final destination = gameEventHasDestination(e);
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(e.kind.emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            e.message,
            style: FoE.label(size: 12).copyWith(color: ParchmentSheet.ink),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          _ago(e.at),
          style: FoE.dim(size: 9).copyWith(color: ParchmentSheet.inkFaint),
        ),
        // The chevron is the whole affordance — without it a tappable row and a
        // dead one look identical, which is worse than none of them being
        // tappable.
        if (destination) ...[
          const SizedBox(width: 2),
          PixelIcon(
            Icons.chevron_right_rounded,
            size: 16,
            color: ParchmentSheet.inkFaint,
          ),
        ],
      ],
    );
    if (!destination) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: ParchmentSheet.card,
        child: body,
      );
    }
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => openGameEvent(context, e),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: ParchmentSheet.card,
        child: body,
      ),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'now';
    if (d.inHours < 1) return '${d.inMinutes}m';
    if (d.inDays < 1) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
