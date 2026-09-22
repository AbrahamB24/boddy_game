import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/building_icon.dart';
import '../social/widgets/social_kit.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'services/battle_rewards.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_card.dart';
import 'widgets/versus_kit.dart';

// ── Pre-battle briefing (user 2026-07-24) ───────────────────
// Before a fight starts you see WHO you're fighting, WHAT clearing it unlocks,
// and you PICK the monster(s) you take in (up to the battle's party allowance).
// Pops the chosen team (in selection order) — or null if you back out.
//
// LAID OUT AS THE CARD DUEL (user 2026-09-20, "Variante 8, Karten-Duell", with
// the power bar of "Variante 2"): the enemy's cards fanned on top, yours below,
// a VS between them sitting on a bar that splits by the two teams' total power.
// Rewards are a button beside the enemy's cards, saved teams a column beside
// yours. With no enemy to show (Survival, a duel's team pick) only your own fan
// is drawn, larger.
class BattlePrepScreen extends StatefulWidget {
  final String title;
  final List<Combatant> enemies;
  final int partySize;
  final List<RewardLine> rewards;
  final bool isBoss;

  /// Whether to show the "You face" fan above the team. Off for Survival Mode
  /// (user 2026-09-08: "beim survival mode brauche ich 'you face' nicht") —
  /// floor 1's squad is a random preview of nothing durable — and for a duel's
  /// team pick, where the other side is hidden anyway.
  final bool showEnemyPreview;

  /// The commit button's words when at least one monster is picked.
  final String confirmLabel;

  const BattlePrepScreen({
    super.key,
    required this.title,
    required this.enemies,
    required this.partySize,
    required this.rewards,
    this.isBoss = false,
    this.showEnemyPreview = true,
    this.confirmLabel = 'Fight',
  });

  @override
  State<BattlePrepScreen> createState() => _BattlePrepScreenState();
}

class _BattlePrepScreenState extends State<BattlePrepScreen> {
  final _ctrl = CreaturesController();

  final List<String> _selected = [];

  // Tutorial's first fight (user 2026-09-02: "Lass den User das Monster
  // selbst einfügen. Daher zum Start noch kein Monster aktiv") — no default
  // roster is pre-picked, so the player has to add their one starter
  // themselves and see the slot fill in, rather than arriving at an
  // already-solved screen. The spotlight follows that: it lights up the
  // empty "Add" slot first, then hands off to Fight once something is
  // actually picked (see [_tutorialSpotlightAnchor]).
  bool _isFirstBattleTutorial = false;

  // One-time explanation shown BEFORE that Add spotlight (user 2026-09-02:
  // "bevor ich ein Monster hinzufüge, kurz den Screen erklären
  // (Gegner/Belohnung/eigenes Team)") — three different sections of this
  // screen, none of which is a single tappable target, so a dismissible panel
  // says all three at once rather than three separate highlights.
  bool _showPrepIntro = false;

  @override
  void initState() {
    super.initState();
    _isFirstBattleTutorial =
        SettlementController().introStep == IntroStep.firstNode;
    _showPrepIntro = _isFirstBattleTutorial;
    // The scripted fight ahead needs a heal item to actually exist in the
    // bag (user 2026-09-03) — see SettlementController.grantTutorialPotion.
    if (_isFirstBattleTutorial) SettlementController().grantTutorialPotion();
    // Pre-select the default roster so a player can just hit Fight — the
    // saved active team if there is one (battleTeam honours it), else the
    // first N ready. Still fully re-pickable. SKIPPED for the tutorial's
    // first fight: the empty slot is what teaches picking a team at all.
    if (_isFirstBattleTutorial) return;
    final defaults = _ctrl.battleTeam(size: widget.partySize);
    final seed = defaults.isNotEmpty
        ? defaults
        : _ctrl.battleReadyCreatures.take(widget.partySize).toList();
    _selected.addAll(seed.map((c) => c.id));
  }

  String? get _tutorialSpotlightAnchor {
    if (!_isFirstBattleTutorial || _showPrepIntro) return null;
    return _selected.isEmpty ? 'battleprep-add' : 'battleprep-fight';
  }

