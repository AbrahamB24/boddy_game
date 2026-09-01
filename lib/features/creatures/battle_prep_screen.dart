import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/parchment_page.dart';
import '../onboarding/intro_flow.dart';
import '../onboarding/intro_spotlight.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/building_icon.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/combatant.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/saved_team.dart';
import 'widgets/creature_backdrop.dart';
import 'widgets/creature_card.dart';
import 'widgets/creature_sprite.dart';
import 'services/battle_rewards.dart';
import 'services/creatures_controller.dart';
import '../common/widgets/recess_bar.dart';

// ── Pre-battle briefing (user 2026-07-24) ───────────────────
// Before a fight starts you see WHO you're fighting, WHAT clearing it unlocks,
// and you PICK the monster(s) you take in (up to the battle's party allowance).
// Pops the chosen team (in selection order) — or null if you back out.
class BattlePrepScreen extends StatefulWidget {
  final String title;
  final List<Combatant> enemies;
  final int partySize;
  final List<RewardLine> rewards;
  final bool isBoss;

  const BattlePrepScreen({
    super.key,
    required this.title,
    required this.enemies,
    required this.partySize,
    required this.rewards,
    this.isBoss = false,
  });

  @override
  State<BattlePrepScreen> createState() => _BattlePrepScreenState();
}

class _BattlePrepScreenState extends State<BattlePrepScreen> {
  final _ctrl = CreaturesController();

  /// Selected creature ids, kept in the order they were picked (first = the
  /// monster that leads the fight).
  final List<String> _selected = [];

  // Tutorial's first fight: nothing to pick (there's only the one starter),
  // so the whole screen is just "here's your team, hit Fight" — one
  // spotlight rather than the battle screen's own 4-part sequence.
  bool _showFightSpotlight = false;

  // Rewards past [_kCollapsedRewardCount] start folded (user 2026-08-28) —
  // the top half of the screen is now a fixed height, not a scrolling list,
  // so a boss's long reward line needs its OWN way to show the rest.
  bool _rewardsExpanded = false;

  @override
  void initState() {
    super.initState();
    // Pre-select the default roster so a player can just hit Fight — the saved
    // active team if there is one (battleTeam honours it), else the first N
    // ready. Still fully re-pickable.
    final defaults = _ctrl.battleTeam(size: widget.partySize);
    final seed = defaults.isNotEmpty
        ? defaults
        : _ctrl.battleReadyCreatures.take(widget.partySize).toList();
    _selected.addAll(seed.map((c) => c.id));
    _showFightSpotlight =
        SettlementController().introStep == IntroStep.firstNode;
  }

  void _toggle(CreatureInstance c) {
    setState(() {
      if (_selected.remove(c.id)) return;
      // At the cap: drop the earliest pick so tapping a new one always works.
      if (_selected.length >= widget.partySize && _selected.isNotEmpty) {
        _selected.removeAt(0);
      }
      _selected.add(c.id);
    });
  }

