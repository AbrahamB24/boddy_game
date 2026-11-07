import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart' show goldButton, sectionLabel, zoneBox;
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../settlement/resources_screen.dart' show romanNumeral;
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/area.dart';
import 'models/expedition.dart' show ExpeditionType;
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/capture_math.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import '../settlement/data/gather_defs.dart';
import 'services/expedition_targets.dart';
import 'services/gather_math.dart';
import 'widgets/creature_card.dart';
import 'widgets/picker_detail_panel.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

/// Picks the group for [target] and sends the trip — embedded directly on
/// the Expeditions hub's own composer (user 2026-10-02, "Konzept 24": the
/// hub picks the target, this panel is just the part of it that was always
/// the same regardless of target). It used to also live under a
/// [showModalBottomSheet] wrapper reached from a separate tile grid; that
/// grid and its sheet are both gone now that the composer feeds this panel
/// a target directly, so there is nothing left to disambiguate by covering
/// the page — this is always inline.
class ExpeditionLaunchPanel extends StatefulWidget {
  final ExpeditionTarget target;

  /// Hunt only: which duration variant this sheet opens on (user 2026-09-29)
  /// — the Expeditions hub's own composer IS the picker now, so a tap there
  /// means the choice is made, not merely offered; there is no picker left
  /// inside the sheet to override it with. Clamped to a valid index.
  final int? initialOptionIndex;

  /// The hub's own "1 Target" step (user 2026-11-04, layout 2 "Drei Schritte"
  /// of ten expedition proposals). When given, the panel lays itself out as
  /// three steps side by side — this widget, then "2 Group", then "3 Start" —
  /// instead of the old single column. Null keeps the single column, which is
  /// what a panel mounted on its own (no hub around it) still gets.
  final Widget? stepOne;

  const ExpeditionLaunchPanel({
    super.key,
    required this.target,
    this.initialOptionIndex,
    this.stepOne,
  });

  @override
  State<ExpeditionLaunchPanel> createState() => _ExpeditionLaunchPanelState();
}

class _ExpeditionLaunchPanelState extends State<ExpeditionLaunchPanel> {
  final _creatures = CreaturesController();
  final _expeditions = ExpeditionController();
  final _settlement = SettlementController();

  final Set<String> _selected = {};
  bool _sending = false;

  /// Set while the roster is open FOR A SWAP — which member tapping a
  /// candidate replaces (user 2026-08-31: "da ich mit anklicken das Monster
  /// austauschen kann" — a filled place now opens the roster instead of
  /// removing itself). Null means the roster was opened from an empty
  /// place instead, and a pick just fills the next open one, same as
  /// before.
  String? _swapTargetId;

  /// Hunt only: which variant (index into kCaptureHuntOptions). Each has a
  /// fixed step target and find count — no longer a hunter count
  /// (2026-09-11), and no longer a duration (2026-10-02 — hunts run on real
  /// steps now).
  int _optionIndex = 0;

  /// The roster picker's own search box — a FIELD tied to this State's own
  /// lifecycle, not a local variable created and disposed per [_openPicker]
  /// call. Disposing it right after that call's `await` fired the sheet's
  /// CLOSING animation, not its removal from the tree: the sheet keeps
  /// rebuilding (and the SearchPill's TextField keeps reading the
  /// controller) for the rest of that animation, so an immediate dispose
  /// crashed it with "TextEditingController was used after being disposed".
  final _pickerSearch = TextEditingController();

  @override
  void initState() {
    super.initState();
    final i = widget.initialOptionIndex;
    if (i != null) {
      _optionIndex = i.clamp(0, kCaptureHuntOptions.length - 1);
    }
  }

  @override
  void dispose() {
    _pickerSearch.dispose();
    super.dispose();
  }

  AreaDef get _area => widget.target.area;
  bool get _isHunt => widget.target.isHunt;
  CaptureHuntOption get _option => kCaptureHuntOptions[_optionIndex];

  List<CreatureInstance> get _available => _creatures.availableForExpedition();
  List<CreatureInstance> get _members =>
      _available.where((c) => _selected.contains(c.id)).toList();

  /// Gather still uses the same growing party cap Battle does. Hunt instead
  /// scales with the chosen length ALONE (user 2026-09-11, confirmed after
  /// an earlier version of this also capped it at
  /// [CreaturesController.teamSizeCap]: "wenn ich 30' hunt auswähle, sollten
  /// unten 2 '+' Boxen sein" — that cap silently held every hunt at 1 slot
  /// until battle progress separately unlocked more, which is exactly the
  /// coupling hunt group size was supposed to have dropped) — one monster
  /// more per rung of [kCaptureHuntOptions], from 1 at 500 steps up to 5 at
  /// 10,000, full stop.
  int get _groupCap => _isHunt ? _optionIndex + 1 : _creatures.teamSizeCap;