  List<CreatureInstance> get _team =>
      _selected.map(_ctrl.byId).whereType<CreatureInstance>().toList();

  int get _enemyPower =>
      widget.enemies.fold(0, (sum, e) => sum + combatantPower(e));

  bool get _preview => widget.showEnemyPreview && widget.enemies.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.battleReadyCreatures;
    final anchor = _tutorialSpotlightAnchor;
    return PopScope(
      // Back blocked for the whole tutorial visit (user 2026-09-02: "Battle
      // 1: zurück sollte nicht anwählbar sein") — both the system
      // gesture/hardware button here, and the header's own close via
      // showClose below.
      canPop: !_isFirstBattleTutorial,
      child: MenuScaffold(
        title: widget.title,
        showClose: !_isFirstBattleTutorial,
        trailing: Text(
          'party of ${widget.partySize}',
          style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
        ),
        child: Stack(
          children: [
            _stage(ready),
            if (anchor != null)
              IntroSpotlightOverlay(
                anchorName: anchor,
                hint: anchor == 'battleprep-add'
                    ? 'Add your monster to the team.'
                    : 'Hit Fight when ready.',
              ),
            if (_showPrepIntro) _prepIntroOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _prepIntroOverlay() => Positioned.fill(
    child: Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _showPrepIntro = false),
      child: Container(
        color: CreamPalette.dim,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 360,
          child: creamCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Before you fight',
                  style: FoE.title(size: 15).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 8),
                Text(
                  'Up top: who you face, and what winning gets you. Below: '
                  'your own team — pick who fights. The bar between them '
                  'shows who is stronger.',
                  style: FoE.label(size: 12).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Tap anywhere to continue',
                    style: FoE.dim(size: 11).copyWith(color: kBoxAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // ── The duel ──────────────────────────────────────────────────────────

  /// Tile size for [n] cards in one fan. Two fans share the page's height, so
  /// they are smaller than a lone fan (Survival's pick, a duel's pick).
  (double, double) _tileSize(int n, {required bool alone}) {
    final w = alone
        ? (n <= 4 ? 96.0 : 86.0)
        : (n <= 3 ? 72.0 : (n <= 4 ? 68.0 : 60.0));
    return (w, alone ? 150.0 : w / 0.60);
  }

  Widget _stage(List<CreatureInstance> ready) {
    final team = _team;
    final myPower = team.fold(0, (sum, c) => sum + totalPower(c));
    final alone = !_preview;
    final (mw, mh) = _tileSize(widget.partySize, alone: alone);

    final tiles = <Widget>[
      for (var i = 0; i < widget.partySize; i++)
        i < team.length
            ? CreatureCard(
                creature: team[i],
                onTap: () => _openPicker(ready, slotIndex: i),
              )
            : _emptySlot(ready, isNext: i == team.length),
    ];

    final mine = VersusSide(
      caption: 'Your team',
      power: _preview ? null : '⚡ $myPower',
      fan: ready.isEmpty
          ? versusHint('No battle-ready monster — heal your team first.')
          : VersusFan(cards: tiles, tileW: mw, tileH: mh, down: true),
      trailing: _presets(ready),
    );

    Widget? enemy;
    if (_preview) {
      final (ew, eh) = _tileSize(widget.enemies.length, alone: false);
      enemy = VersusSide(
        caption: 'You face',
        fan: VersusFan(
          cards: [
            for (final e in widget.enemies)
              CreatureCard(creature: enemyInstanceOf(e), showHp: false),
          ],
          tileW: ew,
          tileH: eh,
        ),
        trailing: widget.rewards.isEmpty ? null : _rewardsChip(),
      );
    }

    return VersusStage(
      enemy: enemy,
      middle: _preview
          ? PowerVersusBar(mine: myPower, theirs: _enemyPower)
          : null,
      mine: mine,
      actions: _actions(),
    );
  }

  Widget _emptySlot(List<CreatureInstance> ready, {required bool isNext}) {
    final slot = EmptyMonsterSlot(
      label: isNext ? 'Add' : null,
      onTap: () => _openPicker(ready),
    );
    if (!isNext || _tutorialSpotlightAnchor != 'battleprep-add') return slot;
    return KeyedSubtree(
      key: IntroSpotlightAnchors.of('battleprep-add'),
      child: slot,
    );
  }

  Widget _actions() {
    final canFight = _selected.isNotEmpty;
    return Row(
      children: [
        Text(
          '${_selected.length}/${widget.partySize} chosen',
          style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft),
        ),
        const Spacer(),
        KeyedSubtree(
          key: IntroSpotlightAnchors.of('battleprep-fight'),
          child: SocialGoldButton(
            canFight ? widget.confirmLabel : 'Pick at least one monster',
            height: 38,
            fontSize: 14,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            onTap: canFight ? () => Navigator.of(context).pop(_team) : null,
          ),
        ),
      ],
    );
  }

  // ── Rewards ───────────────────────────────────────────────────────────

  Widget _rewardsChip() => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: _showRewards,
    child: Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: raisedTile(radius: 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'REWARDS',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: kBoxAccent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.rewards.take(4).map((r) => r.emoji).join(' '),
            style: const TextStyle(fontSize: 16),
          ),
          if (widget.rewards.length > 4)
            Text(
              '+${widget.rewards.length - 4} more',
              style: FoE.dim(size: 10).copyWith(color: kBoxInkSoft),
            ),
        ],
      ),
    ),
  );

  /// Everything winning pays — the fan's neighbour only shows the first four.
  Future<void> _showRewards() => showDialog<void>(
    context: context,
    barrierColor: CreamPalette.dim,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SizedBox(
        width: 340,
        child: creamCard(
          padding: const EdgeInsets.all(16),
          corner: const KitCloseButton(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.isBoss ? '👑 Boss rewards' : 'Rewards',
                textAlign: TextAlign.center,
                style: FoE.title(size: 15).copyWith(color: kBoxInk),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final r in widget.rewards)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                height: 36,
                                child: Center(
                                  child: r.buildingId != null
                                      ? BuildingIcon(
                                          defId: r.buildingId,
                                          emoji: r.emoji,
                                          size: 36,
                                        )
                                      : Text(
                                          r.emoji,
                                          style: const TextStyle(fontSize: 20),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  r.text.replaceFirst('New building: ', ''),
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: kBoxInk,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ── Saved teams ───────────────────────────────────────────────────────

  Widget? _presets(List<CreatureInstance> ready) {
    final teams = _ctrl.battleTeams;
    if (teams.isEmpty) return null;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 110, maxWidth: 116),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'SAVED TEAMS',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: kBoxAccent,
              ),
            ),
            const SizedBox(height: 4),
            for (final t in teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _presetChip(t, ready),
              ),
          ],
        ),
      ),
    );
  }

  bool _sameSelection(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _presetChip(SavedTeam team, List<CreatureInstance> ready) {
    final readyIds = {for (final c in ready) c.id};
    final usable = [
      for (final id in team.memberIds)
        if (readyIds.contains(id)) id,
    ].take(widget.partySize).toList();
    final active = usable.isNotEmpty && _sameSelection(_selected, usable);
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: usable.isEmpty
          ? null
          : () => setState(() {
              _selected
                ..clear()
                ..addAll(usable);
            }),
      child: Opacity(
        opacity: usable.isEmpty ? 0.5 : 1,
        child: Container(
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: active ? goldButton() : raisedTile(radius: 10),
          child: Text(
            team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: kBoxInk,
            ),
          ),
        ),
      ),
    );
  }

  // ── Picking ───────────────────────────────────────────────────────────

  Future<void> _openPicker(
    List<CreatureInstance> ready, {
    int? slotIndex,
  }) async {
    await pushMenu<void>(
      context,
      _TeamPickerScreen(
        ready: ready,
        isPicked: (c) => _selected.contains(c.id),
        onPick: (c) => _pick(c, slotIndex),
        chosen: () => _selected.length,
        partySize: widget.partySize,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Applies a tap in the picker. Returns whether the picker should close: a
  /// swap into a slot is exactly one decision, and a now-full team answers the
  /// question; holding the picker open would leave a list that refuses every
  /// further tap.
  bool _pick(CreatureInstance c, int? slotIndex) {
    setState(() {
      if (slotIndex != null) {
        final already =
            slotIndex < _selected.length && _selected[slotIndex] == c.id;
        if (!already) {
          // A SWAP: this id takes over slotIndex, dropped from wherever else it
          // stood so no two slots share a monster. Guarded above — removing it
          // unconditionally would, for a monster already sitting AT slotIndex,
          // shift a later slot's occupant down into slotIndex and then
          // overwrite it, silently dropping that teammate.
          _selected.remove(c.id);
          if (slotIndex < _selected.length) {
            _selected[slotIndex] = c.id;
          } else {
            _selected.add(c.id);
          }
        }
      } else {
        if (_selected.remove(c.id)) return;
        if (_selected.length >= widget.partySize && _selected.isNotEmpty) {
          _selected.removeAt(0);
        }
        _selected.add(c.id);
      }
    });
    return slotIndex != null || _selected.length >= widget.partySize;
  }
}

/// Who fights? — the roster as the Monsters screen's own tiles, with search,
/// sort (combat power by default: what a battle team is judged on) and a type
/// filter. A tick marks who is already in the team.
class _TeamPickerScreen extends StatefulWidget {
  final List<CreatureInstance> ready;
  final bool Function(CreatureInstance) isPicked;

  /// Applies the tap; true = close the picker.
  final bool Function(CreatureInstance) onPick;
  final int Function() chosen;
  final int partySize;

  const _TeamPickerScreen({
    required this.ready,
    required this.isPicked,
    required this.onPick,
    required this.chosen,
    required this.partySize,
  });

  @override
  State<_TeamPickerScreen> createState() => _TeamPickerScreenState();
}

class _TeamPickerScreenState extends State<_TeamPickerScreen> {
  final _search = TextEditingController();
  String _query = '';
  CreatureElement? _filterElement;
  String? _sortKey; // null = combat power
  bool _descending = true;

  static final PillPalette _pills = PillPalette.cream;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CreatureInstance> get _filtered {
    final q = _query.trim().toLowerCase();
    final list = [
      for (final c in widget.ready)
        if ((_filterElement == null || c.species?.element == _filterElement) &&
            (q.isEmpty || c.displayName.toLowerCase().contains(q)))
          c,
    ];
    int cmp(CreatureInstance a, CreatureInstance b) {
      final r = switch (_sortKey) {
        'level' => a.level.compareTo(b.level),
        'name' => a.displayName.compareTo(b.displayName),
        _ => combatPower(a).compareTo(combatPower(b)),
      };
      return _descending ? -r : r;
    }

    list.sort(cmp);
    return list;
  }

  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: 'Who fights?',
    trailing: Text(
      '${widget.chosen()} of ${widget.partySize} chosen',
      style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: creamCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SearchPill(
                    controller: _search,
                    palette: _pills,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _sortPill()),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _filterPill()),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 14, bottom: 16),
                child: monsterTileGrid([for (final c in _filtered) _tile(c)]),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _tile(CreatureInstance c) {
    final picked = widget.isPicked(c);
    return Stack(
      children: [
        Opacity(
          opacity: picked ? 0.45 : 1,
          child: CreatureCard(
            creature: c,
            onTap: () {
              final close = widget.onPick(c);
              setState(() {});
              if (close) Navigator.pop(context);
            },
          ),
        ),
        if (picked)
          const Positioned(
            top: 2,
            left: 2,
            child: Icon(
              Icons.check_circle,
              size: 18,
              color: CreamPalette.better,
            ),
          ),
      ],
    );
  }

  Widget _sortPill() => MenuPill<String>(
    palette: _pills,
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
      color: CreamPalette.goldDeep,
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
  );

  Widget _filterPill() => MenuPill<String>(
    palette: _pills,
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
      () => _filterElement = v.isEmpty ? null : CreatureElement.fromName(v),
    ),
  );
}