  List<CreatureInstance> get _team =>
      _selected.map(_ctrl.byId).whereType<CreatureInstance>().toList();

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.battleReadyCreatures;
    return ParchmentPage(
      title: widget.title,
      child: Stack(
        children: [
          _body(ready),
          if (_showFightSpotlight)
            IntroSpotlightOverlay(
              anchorName: 'battleprep-fight',
              hint: 'Your team is already picked — hit Fight when ready.',
              onScrimTap: () => setState(() => _showFightSpotlight = false),
            ),
        ],
      ),
    );
  }

  // Fixed split, not one long scroll (user 2026-08-28: "wie Punkt 1" —
  // picking the "no more scrolling" option). The team grid never holds more
  // than 3-per-row / 2 rows (6 monsters, CombatEngine.kFieldSlots's own
  // reserve cap), so it only ever needs its own CONTENT height, not a share
  // of the screen — everything that height doesn't use goes to the top
  // half via Expanded, which is the "more room up top" this unlocks.
  //
  // The one thing that can still overflow a fixed top half is a LONG reward
  // list (a boss can list several). Rather than let the whole screen scroll
  // again for that one case, [_rewardList] itself collapses past
  // [_kCollapsedRewardCount] and offers its own expand arrow (user
  // 2026-08-28: "bitte unten bei der Rewardbox einen Pfeil machen, damit
  // die Box ausgeklappt werden kann").
  /// The one gap this whole screen uses between a title and what follows it,
  /// and between adjacent blocks within a section (user 2026-08-29: "Abstand
  /// ist nicht immer gleich, bitte alles auf gleichen Abstand setzen") —
  /// replaces a mix of 4/8/10/20 that had grown up one request at a time.
  static const double _kGap = 12;

  Widget _body(List<CreatureInstance> ready) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              ParchmentPage.kParchmentPagePad,
              12,
              ParchmentPage.kParchmentPagePad,
              8,
            ),
            child: Column(
              children: [
                _faceTitle('You face'),
                const SizedBox(height: _kGap),
                _enemyRow(),
                if (widget.rewards.isNotEmpty) ...[
                  const SizedBox(height: _kGap),
                  _rewardList(),
                ],
              ],
            ),
          ),
        ),
        // Nudged up a bit (user 2026-08-29: "Your Team inkl. Monster etwas
        // nach oben schieben") — the section above is Expanded and often
        // doesn't fill its own share (a short "you face" + rewards list),
        // which otherwise pushes "Your team" all the way down to sit right
        // above the fight bar with a lot of dead air over it. Transform
        // rather than a layout change: it leaves that air between this
        // block and the fight bar instead, which reads better than a gap
        // ABOVE "Your team" did.
        Transform.translate(
          offset: const Offset(0, -20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              ParchmentPage.kParchmentPagePad,
              _kGap,
              ParchmentPage.kParchmentPagePad,
              0,
            ),
            child: Column(
              children: [
                // Just "Your team" now (user 2026-08-28: "nur Your Team")
                // — the count moved off both this heading and the Fight
                // button; the slots below are the count now.
                _faceTitle('Your team'),
                const SizedBox(height: _kGap),
                // Only when there is nothing to pick from at all — every
                // other hint under this heading is gone (user 2026-08-28:
                // "Text unter your team löschen"), but an EMPTY roster
                // still needs to say why the slots below can't be filled.
                if (ready.isEmpty) ...[
                  Text(
                    'No battle-ready monster — heal your team first.',
                    style: FoE.dim(size: 12),
                  ),
                  const SizedBox(height: _kGap),
                ],
                // PRESET TEAMS (user 2026-08-28: "muss ich die
                // voreingestellten Teams auswählen können"). Fills the
                // slots above from a saved roster in one tap — LOCAL to
                // this fight only: it edits [_selected], never
                // [_ctrl.activateTeam], so picking a preset here does not
                // touch which team is active everywhere else.
                if (_ctrl.battleTeams.isNotEmpty) ...[
                  _presetTeamsRow(ready),
                  const SizedBox(height: _kGap),
                ],
                _slotsGrid(ready),
              ],
            ),
          ),
        ),
        KeyedSubtree(
          key: IntroSpotlightAnchors.of('battleprep-fight'),
          child: _fightBar(),
        ),
      ],
    );
  }

  /// "You face" — bigger and centred (user 2026-08-28), the screen's own
  /// headline rather than one more section label. No sword glyph in front of
  /// it anymore, same request. "Your team" wears the exact same look since
  /// (user 2026-08-28, same day: "Your Team so gross und zentriert wie you
  /// face schreiben") — this screen has two headlines, not one plus a label.
  Widget _faceTitle(String text) => Center(
    child: Text(text, style: FoE.title(size: 20).copyWith(color: FoE.gold)),
  );

  // ── Enemies ────────────────────────────────────────────────
  /// ── THE ENEMY LOOKS LIKE A MONSTER (user 2026-08-04) ──
  /// It was a 96-px bordered box with a small sprite, a name and a level, laid
  /// out beside a grid of full monster tiles. Two ways of drawing the same kind
  /// of thing on one screen, and the comparison you are about to make — my six
  /// against their three — was the one thing the layout made hard.
  ///
  /// So the enemies use the monster tile's geometry: the same grid, the same
  /// aspect, the same element backdrop under the art, the same deepened strip
  /// carrying the name, the same rounded shape and the same pop-out band above
  /// the tile for the sprite to break into.
  ///
  /// It is a MATCHED tile, not literally [CreatureCard]: that widget is built
  /// on a CreatureInstance with a species, XP and HP behind it, and an enemy
  /// has none of those. Faking an instance to reuse the widget would put a lie
  /// in the model to save a hundred lines in the view. What is shared instead
  /// is the vocabulary — [CreatureBackdrop], [FoE.facet], the strip tones —
  /// so the two cannot drift apart on the things a player actually sees.
  // A GridView filled fewer than 3 columns pins its tiles to the LEFT (user
  // 2026-08-28: "Gegnermonster sollen auch zentriert sein" — the same fix
  // already applied to the team's own [_slotsGrid]). A [Wrap] with its own
  // fixed-size tiles centres each row instead.
  Widget _enemyRow() {
    if (widget.enemies.isEmpty) return const SizedBox.shrink();
    // 0.60, not 0.70 (user 2026-08-28: "diese Boxen etwas länger machen,
    // besonders der obere Teil mit dem Monster") — matches every other
    // monster-tile grid in the app.
    const cols = 3, spacing = 12.0, aspect = 0.60;
    final n = widget.enemies.length;
    return LayoutBuilder(
      builder: (context, box) {
        final tileW = (box.maxWidth - spacing * (cols - 1)) / cols;
        // Past 3, one overlapping row instead of a second grid row (user
        // 2026-08-29: "Sobald es mehr als 3 Gegner hat, sollen sich die
        // Boxen etwas überlappen wie ein Kartenfächer"). Same tile size
        // either way — what changes is how close together they stand.
        if (n <= 3) {
          return Wrap(
            alignment: WrapAlignment.center,
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final e in widget.enemies)
                SizedBox(
                  width: tileW,
                  height: tileW / aspect,
                  child: _enemyCard(e),
                ),
            ],
          );
        }
        final tileH = tileW / aspect;
        // How far each card sits from the last — enough overlap that ALL of
        // them fit the row's own width, however many there are, clamped so
        // a couple extra enemies don't paper-thin the fan and a great many
        // don't leave them fully hidden under each other.
        final step = ((box.maxWidth - tileW) / (n - 1)).clamp(
          tileW * 0.25,
          tileW * 0.8,
        );
        final totalW = tileW + step * (n - 1);
        final startX = ((box.maxWidth - totalW) / 2).clamp(
          0.0,
          double.infinity,
        );
        return SizedBox(
          height: tileH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Painted RIGHT-to-LEFT so the LEFTMOST card ends up on top
              // (user 2026-08-29: "Das Monster ganz links soll im
              // Vordergrund sein") — position still comes from the
              // creature's own index, only the paint (list) order is
              // reversed.
              for (var i = n - 1; i >= 0; i--)
                Positioned(
                  left: startX + step * i,
                  width: tileW,
                  height: tileH,
                  child: _enemyCard(widget.enemies[i]),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Sum of every stat, mirroring services/creature_power.dart's
  /// [totalPower] — that function reads a [CreatureInstance], which an enemy
  /// (a bare [Combatant]) doesn't have.
  int _enemyPower(Combatant e) =>
      CreatureStat.values.fold(0, (sum, s) => sum + e.stat(s));

  static const List<Shadow> _enemyStripShadow = [
    Shadow(color: Color(0x66000000), blurRadius: 0, offset: Offset(0, 1)),
  ];

  /// Exactly [CreatureCard]'s layout (user 2026-08-28: level beside the name
  /// at the same height as my own monsters, plus the rarity, power, HP bar
  /// and gender every one of THOSE tiles already carries) — an enemy just
  /// has no XP arc or evolve arrow, having no XP or evolutions of its own.
  Widget _enemyCard(Combatant e) {
    final element = e.element.color;
    final stripDark = Color.lerp(element, Colors.black, 0.46)!;
    final stripLight = Color.lerp(element, Colors.black, 0.30)!;
    final hpFraction = e.maxHp <= 0 ? 0.0 : (e.hp / e.maxHp).clamp(0.0, 1.0);
    final hpColor = hpFraction <= 0
        ? FoE.danger
        : hpFraction < 0.3
        ? FoE.danger
        : hpFraction < 0.6
        ? FoE.gold
        : FoE.positive;
    return LayoutBuilder(
      builder: (context, c) {
        // The same three numbers the monster tile uses, for the same reasons:
        // a strip tall enough for two lines, and a band above the tile the art
        // is allowed to break into so the sprite reads as standing in front of
        // its card rather than boxed inside it.
        const stripH = 54.0;
        final topReserve = c.maxHeight * 0.17;
        return Stack(
          children: [
            Positioned(
              top: topReserve,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: stripDark,
                  shape: FoE.facet(
                    radius: 22,
                    // A boss is the one enemy worth a frame. Everything else
                    // says what it is by its element alone, exactly as my own
                    // monsters do.
                    side: e.isBoss
                        ? const BorderSide(color: FoE.goldBright, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: CreatureBackdrop(
                        element: e.element,
                        radius: 0,
                        child: const SizedBox.expand(),
                      ),
                    ),
                    SizedBox(
                      height: stripH,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [stripLight, stripDark],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(9, 5, 9, 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  Expanded(
                                    child: Text(
                                      e.isBoss ? '👑 ${e.name}' : e.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: FoE.label(size: 13).copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        shadows: _enemyStripShadow,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    'Lv ${e.level}',
                                    style: FoE.value(size: 10).copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.82,
                                      ),
                                      shadows: _enemyStripShadow,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: RecessBar(
                                      value: hpFraction,
                                      color: hpColor,
                                      height: 6,
                                      onDark: true,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    e.gender.symbol,
                                    style: TextStyle(
                                      color: Color.lerp(
                                        e.gender.color,
                                        Colors.white,
                                        0.2,
                                      ),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      height: 1.0,
                                      shadows: _enemyStripShadow,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Power (top-right), rarity underneath — same placement as
            // [CreatureCard], drawn before the art so the monster overlaps it.
            Positioned(
              top: topReserve + 6,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '⚡${_enemyPower(e)}',
                    style: FoE.value(
                      size: 11,
                    ).copyWith(color: Colors.white, shadows: _enemyStripShadow),
                  ),
                  Text(
                    e.rarity.label,
                    style: FoE.dim(size: 9).copyWith(
                      color: Color.lerp(e.rarity.color, Colors.white, 0.35),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      shadows: _enemyStripShadow,
                    ),
                  ),
                ],
              ),
            ),
            // The sprite, breaking up out of the tile. Zoomed to match
            // [CreatureCard]'s own art (user 2026-08-28: "das Monsterasset
            // ebenfalls vergrössern", then "um 20% grösser... zu hoch") —
            // same reasoning and same fix as there: 20%, centred rather
            // than bottom-anchored, so the growth doesn't put its whole 20%
            // into the head.
            Positioned(
              left: 4,
              right: 4,
              top: 0,
              // A bit lower now (user 2026-08-29: "Dort sollen nur die
              // Assets von den gegnerischen Monster etwas tiefer unten
              // sein") — was stripH + 4, closer to the strip shifts the
              // whole (centred) art box down with it.
              bottom: stripH - 4,
              child: Transform.scale(
                scale: 1.20,
                alignment: Alignment.center,
                child: e.imageUrl == null
                    ? const Icon(Icons.pets, color: FoE.gold, size: 34)
                    : CreatureSprite(
                        url: e.imageUrl!,
                        fallback: const Icon(
                          Icons.pets,
                          color: FoE.gold,
                          size: 34,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Rewards ────────────────────────────────────────────────
  /// Shown collapsed before an expand tap adds the rest — see [_body]'s own
  /// doc for why the box needs this now that the top half is a fixed height
  /// rather than a scrolling list.
  static const int _kCollapsedRewardCount = 2;

  Widget _rewardList() {
    final all = widget.rewards;
    final hasMore = all.length > _kCollapsedRewardCount;
    final shown = (_rewardsExpanded || !hasMore)
        ? all
        : all.take(_kCollapsedRewardCount).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: FoE.panel(radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inside the box now (user 2026-08-28: "Text 'Rewards' innerhalb
          // der Reward box") — was a separate label sitting above it.
          Padding(
            // Tighter now (user 2026-08-29: "Die Rewards näher
            // aneinanderrücken (weniger Zeilenabstand)").
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Text(
              'Rewards',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
          ),
          for (final r in shown)
            Padding(
              // Tighter now (user 2026-08-29: "Die Rewards näher
              // aneinanderrücken (weniger Zeilenabstand)").
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: r.buildingId != null
                  ? _buildingRewardRow(r)
                  : _plainRewardRow(r),
            ),
          if (hasMore)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _rewardsExpanded = !_rewardsExpanded),
              child: Padding(
                // Tighter now (user 2026-08-29: "Die Rewards näher
                // aneinanderrücken (weniger Zeilenabstand)").
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _rewardsExpanded
                          ? 'Show less'
                          : 'Show ${all.length - _kCollapsedRewardCount} more',
                      style: FoE.dim(size: 11).copyWith(color: FoE.gold),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _rewardsExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: FoE.gold,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A "new building" reward, as the building's OWN preview picture and its
  /// name (user 2026-08-28) — not the 🏛️ glyph and "New building: X" every
  /// other reward line uses.
  Widget _buildingRewardRow(RewardLine r) => _rewardRow(
    // The bundled renders carry real camera headroom above the roofline
    // (BLENDER_camera framing needs it for a tall building), so at BOTH
    // BuildingIcon's fixed size and BoxFit.contain the actual building
    // sits in roughly the bottom 60% of its own square box — noticeably
    // LOWER than the text beside it (user 2026-08-28: "Gebäude icon
    // zentrieren zum Text"). Nudged up to compensate; a LOCAL fix, since
    // BuildingIcon itself has no alignment knob and every other caller
    // was already tuned around this same headroom.
    Transform.translate(
      offset: const Offset(0, -6),
      child: BuildingIcon(defId: r.buildingId, emoji: r.emoji, size: 36),
    ),
    r.text.replaceFirst('New building: ', ''),
  );

  /// Every other reward: its emoji, plain.
  Widget _plainRewardRow(RewardLine r) =>
      _rewardRow(Text(r.emoji, style: const TextStyle(fontSize: 16)), r.text);

  /// How wide every reward line's icon SLOT is, whatever actually fills it —
  /// an emoji glyph or a 36-px [BuildingIcon] (user 2026-08-28: "den Text
  /// immer gleich bündig machen. D.h in der gleichen Spalte"). The icon
  /// itself is centred in the slot; the text starts at the same x either
  /// way.
  static const double _kRewardIconSlot = 36;

  Widget _rewardRow(Widget icon, String text) => Row(
    children: [
      // HEIGHT too, not just width (user 2026-08-29: "Abstand ist nicht
      // immer gleich, bitte alles auf gleichen Abstand setzen") — a
      // building's 36-px [BuildingIcon] made ITS row taller than a plain
      // emoji's ~16-px glyph did, even though both rows carried the same
      // padding; the ROW's own height was never pinned to match.
      SizedBox(
        width: _kRewardIconSlot,
        height: _kRewardIconSlot,
        child: Center(child: icon),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: FoE.label(size: 13).copyWith(color: FoE.parchment),
        ),
      ),
    ],
  );

  // ── Preset teams ───────────────────────────────────────────
  /// A row of the player's saved battle rosters (from the Teams screen).
  /// Tapping one loads its members into the slots above, in one tap instead
  /// of one monster at a time.
  Widget _presetTeamsRow(List<CreatureInstance> ready) {
    final teams = _ctrl.battleTeams;
    return SizedBox(
      height: 30,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: teams.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _presetChip(teams[i], ready),
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
    // Only members who can actually fight NOW — a preset built with six
    // monsters is still worth one tap when four of them are healed.
    final usable = [
      for (final id in team.memberIds)
        if (readyIds.contains(id)) id,
    ].take(widget.partySize).toList();
    final active = usable.isNotEmpty && _sameSelection(_selected, usable);
    return GestureDetector(
      onTap: usable.isEmpty
          ? null
          : () => setState(() {
              _selected
                ..clear()
                ..addAll(usable);
            }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: active
              ? FoE.goldBright.withValues(alpha: 0.18)
              : kInk.withValues(alpha: 0.10),
          shape: FoE.facet(
            radius: 14,
            side: BorderSide(
              color: active ? FoE.goldBright : kInk.withValues(alpha: 0.22),
            ),
          ),
        ),
        child: Text(
          team.name,
          style: FoE.label(size: 12).copyWith(
            color: usable.isEmpty
                ? kInkFaint
                : (active ? FoE.goldBright : FoE.textDim),
          ),
        ),
      ),
    );
  }

  // ── Team slots ─────────────────────────────────────────────
  // Was one grid of every battle-ready monster, dim ones tap-to-add. Replaced
  // (user 2026-08-28, pointing at the expedition picker's "+ Add" tile) with
  // that same slot-row pattern: [widget.partySize] places, filled ones are
  // THE monster tile (user 2026-07-27: "übernimm bitte überall genau diese
  // Kachel"), empty ones are the expedition's own "+ Add" tile, and a tap on
  // Add opens the roster in a sheet instead of picking inline.
  // A GridView filled fewer than [widget.partySize] of 3 columns pins its
  // tiles to the LEFT (user 2026-08-28: "Monsterkacheln bitte zentrieren") —
  // one slot in a 3-wide grid sat in the corner with two empty columns beside
  // it. [monsterTileGrid]'s own centred alignment fixes that, at the ONE tile
  // size every such grid in the game now shares (user 2026-08-31: "sollen
  // immer genau gleich hoch sein, überall in der gesamten App").
  Widget _slotsGrid(List<CreatureInstance> ready) {
    if (ready.isEmpty) return const SizedBox.shrink();
    final team = _team;
    return monsterTileGrid([
      for (var i = 0; i < widget.partySize; i++)
        i < team.length
            ? _filledSlot(team[i], ready, i)
            : _emptySlot(ready, isNext: i == team.length),
    ], alignment: WrapAlignment.center);
  }

  /// A tap on the tile itself opens the roster to SWAP this monster for
  /// another (user 2026-08-28: "will ich in den Auswahlscreen kommen, um es
  /// auszutauschen") — the small ✕ badge, now an actual button rather than
  /// [IgnorePointer] decoration, is the only way left to empty the slot
  /// outright.
  // No more ✕ badge (user 2026-08-28: "'x' beim eigenen Monster löschen") —
  // a tap on the tile itself already opens the swap picker; that picker's
  // own close/back gesture is now the only way off this screen without
  // picking a replacement.
  Widget _filledSlot(CreatureInstance c, List<CreatureInstance> ready, int i) =>
      CreatureCard(
        creature: c,
        onTap: () => _openPicker(ready, slotIndex: i),
      );

  /// A place waiting to be filled. Only the next one to fill says "Add" —
  /// six copies of the word is noise, one is a caption for the whole rank.
  Widget _emptySlot(List<CreatureInstance> ready, {required bool isNext}) =>
      EmptyMonsterSlot(
        label: isNext ? 'Add' : null,
        onTap: () => _openPicker(ready),
      );

  /// The roster, as a sheet over this one — opened only while a slot is
  /// being filled, which is what keeps it off the page the rest of the time.
  ///
  /// [slotIndex] is set when the tap that opened this was on a FILLED slot
  /// (a swap): the pick that follows replaces that one slot instead of
  /// filling the next empty one.
  Future<void> _openPicker(
    List<CreatureInstance> ready, {
    int? slotIndex,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParchmentSheet(
        title: 'Who fights?',
        initialSize: 0.7,
        builder: (sheetCtx, scrollCtrl) => StatefulBuilder(
          // Its own builder so a pick repaints the picker; the slots behind
          // it catch up when it closes.
          //
          // A [Wrap] through [monsterTileGrid] now, not a `GridView` sizing
          // its own columns off this sheet's local width — that auto-sized
          // width had drifted from the Monsters screen's (this sheet pads
          // 26px, the Monsters screen 24px), and a `GridView` has no way to
          // force an exact width the way it can force an exact height. The
          // roster is a player's own creatures, never remotely large enough
          // to need lazy building (user 2026-08-31: "genau gleich gross sein
          // wie die Kacheln beim Monstersscreen").
          //
          // The 26px itself is now actually 24 too (2026-08-31 audit,
          // ParchmentPage.kParchmentPagePad) — the comment above already
          // flagged the mismatch, but only the tile-width math got fixed
          // at the time; the padding constant here never did.
          builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.fromLTRB(
              ParchmentPage.kParchmentPagePad,
              4,
              ParchmentPage.kParchmentPagePad,
              20,
            ),
            child: monsterTileGrid([
              for (final c in ready)
                _pickerTile(c, sheetCtx, setSheetState, slotIndex),
            ]),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _pickerTile(
    CreatureInstance c,
    BuildContext sheetCtx,
    void Function(VoidCallback) setSheetState,
    int? slotIndex,
  ) {
    final picked = _selected.contains(c.id);
    return Stack(
      children: [
        Opacity(
          opacity: picked ? 0.45 : 1,
          child: CreatureCard(
            creature: c,
            onTap: () {
              setState(() {
                if (slotIndex != null) {
                  final already =
                      slotIndex < _selected.length &&
                      _selected[slotIndex] == c.id;
                  if (!already) {
                    // A SWAP: this id takes over slotIndex, dropped from
                    // wherever else it stood so no two slots share a
                    // monster. Guarded above — removing it unconditionally
                    // would, for a monster already sitting AT slotIndex,
                    // shift a later slot's occupant down into slotIndex and
                    // then overwrite it, silently dropping that teammate.
                    _selected.remove(c.id);
                    if (slotIndex < _selected.length) {
                      _selected[slotIndex] = c.id;
                    } else {
                      _selected.add(c.id);
                    }
                  }
                } else {
                  _toggle(c);
                }
              });
              setSheetState(() {});
              // Either a swap (always exactly one decision) or a now-full
              // team answers the question; holding the picker open would
              // leave a list that refuses every further tap.
              if (slotIndex != null || _selected.length >= widget.partySize) {
                Navigator.pop(sheetCtx);
              }
            },
          ),
        ),
        if (picked)
          const Positioned(
            top: 2,
            left: 2,
            child: Icon(Icons.check_circle, size: 18, color: kAccent),
          ),
      ],
    );
  }

  // ── Fight bar ──────────────────────────────────────────────
  Widget _fightBar() {
    final canFight = _selected.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        ParchmentPage.kParchmentPagePad,
        10,
        ParchmentPage.kParchmentPagePad,
        14,
      ),
      decoration: BoxDecoration(
        color: FoE.panelDark,
        border: Border(top: BorderSide(color: FoE.border)),
      ),
      child: GestureDetector(
        onTap: canFight ? () => Navigator.of(context).pop(_team) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          alignment: Alignment.center,
          decoration: FoE.btn(active: canFight),
          child: Text(
            // No sword glyph and no count any more (user 2026-08-28: "Lösche
            // das Schwert Icon und (1/1)").
            canFight ? 'Fight' : 'Pick at least one monster',
            style: FoE.label(
              size: 15,
            ).copyWith(color: canFight ? Colors.white : FoE.textDim),
          ),
        ),
      ),
    );
  }
}
