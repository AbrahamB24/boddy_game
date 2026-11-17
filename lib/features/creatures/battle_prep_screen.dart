import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/filter_pills.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/settlement_controller.dart';
import '../social/widgets/social_kit.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'services/battle_rewards.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_card.dart';
import 'widgets/enemy_card.dart';
import 'widgets/trading_card.dart';
import 'widgets/picker_detail_panel.dart';
import 'widgets/picker_stage.dart';
import 'widgets/versus_kit.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

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
    // Deferred a frame: called straight from initState it ran while
    // SettlementScreen (this screen's own pusher) was still mid-build, and
    // the grant's notifyListeners chain (_grantItems -> NewItems.add) tried
    // to setState() it right then — "setState() or markNeedsBuild() called
    // during build" (caught live 2026-09-30 QA pass; Flutter's debug handler
    // swallowed it so nothing looked wrong on screen, but it is still a real
    // framework violation worth not shipping).
    if (_isFirstBattleTutorial) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => SettlementController().grantTutorialPotion(),
      );
    }
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
      // "Before you fight" is a SIBLING of MenuScaffold now, not nested
      // inside its own `child` slot (user 2026-09-30: "nicht der ganze
      // screen aussen ist abgedunkelt") — nested there, its Positioned.fill
      // only covered MenuScaffold's own content area, leaving the header
      // ("Battle 1 / party of 1") undimmed outside it. Out here it fills
      // the whole route instead.
      child: Stack(
        children: [
          MenuScaffold(
            title: widget.title,
            showClose: !_isFirstBattleTutorial,
            showHairline: false,
            child: _stage(ready),
          ),
          // Sibling of MenuScaffold, not nested in its `child` — the same fix
          // _prepIntroOverlay below already has (user 2026-10-01: "hier den
          // ganzen screen abdunkeln, das heisst auch den Rand" — nested, the
          // dim only reached MenuScaffold's own content slot, leaving the
          // header ("Battle 1 / party of 1") and its hairline undimmed).
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
                  // Reworded twice now (user 2026-09-30): first pass dropped
                  // "the bar between them shows who is stronger"; this pass
                  // swaps "the rewards below" for "great rewards" — "below"
                  // pointed at a screen region this overlay itself now
                  // hides.
                  'You can see what you face, and set your team to earn '
                  'great rewards.',
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

  /// A hand of at most [kMaxPerSide] cards (user 2026-11-15: "die Trading Cards
  /// sollen genau gleich gross sein, immer â€” nur die Positionierung Ã¤ndert
  /// sich"). The card size depends ONLY on the room of one side (never on how
  /// many monsters stand there), so every card on the page is the same size: as
  /// big as six side by side fit, and as tall as the row allows. Fewer cards
  /// are centred.
  static const int kMaxPerSide = 6;

  static const double _gap = 8;
  static const double _presetsW = 92;
  static const double _capH = 22;
  static const double _barH = 40;

  /// One card size for the whole page (mine and the opponent's): what the
  /// larger hand needs in ONE row, within the height of one row.
  Size _cardSize({
    required double availW,
    required double rowH,
    required int cols,
  }) {
    final byW = (availW - _gap * (cols - 1)) / cols;
    final byH = rowH * 0.72;
    var w = byW < byH ? byW : byH;
    if (w / 0.72 > 320) w = 320 * 0.72;
    if (w < 40) w = 40;
    return Size(w, w / 0.72);
  }

  /// A hand in one centred row.
  Widget _row(List<Widget> allCards, Size card) {
    final cards = allCards.take(kMaxPerSide).toList();
    final n = cards.length;
    return Align(
      alignment: const Alignment(0, -0.7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var j = 0; j < n; j++)
            Padding(
              padding: EdgeInsets.only(left: j == 0 ? 0 : _gap),
              child: SizedBox(
                width: card.width,
                height: card.height,
                child: Transform.rotate(
                  angle: (j - (n - 1) / 2) * 0.04,
                  child: cards[j],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _caption(String text, {String? sub}) => SizedBox(
    height: _capH,
    child: Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.9,
            color: kBoxAccent,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(width: 8),
          Text(sub, style: FoE.dim(size: 11.5).copyWith(color: kBoxInkSoft)),
        ],
      ],
    ),
  );

  // The duel (user 2026-11-16, composition 2 of 10): the opponent's hand on
  // top, the power bar with VS between the hands, yours below with the saved
  // teams at the left edge, Fight bottom right. All cards one size.
  Widget _stage(List<CreatureInstance> ready) {
    final team = _team;
    final myPower = team.fold(0, (sum, c) => sum + totalPower(c));

    final tiles = <Widget>[
      for (var i = 0; i < widget.partySize; i++)
        i < team.length
            ? TradingCard(
                team[i],
                onTap: () => _openPicker(ready, slotIndex: i),
              )
            : _emptySlot(ready, isNext: i == team.length),
    ];

    final presets = _presetsColumn(ready);
    final presetsW = presets != null ? _presetsW : 0.0;
    final enemyCards = [for (final e in widget.enemies) EnemyCard(e)];

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final rows = _preview ? 2 : 1;
                final fixed = _preview ? _barH : _capH;
                final rowH = (c.maxHeight - fixed) / rows;
                var cols = tiles.length;
                if (_preview && enemyCards.length > cols) {
                  cols = enemyCards.length;
                }
                final card = _cardSize(
                  availW: c.maxWidth - presetsW,
                  rowH: rowH,
                  cols: cols.clamp(1, kMaxPerSide),
                );
                return Column(
                  children: [
                    if (_preview) ...[
                      SizedBox(
                        height: rowH,
                        child: Padding(
                          padding: EdgeInsets.only(left: presetsW),
                          // 12 px up, away from the VS bar (user 2026-11-16).
                          child: Transform.translate(
                            offset: const Offset(0, -12),
                            child: _row(enemyCards, card),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: _barH,
                        child: Center(
                          child: PowerVersusBar(
                            mine: myPower,
                            theirs: _enemyPower,
                            theirsLabel: 'Opponent',
                            mineLabel: 'Your team',
                            height: _barH,
                          ),
                        ),
                      ),
                    ],
                    if (!_preview)
                      _caption('Your team', sub: '$kPowerIcon $myPower'),
                    SizedBox(
                      height: rowH,
                      child: ready.isEmpty
                          ? Center(
                              child: versusHint(
                                'No battle-ready monster — heal your team first.',
                              ),
                            )
                          : Row(
                              children: [
                                if (presets != null) presets,
                                // 12 px down, away from the VS bar.
                                Expanded(
                                  child: Transform.translate(
                                    offset: Offset(0, _preview ? 12 : 0),
                                    child: _row(tiles, card),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: 40, child: _actions()),
        ],
      ),
    );
  }

  /// Saved teams stacked at the right edge of the team half.
  Widget? _presetsColumn(List<CreatureInstance> ready) {
    final teams = _ctrl.battleTeams;
    if (teams.isEmpty) return null;
    return SizedBox(
      width: 84,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final t in teams)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _presetChip(t, ready),
              ),
          ],
        ),
      ),
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

  Widget _actions({Widget? middle}) {
    final canFight = _selected.isNotEmpty;
    return Row(
      children: [
        if (middle != null)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: middle,
            ),
          )
        else
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

  // ── Saved teams ───────────────────────────────────────────────────────

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
          decoration: active ? goldButton() : menuButton(),
          child: Text(
            team.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
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
        seat: slotIndex,
        current: slotIndex != null && slotIndex < _selected.length
            ? ready.where((c) => c.id == _selected[slotIndex]).firstOrNull
            : null,
        isTutorial: _isFirstBattleTutorial,
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

  /// The seat being filled (null = the next free one) and who stands in it.
  final int? seat;
  final CreatureInstance? current;

  /// The tutorial's first fight (user 2026-09-30: "Who Fights: ein kurzer
  /// Text, dass ich das Monster anwählen soll und dieses Highlighten (sonst
  /// nichts anwählbar)") — this screen had no tutorial awareness at all
  /// before, unlike every other step of the guided intro. Spotlights the
  /// one ready monster and dead-zones the rest (search/sort/filter).
  final bool isTutorial;

  const _TeamPickerScreen({
    required this.ready,
    required this.isPicked,
    required this.onPick,
    required this.chosen,
    required this.partySize,
    this.seat,
    this.current,
    this.isTutorial = false,
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

  /// Tapping a tile only PREVIEWS it here (user 2026-10-05, "Konzept 4") —
  /// the detail panel's own button is what actually picks it. Null = nothing
  /// tapped yet.
  CreatureInstance? _preview;

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
  Widget build(BuildContext context) => Stack(
    children: [
      MenuScaffold(
        title: 'Who fights?',
        trailing: Text(
          '${widget.chosen()} of ${widget.partySize} chosen',
          style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
        ),
        // No card of its own any more (user 2026-09-30, "hier und
        // andernorts sind noch die alten Kästchen vorhanden") —
        // MenuScaffold is already the one card on screen.
        child: _body(),
      ),
      // Sibling of MenuScaffold, not nested in its `child` (same fix as
      // _BattlePrepScreenState's own build, earlier in this file, user
      // 2026-10-01: "hier auch" — nested, the dim only reached MenuScaffold's
      // content slot, leaving the "Who fights? / 0 of 1 chosen" header and
      // its hairline undimmed).
      if (widget.isTutorial)
        const IntroSpotlightOverlay(
          anchorName: 'teampicker-tile',
          hint: 'Tap your monster to add it to the team.',
        ),
    ],
  );

  Widget _body() =>
      Padding(padding: const EdgeInsets.fromLTRB(0, 10, 0, 0), child: _stage());

  /// The card stage (user 2026-11-11): the seat on the left, the previewed
  /// monster on the right, what the swap does between them, every candidate as
  /// a card along the bottom. [PickerStage] is the shared frame; the plate's
  /// button is still the only thing that commits a pick.
  Widget _stage() {
    final c = _preview;
    final now = widget.current;
    final picked = c != null && widget.isPicked(c);
    return PickerStage(
      banner: pickerBanner(
        'BATTLE TEAM',
        widget.seat == null
            ? 'Pick the next fighter'
            : 'Pick who takes seat ${widget.seat! + 1}',
      ),
      currentLabel: widget.seat == null
          ? 'NEXT SEAT'
          : 'SEAT ${widget.seat! + 1}',
      current: now == null ? null : CreatureCard(creature: now),
      preview: c == null ? null : CreatureCard(creature: c),
      plateTitle: c?.displayName,
      rows: c == null
          ? null
          : [
              pickerCompareRow(
                'Power',
                from: now == null ? null : combatPower(now),
                to: combatPower(c),
              ),
              pickerCompareRow('HP', from: now?.maxHp, to: c.maxHp),
              pickerCompareRow('Level', from: now?.level, to: c.level),
              pickerPlateRow('Type', c.species?.element.label ?? '—'),
            ],
      action: c == null
          ? null
          : pickerChooseButton(
              label: picked ? 'Remove' : (now == null ? 'Place' : 'Swap'),
              onTap: () {
                final close = widget.onPick(c);
                setState(() {});
                if (close) Navigator.pop(context);
              },
            ),
      controls: Row(
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
      tiles: [for (final c in _filtered) _tile(c)],
    );
  }

  Widget _tile(CreatureInstance c) {
    final picked = widget.isPicked(c);
    final previewed = _preview?.id == c.id;
    // The tutorial's one ready monster still picks on a single tap (user
    // 2026-09-30: the scripted first fight spotlights it and expects that tap
    // to close the picker) — everywhere else, a tap only previews.
    final card = Stack(
      children: [
        Opacity(
          opacity: picked ? 0.45 : 1,
          child: pickerPreviewFrame(
            active: previewed,
            child: CreatureCard(
              creature: c,
              onTap: () {
                if (widget.isTutorial) {
                  final close = widget.onPick(c);
                  setState(() {});
                  if (close) Navigator.pop(context);
                  return;
                }
                setState(() => _preview = c);
              },
            ),
          ),
        ),
        if (picked)
          const Positioned(
            top: 2,
            left: 2,
            child: PixelIcon(
              Icons.check_circle,
              size: 18,
              color: CreamPalette.better,
            ),
          ),
      ],
    );
    // The tutorial's one ready monster (see [IntroSpotlightOverlay] above) —
    // untagged once picked, since picking it closes the picker anyway.
    if (widget.isTutorial && !picked) {
      return KeyedSubtree(
        key: IntroSpotlightAnchors.of('teampicker-tile'),
        child: card,
      );
    }
    return card;
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
    trailing: PixelIcon(
      _descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: CreamPalette.goldInk,
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
