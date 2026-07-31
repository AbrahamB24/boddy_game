import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';

// Saved battle rosters. The active team is what battleTeam() hands to every
// fight in the game, so this screen is the ONLY place the player says who
// fights — before it existed, the answer was silently "your oldest monsters".
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  final _ctrl = CreaturesController();

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChange);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onChange);
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
    return ParchmentPage(
      title: 'Teams',
      trailing: Text(
        'max ${_ctrl.teamSizeCap} per team',
        style: FoE.dim(size: 11),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: FoE.gold,
        onPressed: () => _editTeam(null),
        icon: const Icon(Icons.add, color: Colors.black),
        label: Text(
          'New team',
          style: FoE.label(size: 13).copyWith(color: Colors.black),
        ),
      ),
      child: teams.isEmpty
          ? _empty()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(ParchmentPage.kParchmentPagePad, 12, ParchmentPage.kParchmentPagePad, 96),
              itemCount: teams.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _teamCard(teams[i]),
            ),
    );
  }

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'No saved teams.\n\nWithout one, fights use the first '
        '${_ctrl.teamSizeCap} monster${_ctrl.teamSizeCap > 1 ? 's' : ''} that '
        'can go — your oldest. Build a team to choose for yourself.',
        textAlign: TextAlign.center,
        style: FoE.dim(size: 12),
      ),
    ),
  );

  Widget _teamCard(SavedTeam team) {
    final members = team.memberIds
        .map(_ctrl.byId)
        .whereType<CreatureInstance>()
        .toList();
    // Members that no longer exist (released, or from a reset profile) are
    // simply absent — the roster is intent, and battleTeam() skips them too.
    final missing = team.memberIds.length - members.length;
    final overCap = members.length > _ctrl.teamSizeCap;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: FoE.panel(
        radius: 12,
        overrideBorder: team.isActive ? FoE.goldBright : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${team.isActive ? '⭐ ' : ''}${team.name}',
                  style: FoE.title(size: 14),
                ),
              ),
              Text(
                '${members.length} 🐾',
                style: FoE.dim(size: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (members.isEmpty)
            Text('Nobody left in this team', style: FoE.dim(size: 11))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in members) _memberChip(c)],
            ),
          if (overCap) ...[
            const SizedBox(height: 6),
            // Not silently trimmed on save: the cap grows with research, so an
            // oversized team becomes legal later. battleTeam() takes the first
            // teamSizeCap in the player's own order until then.
            Text(
              '⚠️ Over the current cap — only the first ${_ctrl.teamSizeCap} '
              'will fight until you research more team size.',
              style: FoE.dim(size: 10).copyWith(color: FoE.gold),
            ),
          ],
          if (missing > 0) ...[
            const SizedBox(height: 6),
            Text(
              '⚠️ $missing member${missing > 1 ? 's are' : ' is'} gone',
              style: FoE.dim(size: 10).copyWith(color: FoE.danger),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _miniBtn(
                team.isActive ? '⭐ Active' : 'Use this team',
                team.isActive
                    ? () => _ctrl.activateTeam(null)
                    : () => _ctrl.activateTeam(team),
              ),
              const SizedBox(width: 6),
              _miniBtn('Edit', () => _editTeam(team)),
              const Spacer(),
              _miniBtn('Delete', () => _confirmDelete(team), danger: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _memberChip(CreatureInstance c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: FoE.panel(radius: FoE.radiusSmall),
    child: Text(
      '${c.isKo ? '💀 ' : ''}${c.displayName} · '
      '${totalPower(c).toStringAsFixed(0)}',
      style: FoE.label(size: 11).copyWith(
        color: c.isKo ? FoE.danger : FoE.parchment,
      ),
    ),
  );

  Future<void> _confirmDelete(SavedTeam team) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: FoE.panelMid,
        title: Text('Delete "${team.name}"?', style: FoE.title(size: 15)),
        content: Text(
          'The monsters are untouched — only the roster goes.',
          style: FoE.dim(size: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text('Keep', style: FoE.label(size: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(
              'Delete',
              style: FoE.label(size: 13).copyWith(color: Colors.redAccent),
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

  Widget _miniBtn(String label, VoidCallback onTap, {bool danger = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: FoE.btn(),
          child: Text(
            label,
            style: FoE.label(
              size: 12,
            ).copyWith(color: danger ? Colors.redAccent : FoE.parchment),
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

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = CreaturesController();
    final cap = ctrl.teamSizeCap;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: FoE.panelMid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(FoE.radius)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.team == null ? 'New team' : 'Edit team',
              style: FoE.title(size: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              decoration: InputDecoration(
                hintText: 'Team name (e.g. Steinteam)',
                hintStyle: FoE.dim(size: 13),
                filled: true,
                fillColor: FoE.panelDark,
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
              style: FoE.dim(size: 11),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in ctrl.creatures) _row(c, cap),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => Navigator.pop(
                  context,
                  _TeamDraft(_name.text, _picked),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: FoE.btn(active: true),
                  alignment: Alignment.center,
                  child: Text(
                    'Save team',
                    style: FoE.label(size: 14).copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
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
    return GestureDetector(
      onTap: () => setState(
        () => picked ? _picked.remove(c.id) : _picked.add(c.id),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: ShapeDecoration(color: picked ? FoE.panelDark : Colors.transparent, shape: FoE.facet(radius: FoE.radiusSmall, side: BorderSide(color: picked ? FoE.goldBright : FoE.border))),
        child: Row(
          children: [
            Text(
              picked ? '${at + 1}.' : '  ',
              style: FoE.value(size: 12).copyWith(color: FoE.goldBright),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.displayName,
                    style: FoE.label(size: 13).copyWith(color: FoE.parchment),
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
                    style: FoE.dim(size: 10).copyWith(
                      color: overCap ? FoE.gold : null,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              totalPower(c).toStringAsFixed(0),
              style: FoE.value(size: 13).copyWith(color: FoE.goldBright),
            ),
          ],
        ),
      ),
    );
  }
}
