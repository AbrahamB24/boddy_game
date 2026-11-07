import 'package:flutter/material.dart' hide Text;

import '../../core/theme/foe_theme.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/strategy_theme.dart'
    show chunkyDecoration, strategyDarken;
import '../../core/ui/snack.dart';
import '../../core/ui/scroll_cue.dart';
import '../common/widgets/filter_pills.dart';
import '../settlement/settlement_controller.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'services/overworld_path.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_family.dart';
import 'widgets/picker_detail_panel.dart';
import 'widgets/roster_row.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

// Saved battle rosters. The active team is what battleTeam() hands to every
// fight in the game, so this screen is the ONLY place the player says who
// fights — before it existed, the answer was silently "your oldest monsters".
//
// "Kompakte Zeilen" (user 2026-09-22): one row per team — star, name, the seats as
// monster faces (empty ones as "+", the next one locked with the battle it opens
// at), power, buttons. A banner on top says how many monsters a team may hold and
// what it takes to get another. Built for many teams: the list scrolls, and the
// number of SAVED teams is not limited — only the seats per team come from the map
// (see nextPartySeat).
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  final _ctrl = CreaturesController();
  final _settlement = SettlementController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
    // The seat count follows the battles won.
    _settlement.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
    _settlement.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // battleTeams, not savedTeams: the same table also holds the Market's saved
    // caravans since migration 0028, and they are not fighting rosters.
    final teams = _ctrl.battleTeams;
    final cap = _ctrl.teamSizeCap;
    return MenuScaffold(
      title: 'Teams',
      trailing: _newTeamButton(),
      // No card of its own any more (user 2026-09-30, "hier und andernorts
      // sind noch die alten Kästchen vorhanden") — MenuScaffold is already
      // the one card on screen.
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: teams.isEmpty
            ? _empty(cap)
            : ListView.builder(
                itemCount: teams.length,
                itemBuilder: (_, i) => _teamRow(teams[i], cap),
              ),
      ),
    );
  }

  /// The one control left besides the rows themselves. Any number of teams may be
  /// saved — only the seats per team come from the map (see nextPartySeat).
  Widget _newTeamButton() => Pressable(
    onTap: () => _editTeam(null),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: goldButton(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PixelIcon(Icons.add, size: 16, color: CreamPalette.ink),
          const SizedBox(width: 4),
          Text(
            'New team',
            style: FoE.title(size: 12).copyWith(color: goldButtonInk()),
          ),
        ],
      ),
    ),
  );

  Widget _empty(int cap) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Text(
        'No saved teams.\n\nWithout one, fights use the first '
        '$cap monster${cap > 1 ? 's' : ''} that '
        'can go — your oldest. Build a team to choose for yourself.',
        textAlign: TextAlign.center,
        style: FoE.label(size: 12.5).copyWith(color: kBoxInkSoft, height: 1.4),
      ),
    ),
  );

  // ── One team ──────────────────────────────────────────────
  // A bit bigger than the old 34px avatars (user 2026-10-04: "ein bisschen
  // grösser"), matching the slot size used in the Edit sheet's drag bar.
  static const double _kSeatSize = 44;

  Widget _teamRow(SavedTeam team, int cap) {
    final members = team.memberIds
        .map(_ctrl.byId)
        .whereType<CreatureInstance>()
        .toList();
    // Members that no longer exist (released, or from a reset profile) are
    // simply absent — the roster is intent, and battleTeam() skips them too.
    final missing = team.memberIds.length - members.length;
    final over = members.length > cap ? members.length - cap : 0;
    // What would fight: the first [cap] in the player's order, K.O. ones aside.
    final power = members
        .take(cap)
        .where((c) => !c.isKo)
        .fold<int>(0, (a, c) => a + totalPower(c));
    final next = nextPartySeat(_settlement.battlesCleared);
    final seats = members.length > cap ? members.length : cap;
    final sub = over > 0
        ? '$over sits out'
        : missing > 0
        ? '$missing gone'
        : '${members.length}/$cap seats';
    return Container(
      height: _kSeatSize + 22,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: raisedTile(radius: 12, lit: team.isActive),
      child: Row(
        children: [
          Pressable(
            behavior: HitTestBehavior.opaque,
            onTap: () => team.isActive
                ? _ctrl.activateTeam(null)
                : _ctrl.activateTeam(team),
            child: SizedBox(
              width: 24,
              child: PixelIcon(
                team.isActive ? Icons.star_rounded : Icons.star_border_rounded,
                size: 22,
                // The buttons' light blue (user 2026-11-03), filled when
                // active, outlined when not.
                color: CreamPalette.gold,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 140,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.title(size: 13.5).copyWith(color: kBoxInk),
                ),
                Text(
                  sub,
                  style: FoE.dim(size: 10.5).copyWith(
                    color: over > 0 || missing > 0
                        ? CreamPalette.warn
                        : kBoxInkSoft,
                    fontWeight: over > 0 || missing > 0
                        ? FontWeight.w400
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (var k = 0; k < seats; k++) ...[
                  if (k < members.length && members[k].isKo && k < cap)
                    // A K.O. monster cannot fight, so its seat is as good as
                    // empty (user 2026-09-28: "auch für Monster, welche
                    // kampfunfähig sind") — the same "+" a free seat wears
                    // everywhere else in the app (user 2026-10-04: "diese
                    // sollen überall in der App gleich aussehen"). Still a
                    // real occupant underneath, so it drags like one.
                    Tooltip(
                      message: '${members[k].displayName} is K.O.',
                      child: _dragSeat(
                        index: k,
                        draggable: true,
                        acceptsDrop: true,
                        onDropped: (from) =>
                            _reorderSeat(team, members, from, k),
                        child: _emptySeatBox(() => _editTeam(team)),
                      ),
                    )
                  else if (k < members.length)
                    // Past the cap they hold their place but do not fight.
                    _dragSeat(
                      index: k,
                      draggable: true,
                      acceptsDrop: true,
                      onDropped: (from) => _reorderSeat(team, members, from, k),
                      child: Opacity(
                        opacity: k >= cap ? 0.4 : 1,
                        child: CreatureAvatar.of(
                          members[k],
                          size: _kSeatSize,
                          showHp: false,
                        ),
                      ),
                    )
                  else
                    // Drag a seat here to move it to this empty spot — same
                    // drop target the filled seats are, just nothing to drag
                    // FROM.
                    _dragSeat(
                      index: k,
                      draggable: false,
                      acceptsDrop: true,
                      onDropped: (from) => _reorderSeat(team, members, from, k),
                      child: _emptySeatBox(() => _editTeam(team)),
                    ),
                  const SizedBox(width: 9),
                ],
                if (next != null)
                  Tooltip(
                    message: 'Seat ${cap + 1} from battle ${next.battle}',
                    child: SizedBox(
                      width: _kSeatSize,
                      height: _kSeatSize,
                      child: CustomPaint(
                        painter: DashedRRectPainter(
                          color: CreamPalette.tan.withValues(alpha: 0.5),
                          radius: 10,
                        ),
                        child: Center(
                          child: PixelIcon(
                            Icons.lock_outline,
                            size: 18,
                            color: kBoxInkFaint,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              '$power',
              textAlign: TextAlign.right,
              style: FoE.value(size: 14).copyWith(color: kBoxAccent),
            ),
          ),
          const SizedBox(width: 12),
          team.isActive
              ? _miniBtn('★ Active', () => _ctrl.activateTeam(null))
              : _miniBtn('Use', () => _ctrl.activateTeam(team), active: true),
          const SizedBox(width: 6),
          _miniBtn('Edit', () => _editTeam(team)),
          const SizedBox(width: 6),
          _miniBtn('✕', () => _confirmDelete(team), danger: true),
        ],
      ),
    );
  }

  /// The ONE empty-monster-slot look, app-wide (user 2026-08-30, reaffirmed
  /// 2026-10-04) — [EmptySeat] already is that shared widget; this just
  /// gives it the fixed size every seat in this row (filled or not) shares.
  ///
  /// A "+" invites a tap (user 2026-11-03: "der plus button ist nicht
  /// anwählbar"), so it opens this team in the editor, where the seat is
  /// filled.
  Widget _emptySeatBox(VoidCallback onTap) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      width: _kSeatSize,
      height: _kSeatSize,
      child: EmptySeat(radius: 10),
    ),
  );

  /// Wraps a seat so it can be dragged (if [draggable], long-press) and/or
  /// dropped onto (if [acceptsDrop]) — the exact same drag-reorder gesture
  /// [_TeamEditorSheetState._slotTile] uses, so a team's fight order can be
  /// changed right here without opening Edit (user 2026-10-04: "dann kann
  /// ich diese direkt in diesem Screen verschieben durch dnd").
  Widget _dragSeat({
    required int index,
    required Widget child,
    required bool draggable,
    required bool acceptsDrop,
    required void Function(int from) onDropped,
  }) {
    Widget tile = child;
    if (acceptsDrop) {
      final inner = tile;
      tile = DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => onDropped(details.data),
        builder: (context, candidates, rejected) => candidates.isEmpty
            ? inner
            : DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: vr(10),
                  border: Border.all(color: CreamPalette.gold, width: 3),
                ),
                child: inner,
              ),
      );
    }
    if (!draggable) return tile;
    return LongPressDraggable<int>(
      data: index,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: _kSeatSize, height: _kSeatSize, child: child),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  /// Drags seat [from] onto seat [onto] — reorders [team]'s saved fight
  /// order and persists immediately (there is no Save button in this
  /// compact row, unlike the editor sheet).
  Future<void> _reorderSeat(
    SavedTeam team,
    List<CreatureInstance> members,
    int from,
    int onto,
  ) async {
    if (from == onto || from >= members.length) return;
    final ids = members.map((c) => c.id).toList();
    final id = ids.removeAt(from);
    ids.insert(onto.clamp(0, ids.length), id);
    final err = await _ctrl.setTeamMembers(team, ids);
    if (err != null && mounted) context.snack(err, error: true);
  }

  Future<void> _confirmDelete(SavedTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (dctx) => AlertDialog(
        backgroundColor: CreamPalette.paperTop,
        shape: RoundedRectangleBorder(
          borderRadius: vr(14),
          side: BorderSide(color: CreamPalette.tan, width: 1.5),
        ),
        title: Text(
          'Delete "${team.name}"?',
          style: FoE.title(size: 15).copyWith(color: kBoxInk),
        ),
        content: Text(
          'The monsters are untouched — only the roster goes.',
          style: TextStyle(fontSize: 13, color: kBoxInkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(
              'Keep',
              style: TextStyle(fontSize: 13, color: kBoxInkSoft),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: CreamPalette.warn,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) await _ctrl.deleteTeam(team);
  }

  /// Opens the builder for [team], or — with null — for a brand-new team.
  Future<void> _editTeam(SavedTeam? team) async {
    final result = await showModalBottomSheet<_TeamDraft>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _TeamEditorSheet(team: team),
    );
    if (result == null || !mounted) return;
    final err = team == null
        ? await _ctrl.createTeam(result.name, result.memberIds)
        : await _renameAndSet(team, result);
    if (err != null && mounted) context.snack(err, error: true);
  }

  Future<String?> _renameAndSet(SavedTeam team, _TeamDraft d) async {
    final err = await _ctrl.setTeamMembers(team, d.memberIds);
    if (err != null) return err;
    return _ctrl.renameTeam(team, d.name);
  }

  /// A row button: amber for the main one, the warning colour for Delete,
  /// raised cream for the rest.
  Widget _miniBtn(
    String label,
    VoidCallback onTap, {
    bool danger = false,
    bool active = false,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: danger
          ? chunkyDecoration(
              fill: CreamPalette.warn,
              deep: strategyDarken(CreamPalette.warn, 0.35),
              radius: 10,
              shadowOffset: 2,
            )
          : active
          ? chunkyDecoration(
              fill: CreamPalette.gold,
              deep: CreamPalette.goldDeep,
              radius: 10,
              shadowOffset: 2,
            )
          : raisedTile(radius: 10),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: danger ? CreamPalette.paperTop : kBoxInk,
        ),
      ),
    ),
  );
}

class _TeamDraft {
  final String name;
  final List<String> memberIds;
  const _TeamDraft(this.name, this.memberIds);
}

// The builder itself. Picks from the WHOLE collection — a K.O. or stationed
// monster is still a valid member, it just won't fight while it's out. Saving
// intent rather than a live roster is what lets one team survive a bad run.
class _TeamEditorSheet extends StatefulWidget {
  final SavedTeam? team;
  const _TeamEditorSheet({this.team});

  @override
  State<_TeamEditorSheet> createState() => _TeamEditorSheetState();
}

class _TeamEditorSheetState extends State<_TeamEditorSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.team?.name ?? '',
  );
  late final List<String> _picked = [...?widget.team?.memberIds];

  /// The slot bar index currently armed for a swap-in (user 2026-10-04: "ich
  /// muss Monster austauschen können") — tap a slot (filled or the "+" of an
  /// empty one), then tap a roster monster, and THAT slot gets it, instead
  /// of always appending to the end. Null while nothing is armed, which is
  /// when a roster tap falls back to the old add/remove toggle. Cleared
  /// after every swap and every drag-reorder.
  int? _replaceTarget;

  /// Tapping a roster row only PREVIEWS it here (user 2026-10-05, "Konzept
  /// 4") — the detail panel's own button is what actually adds, removes or
  /// swaps it. Null = nothing tapped yet.
  CreatureInstance? _preview;

  // Sort/filter/search, added everywhere a monster or a group is picked
  // (user 2026-09-11: "überall, wo ich ein Monster oder eine Gruppe
  // auswähle, sollen diese nach dem entsprechenden Wert geordnet sein und
  // eine Sortier, Filter- und Suchfunktion haben"). Same shared pills every
  // other picker uses, ranked by total power by default — the number this
  // list's own row already prints.
  final _search = TextEditingController();
  String _query = '';
  CreatureElement? _filterElement;
  String? _sortKey; // null = total power
  bool _descending = true;

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  List<CreatureInstance> _roster(CreaturesController ctrl) {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final c in ctrl.creatures)
        if ((_filterElement == null || c.species?.element == _filterElement) &&
            (q.isEmpty || c.displayName.toLowerCase().contains(q)))
          c,
    ];
    int cmp(CreatureInstance a, CreatureInstance b) {
      final r = switch (_sortKey) {
        'level' => a.level.compareTo(b.level),
        'name' => a.displayName.compareTo(b.displayName),
        _ => totalPower(a).compareTo(totalPower(b)),
      };
      return _descending ? -r : r;
    }

    list.sort(cmp);
    return list;
  }

  /// Arms/disarms [i] as the swap target — see [_replaceTarget]'s own doc.
  void _tapSlot(int i) =>
      setState(() => _replaceTarget = _replaceTarget == i ? null : i);

  /// A roster tap. With a slot armed, it fills (or replaces) THAT slot
  /// instead of the old append/remove toggle — unless [c] is already on
  /// the team in a DIFFERENT slot, which is ignored rather than
  /// duplicating it (dragging is how an already-picked monster moves).
  void _tapRoster(CreatureInstance c) {
    final existingIndex = _picked.indexOf(c.id);
    final target = _replaceTarget;
    if (target != null) {
      if (existingIndex != -1 && existingIndex != target) return;
      setState(() {
        if (target < _picked.length) {
          _picked[target] = c.id;
        } else {
          _picked.add(c.id);
        }
        _replaceTarget = null;
      });
      return;
    }
    setState(() {
      if (existingIndex != -1) {
        _picked.removeAt(existingIndex);
      } else {
        _picked.add(c.id);
      }
    });
  }

  /// A slot tile was dropped onto slot [onto] — reorders within [_picked]
  /// (fight order). Dropping onto an empty slot (beyond the current
  /// length) just moves it to the end, the only sensible reading of
  /// "there" when there's no gap to actually sit in.
  void _dropOnto(int from, int onto) {
    if (from == onto) return;
    setState(() {
      final id = _picked.removeAt(from);
      _picked.insert(onto.clamp(0, _picked.length), id);
      _replaceTarget = null;
    });
  }

  /// The line-up — every slot up to [cap] (plus any over-cap picks
  /// inherited from a team saved before the cap shrank, still shown so
  /// they can be seen and swapped out rather than silently vanishing).
  /// Filled slots drag to reorder; every slot (filled or the "+" of an
  /// empty one) is also a tap target for [_tapSlot].
  Widget _slotBar(int cap) {
    final slotCount = _picked.length > cap ? _picked.length : cap;
    return SizedBox(
      height: 72,
      child: Row(
        children: [
          for (var i = 0; i < slotCount; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _slotTile(i, cap)),
          ],
        ],
      ),
    );
  }

  Widget _slotTile(int i, int cap) {
    final filled = i < _picked.length;
    final overCap = i >= cap;
    final targeted = _replaceTarget == i;
    final c = filled ? CreaturesController().byId(_picked[i]) : null;

    final box = Container(
      decoration: BoxDecoration(
        color: filled ? null : CreamPalette.tan.withValues(alpha: 0.12),
        gradient: filled
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
              )
            : null,
        borderRadius: vr(10),
        border: Border.all(
          color: targeted
              ? CreamPalette.gold
              : overCap
              ? CreamPalette.warn
              : filled
              ? CreamPalette.goldDeep
              : CreamPalette.tan.withValues(alpha: 0.4),
          width: targeted ? 2.5 : 1.5,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (c != null)
            CreatureAvatar.of(c, size: 36)
          else
            PixelIcon(Icons.add, color: kBoxInkFaint, size: 22),
          if (filled)
            Positioned(
              top: 2,
              left: 3,
              child: Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: kBoxAccent,
                ),
              ),
            ),
        ],
      ),
    );

    Widget tile = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapSlot(i),
      child: box,
    );

    final preDrop = tile;
    tile = DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != i,
      onAcceptWithDetails: (details) => _dropOnto(details.data, i),
      builder: (context, candidates, rejected) => candidates.isEmpty
          ? preDrop
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: vr(10),
                border: Border.all(color: CreamPalette.gold, width: 3),
              ),
              child: preDrop,
            ),
    );

    if (!filled) return tile;
    return LongPressDraggable<int>(
      data: i,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 56, height: 56, child: box),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: tile,
    );
  }

  Widget _controlsRow() => Row(
    children: [
      Expanded(
        flex: 3,
        child: SearchPill(
          controller: _search,
          palette: PillPalette.cream,
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: MenuPill<String>(
          palette: PillPalette.cream,
          icon: Icons.swap_vert,
          label: switch (_sortKey) {
            'level' => 'Level',
            'name' => 'Name',
            _ => 'Power',
          },
          engaged: _sortKey != null || !_descending,
          value: _sortKey ?? '',
          entries: const [
            MapEntry('', 'Power'),
            MapEntry('level', 'Level'),
            MapEntry('name', 'Name'),
          ],
          trailing: PixelIcon(
            _descending ? Icons.arrow_downward : Icons.arrow_upward,
            size: 14,
            color: CreamPalette.accent,
          ),
          selectedTrailing: _descending ? '↓' : '↑',
          onSelected: (v) => setState(() {
            final picked = v.isEmpty ? null : v;
            if (picked == _sortKey) {
              _descending = !_descending;
            } else {
              _sortKey = picked;
              _descending = true;
            }
          }),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        flex: 2,
        child: MenuPill<String>(
          palette: PillPalette.cream,
          icon: Icons.filter_alt_outlined,
          label: _filterElement?.label ?? 'Every type',
          engaged: _filterElement != null,
          value: _filterElement?.name ?? '',
          entries: [
            const MapEntry('', 'Every type'),
            for (final e in CreatureElement.values)
              if (e != CreatureElement.neutral)
                MapEntry(e.name, '${e.emoji} ${e.label}'),
          ],
          onSelected: (v) => setState(
            () =>
                _filterElement = v.isEmpty ? null : CreatureElement.fromName(v),
          ),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final ctrl = CreaturesController();
    final cap = ctrl.teamSizeCap;
    // Capped to a FRACTION of the screen's own height now (2026-09-18) —
    // a plain modal bottom sheet has no natural height limit of its own,
    // and in landscape's short viewport an uncapped Column of controls +
    // roster list could ask for more room than exists at all.
    final maxH = MediaQuery.sizeOf(context).height * 0.86;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(
              top: BorderSide(color: CreamPalette.gold, width: 2.5),
            ),
          ),
          padding: const EdgeInsets.all(16),
          // SCROLLABLE AS A WHOLE now (user-visible bug, 2026-10-05 QA pass):
          // the fixed chrome above the roster — title, name field, slot bar,
          // hint, controls — already eats most of a short landscape
          // viewport's height on its own, which used to leave the roster's
          // own `Expanded` as little as ~27px to work with. A plain
          // `ListView` inside that just clipped silently, but the new
          // detail panel's commit BUTTON has a real minimum size and ended
          // up partly outside the Row's own bounds — un-clickable, not just
          // ugly. Giving the detail/roster row a fixed, GENEROUS height
          // instead and letting the sheet scroll for the rest if the
          // viewport is too short to show it all at once keeps both halves
          // always fully usable.
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.team == null ? 'New team' : 'Edit team',
                  style: FoE.title(size: 16).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  style: FoE.label(size: 14).copyWith(color: kBoxInk),
                  decoration: InputDecoration(
                    hintText: 'Team name (e.g. Steinteam)',
                    hintStyle: FoE.dim(size: 13).copyWith(color: kBoxInkFaint),
                    filled: true,
                    fillColor: CreamPalette.tan.withValues(alpha: 0.16),
                    border: OutlineInputBorder(
                      borderRadius: vr(FoE.radiusSmall),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _slotBar(cap),
                const SizedBox(height: 6),
                Text(
                  _replaceTarget != null
                      ? 'Tap a monster below, then confirm in the panel, to '
                            'fill that slot.'
                      : 'Drag a slot to reorder (fight order) — tap a slot, '
                            'then a monster, to swap it in.',
                  style: FoE.dim(size: 11).copyWith(
                    color: _replaceTarget != null
                        ? CreamPalette.accent
                        : kBoxInkSoft,
                    fontWeight: _replaceTarget != null
                        ? FontWeight.w400
                        : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 8),
                _controlsRow(),
                const SizedBox(height: 8),
                SizedBox(
                  height: 240,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _detail(cap),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final roster = _roster(ctrl);
                            return roster.isEmpty
                                ? RosterRow.emptyState('No monsters.')
                                : ScrollCue(
                                    builder: (context, controller) => ListView(
                                      controller: controller,
                                      shrinkWrap: true,
                                      children: [
                                        for (final c in roster) _row(c, cap),
                                      ],
                                    ),
                                  );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Pressable(
                    onTap: () =>
                        Navigator.pop(context, _TeamDraft(_name.text, _picked)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      alignment: Alignment.center,
                      decoration: goldButton(),
                      child: Text(
                        'Save team',
                        style: FoE.title(
                          size: 14,
                        ).copyWith(color: goldButtonInk()),
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

  /// One roster row via the shared [RosterRow] (user 2026-10-05: "wirklich
  /// überall den gleichen [Monsterpicker] nehmen") — same face/bar/pill/
  /// figure/icon layout the worker-assignment picker uses, with team-editor
  /// values in its slots: Power for the bar, this monster's seat (or why
  /// it has none) for the status pill, Level for the figure. A tap only
  /// PREVIEWS it in [_detail] now — the icon still says what the detail
  /// panel's button will do, but that button is what actually does it.
  Widget _row(CreatureInstance c, int cap) {
    final at = _picked.indexOf(c.id);
    final picked = at >= 0;
    // Over-cap picks are allowed but flagged: the cap grows with research, and
    // silently refusing the 4th monster reads as a bug rather than a rule.
    final overCap = picked && at >= cap;
    // Already on the team in a different slot while one is armed for a
    // swap — a tap here is ignored (see _tapRoster), so it reads as such.
    final blocked = _replaceTarget != null && picked && at != _replaceTarget;
    final statMax = CreaturesController().creatures.fold<int>(
      1,
      (m, o) => totalPower(o) > m ? totalPower(o) : m,
    );
    final (status, kind) = c.isKo
        ? ('💀 K.O.', RosterPillKind.no)
        : overCap
        ? ('Over cap', RosterPillKind.warn)
        : picked
        ? ('Seat ${at + 1}', RosterPillKind.free)
        : ('Not picked', RosterPillKind.no);
    return pickerPreviewFrame(
      active: _preview?.id == c.id,
      child: RosterRow(
        creature: c,
        statValue: totalPower(c),
        statMax: statMax,
        status: status,
        statusKind: kind,
        figureText: 'Lv ${c.level}',
        figureColor: kBoxInkSoft,
        dimmed: blocked,
        actionIcon: picked
            ? Icons.close
            : (_replaceTarget != null ? Icons.swap_horiz : Icons.add),
        actionColor: picked ? CreamPalette.warn : CreamPalette.gold,
        actionIconColor: picked ? Colors.white : CreamPalette.ink,
        onTap: () => setState(() => _preview = c),
      ),
    );
  }

  /// The left panel: power and this monster's seat — what the team editor's
  /// roster is judged on. [action] is the only thing that actually adds,
  /// removes or swaps a member now; tapping a row just fills this in first.
  Widget _detail(int cap) {
    final c = _preview;
    if (c == null) {
      return const PickerDetailPanel(
        placeholder: 'Tap a monster to see its details.',
      );
    }
    final at = _picked.indexOf(c.id);
    final picked = at >= 0;
    final overCap = picked && at >= cap;
    final armed = _replaceTarget != null;
    final blocked = armed && picked && at != _replaceTarget;
    final (status, statusColor) = c.isKo
        ? ('K.O.', CreamPalette.warn)
        : overCap
        ? ('Over cap', CreamPalette.warn)
        : picked
        ? ('Seat ${at + 1}', CreamPalette.better)
        : ('Not picked', kBoxInkSoft);
    final label = blocked
        ? 'On the team already'
        : armed
        ? 'Place in slot ${_replaceTarget! + 1}'
        : picked
        ? 'Remove from team'
        : 'Add to team';
    return PickerDetailPanel(
      art: CreatureCard(creature: c),
      title: c.displayName,
      subtitle: 'Lv ${c.level}',
      rows: [
        pickerStatRow('Power', '⚡ ${totalPower(c)}'),
        pickerStatRow('Status', status, valueColor: statusColor),
      ],
      action: pickerChooseButton(
        label: label,
        onTap: blocked
            ? null
            : () {
                _tapRoster(c);
                setState(() {});
              },
      ),
    );
  }
}