  GatherPlan? get _plan => widget.target.spot == null
      ? null
      : _expeditions.preview(
          area: _area,
          spot: widget.target.spot!,
          members: _members,
        );

  /// What a hunt here can find. EVERY species, minus the legendaries still
  /// standing (user 2026-07-27) — the area decides the danger, the level and
  /// the travel, no longer the guest list.
  List<SpeciesDef> get _pool => catchableSpecies(_settlement.dungeonMaxStage);

  void _toggle(CreatureInstance c) {
    final selected = _selected.contains(c.id);
    if (!selected && _selected.length >= _groupCap) {
      // Silently swapping the oldest pick would hide which monster left the
      // group. Say what the limit is instead — same message hunt and gather
      // now share, since both are capped by the same growing party size.
      _say(
        'You may send $_groupCap monster${_groupCap > 1 ? 's' : ''} — '
        'win battles to widen the party.',
      );
      return;
    }
    setState(() => selected ? _selected.remove(c.id) : _selected.add(c.id));
  }

  // Messages are back (user 2026-11-02) — they were a no-op from 2026-08-29.
  void _say(String message) => context.snack(message, error: true);

  Future<void> _send() async {
    setState(() => _sending = true);
    final err = _isHunt
        ? await _expeditions.startCapture(
            area: _area,
            members: _members,
            option: _option,
          )
        : await _expeditions.startGather(
            area: _area,
            spot: widget.target.spot!,
            members: _members,
          );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      // No more energy-specific exception here (user 2026-09-14): starting a
      // trip can no longer fail for energy at all — low energy now scales
      // the trip's own duration instead of blocking it, see
      // ExpeditionController.startGather/startCapture.
      Feel.deny();
      _say(err);
      return;
    }
    Feel.success();
    // No modal to pop — the panel stays right where it is, ready for
    // another group if slots allow. ExpeditionController's own
    // notifyListeners() is what actually moves the new trip into "Out now";
    // this only clears this panel's own pick.
    setState(_selected.clear);
    if (context.mounted) context.snack('Off they go!');
  }

  // WHERE, under the title — the region and its danger decide the level of
  // what lives there and how likely a casualty is, so they belong with the
  // heading rather than buried in the body.
  //
  // Hunt doesn't get this row any more (user 2026-09-11) — every species is
  // catchable everywhere now (see catchableSpecies's own doc comment), so
  // the area name/danger no longer explains what you might find, only where
  // the trip physically happens, which the "Hunt" title next to it already
  // implies well enough. Gather keeps it: the region genuinely decides which
  // resource is here.
  Widget _whereRow() {
    if (_isHunt) return const SizedBox.shrink();
    return Padding(
      // kMonsterTilePageMargin (24), not ParchmentPage.kParchmentPagePad —
      // this comment used to claim those were the same value (2026-08-31
      // audit: "24, not 26... matching the Monsters screen"), but
      // kParchmentPagePad is actually 36 (2026-09-11 fix, alongside the
      // Group grid below finally getting the same margin): this row sat
      // 12px further right than the content under it the whole time.
      padding: const EdgeInsets.fromLTRB(
        kMonsterTilePageMargin,
        0,
        kMonsterTilePageMargin,
        6,
      ),
      child: Row(
        children: [
          Text(widget.target.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_area.emoji} Level ${romanNumeral(_area.order)}',
              style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  /// The hub's composer hands this an `Expanded` slot of its own (user
  /// 2026-10-02, "Konzept 24") — not an ambient scrolling list, so a hunt
  /// with a big enough roster still has somewhere to go rather than
  /// overflowing the column outright. The body scrolls within whatever
  /// height it's actually given; [_whereRow] and [_sendBar] stay fixed top
  /// and bottom around it.
  @override
  Widget build(BuildContext context) => widget.stepOne != null
      ? _threeSteps()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _whereRow(),
            Expanded(child: _body()),
            const SizedBox(height: 12),
            _sendBar(),
          ],
        );

  // ── Three steps (layout 2) ────────────────────────────────
  // The order is real — you pick WHERE, then WHO, then press go — which is why
  // the headings are numbered. Each step is its own zone so none of them can
  // push another off the screen; a text too long for its zone ellipsises
  // inside it.
  Widget _threeSteps() => Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(flex: 10, child: _step('1  Target', widget.stepOne!)),
      const SizedBox(width: 10),
      Expanded(
        flex: 11,
        child: _step(
          '2  Group',
          _groupStep(),
          trailing: Text(
            '${_members.length}/$_groupCap',
            style: FoE.dim(size: 11).copyWith(color: kInkFaint),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(flex: 9, child: _step('3  Start', _startStep())),
    ],
  );

  Widget _step(String title, Widget body, {Widget? trailing}) => zoneBox(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        sectionLabel(title, trailing: trailing),
        const SizedBox(height: 8),
        Expanded(child: body),
      ],
    ),
  );

  /// Step 2: the same scaled-to-fit group places as before, minus the heading
  /// the step already carries.
  Widget _groupStep() {
    if (_isHunt && _pool.isEmpty) return _body();
    final sections = _isHunt
        ? _groupSection(
            header: false,
            caption: (c) => '🪤 ${c.statValue(CreatureStat.catchRate)}',
          )
        : _groupSection(
            header: false,
            hint: 'Mining speed is the group\'s gather stat.',
            caption: (c) =>
                '⛏️ ${gatherPowerOf(c)}   🎒 ${c.statValue(CreatureStat.carry)}',
          );
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sections,
          ),
        ),
      ),
    );
  }

  /// Step 3: the trip's figures as label/value rows, the info button, and the
  /// Send button at the foot.
  Widget _startStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!_isHunt)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '${_area.emoji} Level ${romanNumeral(_area.order)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 11).copyWith(color: kInkFaint),
          ),
        ),
      for (final s in _statPairs()) _kv(s.$1, s.$2),
      Align(alignment: Alignment.centerRight, child: _infoButton()),
      const Spacer(),
      _sendBar(),
    ],
  );

  /// The body, as ONE column (2026-10-01 — "Konzept 8" of ten redesign
  /// proposals, picked over the old left-rail/right-content split). That
  /// split only ever existed to give the hunt's "Hunt length" grid somewhere
  /// to live; the hub's composer hands this an `initialOptionIndex` already
  /// chosen, so re-offering the same cards here would be the composer's own
  /// choice asked a second time. [_statStrip] carries the figures the rail
  /// used to; the roster gets the sheet's full width instead. A hunt with no
  /// species defined still gets the old full-width notice.
  ///
  /// SCALED TO FIT, NOT SCROLLED (user 2026-10-02: "es sollte alles auf einem
  /// Screen ohne scrollen sichtbar sein") — a [SingleChildScrollView] here
  /// used to let a 5-slot hunt's group [Wrap] spill onto a second row and
  /// just scroll past the fold, same problem the hub's old era-resource
  /// stack had before it adopted this exact [FittedBox] technique. Laying
  /// the column out at the slot's own WIDTH but UNBOUNDED height, then
  /// scaling the whole result down to fit, means a 1-slot hunt looks
  /// untouched (nothing to shrink) and only a long hunt's bigger group ever
  /// pays for it — uniformly, text and tiles together, rather than cropping
  /// anything off the bottom.
  Widget _body() {
    if (_isHunt && _pool.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No species are defined yet.\nAdd some in Dev Mode → Species.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 12),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: constraints.maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _isHunt ? _huntSections() : _gatherSections(),
          ),
        ),
      ),
    );
  }

  /// A row of equal-width figures — "Length · Finds · Duration", "Haul ·
  /// Carry cap · Duration" — replacing the old narrow info rail. [trailing]
  /// is the ⓘ that still opens the fuller, rarely-needed table behind it.
  Widget _statStrip(
    List<(String label, String value)> stats, {
    Widget? trailing,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      for (var i = 0; i < stats.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(child: _statChip(stats[i].$1, stats[i].$2)),
      ],
      if (trailing != null) ...[const SizedBox(width: 10), trailing],
    ],
  );

  Widget _statChip(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
    decoration: ShapeDecoration(
      color: kInk.withValues(alpha: 0.05),
      shape: FoE.facet(
        radius: 10,
        side: BorderSide(color: kInk.withValues(alpha: 0.16)),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: FoE.title(size: 14).copyWith(color: kInk),
        ),
        const SizedBox(height: 2),
        Text(
          label.toUpperCase(),
          style: FoE.dim(
            size: 9,
          ).copyWith(color: kInkFaint, letterSpacing: 0.6),
        ),
      ],
    ),
  );

  // ── Gather ────────────────────────────────────────────────
  /// Spot stock/regen moved behind the ⓘ (2026-10-01, Konzept 8) — they
  /// never change with who's picked, only the three trip figures do, so they
  /// sit in the strip and the spot's own numbers are one tap away instead of
  /// permanently on screen.
  /// The trip's figures — shared by the single-column strip and step 3.
  List<(String, String)> _statPairs() {
    if (_isHunt) {
      final o = _option;
      return [('Length', o.label), ('Finds', '${o.finds}')];
    }
    final plan = _plan;
    return [
      (
        'Haul',
        plan == null || !plan.isViable
            ? '—'
            : '${plan.amount.toStringAsFixed(0)} ${plan.resource}',
      ),
      ('Carry cap', plan?.loadCap.toStringAsFixed(0) ?? '0'),
      (
        'Duration',
        plan != null && plan.isViable ? fmtTripDuration(plan.duration) : '—',
      ),
    ];
  }

  /// The ⓘ behind the figures: a spot's stock and regrowth for gather, the
  /// find odds for a hunt.
  Widget _infoButton() {
    if (_isHunt) {
      return ParchmentInfoButton(
        title: 'Find odds',
        content: (_) => _oddsRows(_pool.map((s) => s.rarity).toSet()),
      );
    }
    final spot = widget.target.spot!;
    final plan = _plan;
    final stock = _expeditions.availableStock(spot);
    // Capacity / regen / mining speed are per-RESOURCE dials now (Dev Mode →
    // Resources), not per spot.
    final dials = gatherDefFor(spot.resource);
    return ParchmentInfoButton(
      title: 'Spot',
      content: (_) => [
        _kv(
          'In the ground',
          '${stock.toStringAsFixed(0)} / '
              '${dials.spotCapacity.toStringAsFixed(0)}',
        ),
        _bar(
          dials.spotCapacity <= 0 ? 0 : stock / dials.spotCapacity,
          kParchmentGo,
        ),
        const SizedBox(height: 8),
        _kv('Regrows', '${dials.regenPerHour.toStringAsFixed(0)}/h'),
        _kv(
          'Carry point',
          '${_fmtNum(dials.unitsPerCarry)} ${spot.resource}',
        ),
        const SizedBox(height: 8),
        _kv(
          'Mining rate',
          '${plan?.ratePerHour.toStringAsFixed(1) ?? '0'}/h',
        ),
      ],
    );
  }

  List<Widget> _gatherSections() {
    return [
      _statStrip(_statPairs(), trailing: _infoButton()),
      const SizedBox(height: 14),
      ..._groupSection(
        hint:
            'Mining speed is the group\'s gather stat; the load cap is its '
            'carry. A full load ends the trip.',
        // The two stats a miner is judged on, exactly where the caravan
        // picker puts its carry/speed pair.
        caption: (c) =>
            '⛏️ ${gatherPowerOf(c)}   '
            '🎒 ${c.statValue(CreatureStat.carry)}',
      ),
    ];
  }

  // ── Hunt ──────────────────────────────────────────────────
  // NO DURATION GRID any more (2026-10-01, Konzept 8) — every path into this
  // sheet for a hunt hands it an `initialOptionIndex` already (the
  // Expeditions hub's own 2×3 duration grid is the only way in; see
  // [ExpeditionsScreen._openHunt]), so re-offering the same six cards here
  // was the hub's own choice asked a second time. [_statStrip] carries what
  // the old left column did; what was the right-hand "Hunt length" grid is
  // now just more room for [_groupSection]. Catch timing and rarity odds
  // stay reference, one tap away behind the ⓘ (user 2026-07-30: "what lives
  // here kann komplett gelöscht werden... Seltenheit kann in ein kleines 'i'
  // gepackt werden") — rather than sitting between the player and the
  // decision.
  List<Widget> _huntSections() {
    return [
      _statStrip(_statPairs(), trailing: _infoButton()),
      const SizedBox(height: 14),
      ..._groupSection(
        caption: (c) => '🪤 ${c.statValue(CreatureStat.catchRate)}',
      ),
    ];
  }

  /// Find odds, one row per rarity — the SAME regardless of hunt length
  /// (2026-09-11: length only changes how many finds you get, never their
  /// odds, so there is nothing left to key this off the selected variant).
  ///
  /// Legendary always gets a row, even before [present] contains it — it
  /// never joins the pool until its region's boss is down (see
  /// [catchableSpecies]), so instead of a percentage it shows the reason it
  /// is missing rather than silently vanishing from the list.
  List<Widget> _oddsRows(Set<CreatureRarity> present) {
    final legendaryUnlocked = present.contains(CreatureRarity.legendary);
    final shown = [
      for (final r in CreatureRarity.values)
        if (r != CreatureRarity.legendary && present.contains(r)) r,
      CreatureRarity.legendary,
    ];
    final weights = rarityWeights();
    final total = shown
        .where((r) => r != CreatureRarity.legendary || legendaryUnlocked)
        .fold<double>(0, (s, r) => s + (weights[r] ?? 0));
    return [
      for (final r in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(
                r.label,
                style: FoE.label(size: 11).copyWith(color: r.color),
              ),
              const SizedBox(width: 6),
              Text(
                '${qteHitsRequired(r)} hit${qteHitsRequired(r) > 1 ? 's' : ''}',
                style: FoE.dim(size: 9).copyWith(color: kInkFaint),
              ),
              const Spacer(),
              if (r == CreatureRarity.legendary && !legendaryUnlocked)
                Text(
                  'beat the 1st boss',
                  style: FoE.dim(size: 9).copyWith(color: kInkFaint),
                )
              else
                Text(
                  total > 0
                      ? '${((weights[r] ?? 0) / total * 100).round()}%'
                      : '0%',
                  style: FoE.value(size: 11).copyWith(color: kInk),
                ),
            ],
          ),
        ),
    ];
  }

  // ── Group picker (shared) ─────────────────────────────────
  // PLACES, NOT A ROSTER (user 2026-07-30: "Unten nicht alle monster, sondern
  // diese Buttons entsprechend der möglichen Monsterzahl").
  //
  // It listed every free monster, which on a full collection is a wall of tiles
  // between the player and the Send button — and it never showed the one number
  // that decides the trip: how many may go. Now the sheet shows exactly that
  // many PLACES, the way the Market shows a caravan's, and filling one opens the
  // roster. Same frame as the Hatchery's egg slot and the breeding screen's
  // parents, so an empty place lines up with the tile that will fill it.
  //
  // Shared by hunt and gather: both ask "who goes", only the cap and the
  // caption differ.
  List<Widget> _groupSection({
    String? hint,
    bool header = true,
    required String Function(CreatureInstance) caption,
  }) => [
    if (header)
      ParchmentSectionHeader(
        title: 'Group',
        hint: '${_members.length} / $_groupCap chosen',
      ),
    if (hint != null)
      Text(hint, style: FoE.dim(size: 10).copyWith(color: kInkFaint)),
    // "THE SAME AGAIN" (user 2026-07-30). Sending a party is the most repeated
    // action in the game, and it was a fresh hunt through the roster every time.
    // Only shown when it would actually DO something: there is a remembered
    // party, somebody in it is still free, and they are not already picked.
    if (_lastPartyAvailable().isNotEmpty) ...[
      const SizedBox(height: 8),
      _sameAgainButton(),
    ],
    const SizedBox(height: 10),
    // The shared tile size (user 2026-08-31: "genau gleich gross sein wie
    // die Kacheln beim Monstersscreen"), not this sheet's own delegate.
    // Centred rather than left-hugging when there is only ONE place (user
    // 2026-09-11: "das '+' Feld zentrieren") — the 10 min hunt (and Gather,
    // early on) still caps at a single hunter, and a lone tile pinned to the
    // left of a full-width row reads as stranded.
    monsterTileGrid([
      for (var i = 0; i < _groupCap; i++)
        i < _members.length
            ? _filledPlace(_members[i])
            : _emptyPlace(isNext: i == _members.length),
    ], alignment: _groupCap == 1 ? WrapAlignment.center : WrapAlignment.start),
  ];

  /// A place waiting to be filled. A tap opens the roster.
  ///
  /// Only the NEXT one to be filled says "Add" — six copies of the word is
  /// noise, and one is a caption for the whole rank.
  Widget _emptyPlace({required bool isNext}) =>
      EmptyMonsterSlot(label: isNext ? 'Add' : null, onTap: _openPicker);

  /// A filled place: THE monster tile, unchanged from every other screen.
  ///
  /// A TAP OPENS THE ROSTER TO SWAP IT (user 2026-08-31: "das x im Kreis
  /// löschen, da ich mit anklicken das Monster austauschen kann") — no more
  /// ✗ badge; the tile itself is the only entry point now, same as the
  /// work-post picker's own filled seats. The roster offers a dedicated
  /// EMPTY tile for the case that used to be this tap's whole job.
  Widget _filledPlace(CreatureInstance c) => CreatureCard(
    creature: c,
    onTap: () => _openPicker(swapTargetId: c.id),
  );

  /// The roster, as a sheet over this one — opened only while a place is being
  /// filled, which is what keeps it off the page the rest of the time.

  /// The remembered party, minus whoever cannot go now (K.O., stationed away,
  /// breeding, already out) and minus anyone already picked — capped at the
  /// group size. Empty when the shortcut would change nothing.
  List<CreatureInstance> _lastPartyAvailable() {
    final ids = _expeditions
        .lastParty[_isHunt ? ExpeditionType.capture : ExpeditionType.gather];
    if (ids == null) return const [];
    final free = {for (final c in _available) c.id: c};
    final out = <CreatureInstance>[];
    for (final id in ids) {
      final c = free[id];
      if (c == null || _selected.contains(id)) continue;
      if (out.length + _selected.length >= _groupCap) break;
      out.add(c);
    }
    return out;
  }

  Widget _sameAgainButton() {
    final party = _lastPartyAvailable();
    final missing =
        (_expeditions
                .lastParty[_isHunt
                    ? ExpeditionType.capture
                    : ExpeditionType.gather]
                ?.length ??
            0) -
        party.length -
        _selected.length;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Feel.tap();
        setState(() {
          for (final c in party) {
            _selected.add(c.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: goldButton(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PixelIcon(Icons.replay_rounded, size: 14, color: kInk),
            const SizedBox(width: 6),
            Text(
              'Same as last time (${party.length})',
              style: FoE.label(size: 11).copyWith(color: kInk),
            ),
            // Honest about what it CANNOT bring back — silently sending a
            // smaller party than the one you remember is the worse failure.
            if (missing > 0) ...[
              const SizedBox(width: 6),
              Text(
                '· $missing busy',
                style: FoE.dim(size: 10).copyWith(color: kInkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Candidates the roster actually offers. Opened plain (from an empty
  /// place), it is every free monster, exactly as before — the multi-pick
  /// flow taps several in a row. Opened to SWAP one member, the outgoing
  /// monster is left off the list (the dedicated empty tile is how you
  /// clear it instead) and so is anyone ELSE already in the group — picking
  /// one of those would silently shrink the party rather than swap it.
  List<CreatureInstance> get _pickerCandidates {
    final swapping = _swapTargetId;
    if (swapping == null) return _available;
    return _available
        .where((c) => c.id != swapping && !_selected.contains(c.id))
        .toList();
  }

  Future<void> _openPicker({String? swapTargetId}) async {
    if (_available.isEmpty) {
      _say('Nobody is free — everyone is K.O., stationed, breeding or out.');
      return;
    }
    _swapTargetId = swapTargetId;
    final swapping = swapTargetId != null;

    // Sort/filter/search, added everywhere a monster or a group is picked
    // (user 2026-09-11: "überall, wo ich ein Monster oder eine Gruppe
    // auswähle, sollen diese nach dem entsprechenden Wert geordnet sein und
    // eine Sortier, Filter- und Suchfunktion haben"). The controller is
    // [_pickerSearch], a State field — NOT created and disposed here per
    // open (see that field's own comment for why that crashed).
    _pickerSearch.clear();
    String query = '';
    CreatureElement? filterElement;
    String? sortKey; // null = the trip's own stat (catch rate / mining power)
    bool descending = true;
    // Tapping a candidate only PREVIEWS it here (user 2026-10-05, "Konzept
    // 4") — the detail panel's own button is what actually adds, removes or
    // swaps it.
    CreatureInstance? preview;

    double primary(CreatureInstance c) => _isHunt
        ? c.statValue(CreatureStat.catchRate).toDouble()
        : gatherPowerOf(c).toDouble();

    List<CreatureInstance> filtered() {
      final q = query.trim().toLowerCase();
      final list = [
        for (final c in _pickerCandidates)
          if ((filterElement == null || c.species?.element == filterElement) &&
              (q.isEmpty || c.displayName.toLowerCase().contains(q)))
            c,
      ];
      int cmp(CreatureInstance a, CreatureInstance b) {
        final r = switch (sortKey) {
          'level' => a.level.compareTo(b.level),
          'name' => a.displayName.compareTo(b.displayName),
          _ => primary(a).compareTo(primary(b)),
        };
        return descending ? -r : r;
      }

      list.sort(cmp);
      return list;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParchmentSheet(
        // Named for what it picks, not the question that opens it (user
        // 2026-08-31: "dieser Screen heisst Group") — the same word the
        // section above it already carries.
        title: 'Group',
        initialSize: 0.7,
        builder: (sheetCtx, scrollCtrl) => StatefulBuilder(
          // Its own builder so a pick repaints the picker; the places behind it
          // catch up when it closes.
          builder: (sheetCtx, setSheetState) {
            final candidates = filtered();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kMonsterTilePageMargin,
                    4,
                    kMonsterTilePageMargin,
                    8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: SearchPill(
                          controller: _pickerSearch,
                          palette: PillPalette.cream,
                          onChanged: (v) => setSheetState(() => query = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: MenuPill<String>(
                          palette: PillPalette.cream,
                          icon: Icons.swap_vert,
                          label: switch (sortKey) {
                            'level' => 'Level',
                            'name' => 'Name',
                            _ => _isHunt ? 'Catch' : 'Mining',
                          },
                          engaged: sortKey != null || !descending,
                          value: sortKey ?? '',
                          entries: [
                            MapEntry('', _isHunt ? 'Catch' : 'Mining'),
                            const MapEntry('level', 'Level'),
                            const MapEntry('name', 'Name'),
                          ],
                          trailing: PixelIcon(
                            descending
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 14,
                            color: FoE.goldBright,
                          ),
                          selectedTrailing: descending ? '↓' : '↑',
                          onSelected: (v) => setSheetState(() {
                            final picked = v.isEmpty ? null : v;
                            if (picked == sortKey) {
                              descending = !descending;
                            } else {
                              sortKey = picked;
                              descending = true;
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
                          label: filterElement?.label ?? 'Every type',
                          engaged: filterElement != null,
                          value: filterElement?.name ?? '',
                          entries: [
                            const MapEntry('', 'Every type'),
                            for (final e in CreatureElement.values)
                              if (e != CreatureElement.neutral)
                                MapEntry(e.name, '${e.emoji} ${e.label}'),
                          ],
                          onSelected: (v) => setSheetState(
                            () => filterElement = v.isEmpty
                                ? null
                                : CreatureElement.fromName(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          left: kMonsterTilePageMargin,
                        ),
                        child: _pickerDetail(preview, sheetCtx, setSheetState),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GridView.builder(
                          controller: scrollCtrl,
                          // 24, not 26 (user 2026-08-31: "genau gleich gross
                          // sein wie die Kacheln beim Monstersscreen") — the
                          // 2px difference from [kMonsterTilePageMargin] was
                          // enough to hand every tile in this sheet a
                          // slightly narrower cell than the Monsters grid's
                          // own.
                          padding: const EdgeInsets.fromLTRB(
                            0,
                            0,
                            kMonsterTilePageMargin,
                            20,
                          ),
                          gridDelegate: monsterTileGridDelegate(sheetCtx),
                          itemCount: candidates.length + (swapping ? 1 : 0),
                          itemBuilder: (_, i) {
                            // A dedicated EMPTY tile (user 2026-08-31: "beim
                            // Auswahlscreen eine 'leere' Kachel anbieten, wenn
                            // ich diese anwähle, dann ist dieser Slot leer")
                            // — swapping in nothing, the same clearing job
                            // the ✗ badge used to do, but as a real choice in
                            // the roster instead of a shortcut on the tile
                            // behind it. Clearing is unambiguous, so it stays
                            // a single tap rather than going through preview.
                            if (swapping && i == 0) {
                              return EmptyMonsterSlot(
                                label: 'Empty',
                                onTap: () {
                                  setState(
                                    () => _selected.remove(_swapTargetId),
                                  );
                                  Navigator.pop(sheetCtx);
                                },
                              );
                            }
                            final c = candidates[i - (swapping ? 1 : 0)];
                            return _pickerTile(
                              c,
                              preview,
                              (p) => setSheetState(() => preview = p),
                            );
                          },
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
    );
    _swapTargetId = null;
    if (mounted) setState(() {});
  }

  /// The left panel: the stat this trip actually judges a member on, plus
  /// carry — not combat power or HP, which neither hunting nor gathering
  /// cares about.
  Widget _pickerDetail(
    CreatureInstance? preview,
    BuildContext sheetCtx,
    void Function(VoidCallback) setSheetState,
  ) {
    if (preview == null) {
      return const PickerDetailPanel(
        placeholder: 'Tap a monster to see its details.',
      );
    }
    final picked = _selected.contains(preview.id);
    final swapping = _swapTargetId != null;
    final label = swapping
        ? 'Swap in'
        : (picked ? 'Remove from group' : 'Add to group');
    return PickerDetailPanel(
      art: CreatureCard(creature: preview, showHp: true),
      title: preview.displayName,
      subtitle: 'Lv ${preview.level}',
      rows: [
        pickerStatRow(
          _isHunt ? 'Catch' : 'Mining',
          '${_isHunt ? preview.statValue(CreatureStat.catchRate) : gatherPowerOf(preview)}',
        ),
        pickerStatRow('Carry', '${preview.statValue(CreatureStat.carry)}'),
      ],
      action: pickerChooseButton(
        label: label,
        onTap: () {
          if (_swapTargetId != null) {
            setState(() {
              _selected.remove(_swapTargetId);
              _selected.add(preview.id);
            });
            Navigator.pop(sheetCtx);
            return;
          }
          _toggle(preview);
          setSheetState(() {});
          // A full group means the question is answered; holding the picker
          // open would leave a list that refuses every further tap.
          if (_members.length >= _groupCap) {
            Navigator.pop(sheetCtx);
          }
        },
      ),
    );
  }

  Widget _pickerTile(
    CreatureInstance c,
    CreatureInstance? preview,
    ValueChanged<CreatureInstance> onPreview,
  ) {
    final picked = _selected.contains(c.id);
    return pickerPreviewFrame(
      active: preview?.id == c.id,
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: picked ? 0.45 : 1,
              child: CreatureCard(
                creature: c,
                // The stat this trip is actually judged on, in the tile
                // itself (user 2026-08-31: "den gleichen Stil übernehmen" —
                // the work-post picker's flag on the tile)
                // instead of a caption line below it.
                extras: [
                  TileValue(
                    _isHunt ? 'Catch' : 'Mining',
                    _isHunt
                        ? c.statValue(CreatureStat.catchRate)
                        : gatherPowerOf(c),
                  ),
                ],
                onTap: () => onPreview(c),
              ),
            ),
          ),
          if (picked)
            const Positioned(
              top: 2,
              left: 2,
              child: PixelIcon(Icons.check_circle, size: 18, color: kAccent),
            ),
        ],
      ),
    );
  }

  // ── Send ──────────────────────────────────────────────────
  Widget _sendBar() {
    final full = _expeditions.slotsFull;
    final plan = _plan;
    final ready = _isHunt
        ? _members.isNotEmpty
        : _members.isNotEmpty && plan != null && plan.isViable;
    final canSend = !_sending && !full && ready;

    final label = full
        // Zero slots is not a queue — name the building that opens them
        // instead of a busy party that isn't there (user 2026-07-29).
        ? _expeditions.noSlots
              ? 'No expedition slots — build a Scout Post'
              : 'All expedition slots busy '
                    '(${_expeditions.activeCount}/${_expeditions.maxSlots})'
        : _isHunt
        ? ready
              ? 'Send ${_option.label} hunt'
              : 'Pick who goes'
        : ready
        ? 'Send expedition · ${fmtTripDuration(plan!.duration)}'
        : _members.isEmpty
        ? 'Pick who goes'
        : 'Nothing left to mine here';

    // No footer chrome or bottom safe-area padding — there is no fixed-height
    // sheet to foot any more (2026-10-02): this bar is just the next thing in
    // the composer's own column.
    return SizedBox(
      width: double.infinity,
      child: _sending
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAccent,
                  ),
                ),
              ),
            )
          : ParchmentButton(
              label: label,
              expand: true,
              primary: canSend,
              onTap: canSend ? _send : null,
            ),
    );
  }

  // ── Small shared pieces ───────────────────────────────────
  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        // Expanded + ellipsis, not a Spacer (2026-09-29, the two-column
        // launch sheet): a Spacer only shrinks the GAP, so a label/value
        // pair that is merely SNUG in the old wide panel overflows outright
        // in the new 160px info rail ("Carry point" + "20 wood" does). The
        // label is the one that can afford to lose a word; the value never
        // truncates.
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FoE.dim(size: 11).copyWith(color: kInkFaint),
          ),
        ),
        const SizedBox(width: 6),
        Text(value, style: FoE.value(size: 12).copyWith(color: kInk)),
      ],
    ),
  );

  Widget _bar(double fraction, Color color) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: RecessBar(value: fraction.clamp(0.0, 1.0), color: color, height: 9),
  );

  /// 20 → "20", 0.5 → "0.5" — carry weights are not always whole.
  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// Trip lengths read as "1h 20m" / "12m" / "45s" everywhere they appear — the
/// planner sheet and the running-trip cards shared two near-identical copies of
/// this before.
String fmtTripDuration(Duration d) {
  if (d.inSeconds <= 0) return 'instant';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
