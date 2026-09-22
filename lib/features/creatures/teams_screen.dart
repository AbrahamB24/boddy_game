import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/theme/strategy_theme.dart'
    show chunkyDecoration, strategyDarken;
import '../../core/ui/snack.dart';
import '../common/widgets/filter_pills.dart';
import '../settlement/settlement_controller.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'services/overworld_path.dart';
import 'widgets/creature_family.dart';
import '../../core/ui/pressable.dart';

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
      child: creamCard(
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
          const Icon(Icons.add, size: 16, color: CreamPalette.ink),
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
      height: 52,
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
              child: Icon(
                team.isActive ? Icons.star_rounded : Icons.star_border_rounded,
                size: 22,
                color: team.isActive ? CreamPalette.goldDeep : kBoxInkFaint,
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
                        ? FontWeight.w800
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
                  if (k < members.length)
                    // Past the cap they hold their place but do not fight.
                    Opacity(
                      opacity: k >= cap ? 0.4 : 1,
                      child: CreatureAvatar.of(
                        members[k],
                        size: 34,
                        showHp: false,
                      ),
                    )
                  else
                    _seatBox(const Icon(Icons.add, size: 16), faint: false),
                  const SizedBox(width: 8),
                ],
                if (next != null)
                  Tooltip(
                    message: 'Seat ${cap + 1} from battle ${next.battle}',
                    child: _seatBox(
                      Icon(Icons.lock_outline, size: 15, color: kBoxInkFaint),
                      faint: true,
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

  /// A seat with nobody in it: a dashed square, the size of a monster's face.
  Widget _seatBox(Widget child, {required bool faint}) => SizedBox(
    width: 34,
    height: 34,
    child: CustomPaint(
      painter: DashedRRectPainter(
        color: CreamPalette.tan.withValues(alpha: faint ? 0.5 : 0.85),
        radius: 9,
      ),
      child: Center(child: child),
    ),
  );

  Future<void> _confirmDelete(SavedTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (dctx) => AlertDialog(
        backgroundColor: CreamPalette.paperTop,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
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
                fontWeight: FontWeight.w800,
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
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
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
          trailing: Icon(
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
                    borderRadius: BorderRadius.circular(FoE.radiusSmall),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Picked ${_picked.length}/$cap — tap to add or remove. Order is '
                'the order they fight in.',
                style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
              ),
              const SizedBox(height: 8),
              _controlsRow(),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [for (final c in _roster(ctrl)) _row(c, cap)],
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
    );
  }

  Widget _row(CreatureInstance c, int cap) {
    final at = _picked.indexOf(c.id);
    final picked = at >= 0;
    // Over-cap picks are allowed but flagged: the cap grows with research, and
    // silently refusing the 4th monster reads as a bug rather than a rule.
    final overCap = picked && at >= cap;
    return Pressable(
      onTap: () =>
          setState(() => picked ? _picked.remove(c.id) : _picked.add(c.id)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: ShapeDecoration(
          color: picked
              ? CreamPalette.tan.withValues(alpha: 0.18)
              : Colors.transparent,
          shape: FoE.facet(
            radius: FoE.radiusSmall,
            side: BorderSide(
              color: picked
                  ? CreamPalette.accent
                  : CreamPalette.tan.withValues(alpha: 0.45),
            ),
          ),
        ),
        child: Row(
          children: [
            Text(
              picked ? '${at + 1}.' : '  ',
              style: FoE.value(size: 12).copyWith(color: kBoxAccent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayName,
                    style: FoE.label(size: 13).copyWith(color: kBoxInk),
                  ),
                  Text(
                    [
                      'Lv ${c.level}',
                      if (c.isKo)
                        '💀 K.O.'
                      else
                        '${c.hp.toStringAsFixed(0)} HP',
                      if (overCap) 'over cap — sits out',
                    ].join(' · '),
                    style: FoE.dim(size: 10)
                        .copyWith(color: kBoxInkSoft)
                        .copyWith(color: overCap ? CreamPalette.warn : null),
                  ),
                ],
              ),
            ),
            Text(
              totalPower(c).toStringAsFixed(0),
              style: FoE.value(size: 13).copyWith(color: kBoxAccent),
            ),
          ],
        ),
      ),
    );
  }
}
