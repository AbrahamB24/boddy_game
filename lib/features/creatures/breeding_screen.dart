import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../../core/theme/cream_kit.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/settlement_controller.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'widgets/creature_sprite.dart';
import 'models/creature_instance.dart';
import 'models/species_balance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/breeding_cost.dart';
import 'services/creatures_controller.dart';
import 'widgets/creature_card.dart';
import 'widgets/gene_bar_toggle.dart';
import 'widgets/picker_detail_panel.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';
import '../../core/ui/game_text.dart';

// The Breeding Hut: MATING, and nothing after it (user 2026-07-26 — "Eggs
// müssen nicht angezeigt werden … und die Hatchery auch nicht, da dies ein
// eigenes Gebäude ist"). Top: the matings running, with live countdowns.
// Bottom: pick the two parents and start the timer.
//
// Picking is a COMPARISON, not a form: you choose a monster (its species picks
// the partner's list for you) and the panel lays the two sets of genes side by
// side, because that — plus the odds the better gene wins — is the whole
// decision. Eggs, incubation and hatching live on the Hatchery screen.
class BreedingPane extends StatefulWidget {
  const BreedingPane({super.key});

  @override
  State<BreedingPane> createState() => _BreedingPaneState();
}

class _BreedingPaneState extends State<BreedingPane> {
  // ── Ink on parchment (user 2026-07-26: "gestalte das Breeding menü neu
  // und den anderen Menüs entsprechend") ──
  // The build menu, the building dialog, the worker sheet and the upgrade
  // preview all share one surface; this page was the last dark screen among
  // them, and it is reached from the same building.
  static const Color _ink = kBoxInk;
  static final Color _inkSoft = kBoxInk.withValues(alpha: 0.78);
  static const Color _accent = CreamPalette.accent;

  /// The page and the picker sheet are both the kit's cream now, so one ink
  /// serves both; these are the names the page's own text used while it sat on a
  /// dark ground.
  static const Color _pageInk = kBoxInk;
  static final Color _pageInkSoft = kBoxInk.withValues(alpha: 0.78);
  static final Color _pageInkFaint = kBoxInk.withValues(alpha: 0.5);

  /// This page is cream, so its pills are.
  static final PillPalette _pills = PillPalette.cream;

  final _breeding = BreedingController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  // No species field any more: you pick a MONSTER and its species decides the
  // other slot's list (user 2026-07-26 — the dropdown asked you to name a
  // species before you had chosen anything, which is backwards).
  //
  // And no ♂/♀ slot any more (user 2026-07-27: "Es ist egal, welches Monster
  // ich zuerst auswähle"). The slots are just FIRST and SECOND: whichever you
  // fill first decides what the other one has to be — same species, other
  // gender — and the tile already shows which that is.
  String? _slotAId;
  String? _slotBId;
  bool _busy = false;

  /// Which gene the comparison bars are drawn from — see [GeneBarToggle].
  bool _barsShowGrowth = false;

  /// Which level every figure on the page is worked out at (user 2026-09-28: "auf
  /// lvl1 und level max umschalten … dann wechselt auch die Energieanzeige") —
  /// the current level, level 1 (the genes, what a child starts from) or the
  /// maximum.
  int _refIndex = 0; // 0 = now, 1 = level 1, 2 = the maximum
  /// The level to work out at; null = each monster's own (Now).
  int? get _refLevel => switch (_refIndex) {
    1 => 1,
    2 => kCreatureMaxLevel,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _creatures.load();
    _breeding.load();
    // Live countdowns; cheap enough to just rebuild every second while open.
    // Also promotes any finished mating to a collectable egg on the spot.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _breeding.jobs.isEmpty) return;
      _breeding.refreshEggs();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Free to breed right now: not K.O., not already in a job.
  bool _available(CreatureInstance c) =>
      !c.isKo && !_creatures.isBreeding(c.id);

  /// Species you own an available male AND female of — the only ones worth
  /// offering, since anything else is a pick that cannot be completed.
  Set<String> get _breedableSpeciesIds {
    final byId = <String, Set<CreatureGender>>{};
    for (final c in _creatures.creatures) {
      if (!_available(c)) continue;
      final def = kSpeciesDefs[c.speciesId];
      if (def == null || !rarityCanBreed(def.rarity)) continue;
      byId.putIfAbsent(c.speciesId, () => {}).add(c.gender);
    }
    return {
      for (final e in byId.entries)
        if (e.value.length == 2) e.key,
    };
  }

  /// The species the pair is locked to once either slot is filled.
  String? get _pairSpeciesId =>
      _byId(_slotAId)?.speciesId ?? _byId(_slotBId)?.speciesId;

  /// Who may fill a slot whose PARTNER slot holds [otherId].
  ///
  /// With the partner empty: every creature of a species you own a breedable
  /// male AND female of — either gender, since neither slot is a gender any
  /// more. With the partner chosen: its species, and the other gender. Best
  /// genes first, which is the whole reason to look at this list.
  List<CreatureInstance> _candidatesFor(String? otherId) {
    final other = _byId(otherId);
    final breedable = _breedableSpeciesIds;
    return [
      for (final c in _creatures.creatures)
        if (_available(c) &&
            (other == null
                ? breedable.contains(c.speciesId)
                : c.speciesId == other.speciesId && c.gender != other.gender))
          c,
    ]..sort((a, b) => _geneScore(b).compareTo(_geneScore(a)));
  }

  /// Sum of a creature's GENES — the numbers a child actually inherits, so the
  /// one figure that ranks breeding stock. Level plays no part: a levelled
  /// monster shows bigger stats but passes on the same genes.
  double _geneScore(CreatureInstance c) => CreatureStat.values.fold<double>(
    0,
    (sum, s) => sum + (c.statBase[s] ?? 0),
  );

  CreatureInstance? _byId(String? id) {
    if (id == null) return null;
    for (final c in _creatures.creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _start() async {
    final a = _byId(_slotAId);
    final b = _byId(_slotBId);
    if (a == null || b == null) return;
    // The job row keeps parent A as the father, so the running card can print
    // "♂ × ♀" without looking anything up — the slots no longer say which is
    // which, so sort them here.
    final male = a.gender == CreatureGender.male ? a : b;
    final female = identical(male, a) ? b : a;
    setState(() => _busy = true);
    final error = await _breeding.start(male, female);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _slotAId = null;
        _slotBId = null;
      }
    });
    context.snack(error ?? '💞 Breeding started!');
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  // The BREEDING half of the merged Breeding & Hatchery page (user 2026-09-20:
  // "hatchery und breeding sollten zusammen sein wie worker und population").
  // The page's own frame — title, tabs, close — lives in HatcheryScreen.
  //
  // Mating (a running queue) and New pair (an action panel) ARE different
  // Gebiete (user 2026-09-29, "Trennlinien und Zonen gemischt", app-wide), so
  // Mating gets a [zoneBox] of its own — its edge is separation enough on its
  // own. (HatcheryScreen's MenuScaffold is the one card now — no [pageCard]
  // here, or this would nest a card inside its card.)
  /// Below this height the page is laid out at this height and scaled down as
  /// a whole — a cramped window only. The app's own landscape screen gives the
  /// pane ~293 px (measured 2026-11-03 at 932×430), so it never shrinks there.
  static const double _kMinPaneHeight = 260;

  // "BREITE WAAGE" (user 2026-11-03, concept 1 of 10: "Text und die Stats viel
  // zu klein"). The old page gave a Mating column a quarter of the width and
  // then SCALED the new-pair panel down to fit what was left. Now:
  //   · the matings are a chip in the foot row, opening a sheet;
  //   · the two parents stand at the left and right edge;
  //   · the gene table runs between them over the full height, one row per
  //     stat, so nothing has to be scaled at all;
  //   · the foot carries the switches, the odds, the time and Breed.
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_breeding, _creatures]),
    builder: (context, _) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, c) {
          if (c.maxHeight.isFinite && c.maxHeight >= _kMinPaneHeight) {
            return _pane();
          }
          return FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: c.maxWidth,
              height: _kMinPaneHeight,
              child: _pane(),
            ),
          );
        },
      ),
    ),
  );

  Widget _pane() {
    final a = _byId(_slotAId);
    final b = _byId(_slotBId);
    final Widget middle;
    if (_candidatesFor(null).isEmpty) {
      middle = _centreNote(
        'You need an available male AND female of the same species '
        '(not K.O., not already breeding).',
      );
    } else if (a != null && b != null) {
      middle = _geneTable(a, b);
    } else {
      middle = _centreNote(
        a == null && b == null
            ? 'Choose two parents — their genes are compared here.'
            : 'Now choose the partner.',
      );
    }
    final picking = _candidatesFor(null).isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (picking) _parentColumn(first: true, c: a),
              if (picking) const SizedBox(width: 12),
              Expanded(child: middle),
              if (picking) const SizedBox(width: 12),
              if (picking) _parentColumn(first: false, c: b),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(height: 46, child: _footer(a, b)),
      ],
    );
  }

  Widget _centreNote(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: FoE.dim(size: 15).copyWith(color: _pageInkSoft),
      ),
    ),
  );

  /// One parent at the page's edge: the Monsters tile, centred in its column.
  Widget _parentColumn({required bool first, required CreatureInstance? c}) =>
      SizedBox(
        width: _kTileW,
        child: Center(
          child: _parentSlot(first: first, c: c),
        ),
      );

  /// The foot row: the matings chip, the two switches, the odds and time,
  /// and Breed.
  Widget _footer(CreatureInstance? a, CreatureInstance? b) {
    final species = kSpeciesDefs[_pairSpeciesId];
    final both = a != null && b != null;
    return Row(
      children: [
        _matingChip(),
        if (a != null || b != null) ...[
          const SizedBox(width: 10),
          // WHICH LEVEL the numbers (and each tile's ⚡) are worked out at …
          LevelRefToggle(
            index: _refIndex,
            onChanged: (i) => setState(() => _refIndex = i),
            ink: _pageInk,
            inkFaint: _pageInkFaint,
            accent: CreamPalette.accent,
          ),
        ],
        if (both) ...[
          const SizedBox(width: 8),
          // … and WHICH gene the bars draw.
          GeneBarToggle(
            showGrowth: _barsShowGrowth,
            onChanged: (v) => setState(() => _barsShowGrowth = v),
            ink: _pageInk,
            inkFaint: _pageInkFaint,
            accent: CreamPalette.accent,
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: species == null || !both
              ? const SizedBox()
              : FittedBox(fit: BoxFit.scaleDown, child: _footInfo(species)),
        ),
        // NO BUTTON WITH BOTH SLOTS EMPTY (user 2026-07-27: "pick both
        // parents kann gelöscht werden").
        if (a != null || b != null) ...[
          const SizedBox(width: 10),
          SizedBox(width: 210, child: _breedButton(a, b)),
        ],
      ],
    );
  }

  /// The odds and the real mating time, as two short lines in the foot.
  Widget _footInfo(SpeciesDef species) {
    final favored = breedingFavoredChance();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            style: FoE.dim(size: 13).copyWith(color: _pageInkSoft),
            children: [
              const TextSpan(text: 'Each stat: '),
              TextSpan(
                text: '${(favored * 100).round()} %',
                style: const TextStyle(
                  color: CreamPalette.better,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const TextSpan(text: ' the better parent\'s'),
            ],
          ),
        ),
        const SizedBox(height: 2),
        _timeLine(species),
      ],
    );
  }

  /// Breed, with the price and the duration on its sub-line (user
  /// 2026-07-27): the same face as Upgrade, red sub-line when the store
  /// cannot cover it.
  Widget _breedButton(CreatureInstance? a, CreatureInstance? b) {
    final species = kSpeciesDefs[_pairSpeciesId];
    // A mating COSTS SUPPLIES (user 2026-07-27), in the goods of the era the
    // PARENTS come from.
    final stock = SettlementController().resources?.asMap ?? const {};
    final cost = a == null || b == null
        ? const <String, double>{}
        : breedCost(a, b, stock);
    final affordable = canAffordBreed(cost, stock);
    final canStart = a != null && b != null && affordable && !_busy;
    return Pressable(
      onTap: canStart ? _start : null,
      child: Container(
        alignment: Alignment.center,
        decoration: goldButton(active: canStart),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A greyed button that repeats its own label says it is off but
            // not WHY. Name the missing half instead.
            Text(
              a == null || b == null ? 'Pick the partner' : 'Breed',
              style: TextStyle(
                fontSize: 17,
                height: 1.1,
                fontWeight: FontWeight.w400,
                color: goldButtonInk(active: canStart),
              ),
            ),
            if (cost.isNotEmpty && species != null)
              Text(
                '${breedCostLabel(cost)}   '
                '⏱ ${_hoursText(_matingHours(species))}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w400,
                  color: affordable
                      ? goldButtonInk(active: canStart)
                      : CreamPalette.warn,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The matings running, folded into one chip ("2 mating · next 47m 05s")
  /// that opens them as a sheet — the column they had took a quarter of the
  /// page from the gene table.
  Widget _matingChip() {
    final jobs = _breeding.matingJobs;
    final next = jobs.isEmpty
        ? null
        : jobs.map((j) => j.remaining).reduce((x, y) => x < y ? x : y);
    return Pressable(
      onTap: jobs.isEmpty ? null : _showMatings,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: raisedTile(radius: 18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PixelIcon(
              Icons.favorite,
              size: 15,
              color: jobs.isEmpty ? _pageInkFaint : CreamPalette.warn,
            ),
            const SizedBox(width: 6),
            Text(
              jobs.isEmpty
                  ? 'No pair mating'
                  : '${jobs.length} mating · next ${_fmt(next!)}',
              style: FoE.label(
                size: 13,
              ).copyWith(color: jobs.isEmpty ? _pageInkFaint : _ink),
            ),
          ],
        ),
      ),
    );
  }

  /// The running matings, each with its speed-up and cancel — on the same
  /// parchment sheet the parent picker uses. Ticks every second for the
  /// countdowns.
  Future<void> _showMatings() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => StreamBuilder<int>(
      stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
      builder: (ctx, _) => ListenableBuilder(
        listenable: _breeding,
        builder: (ctx, _) {
          final jobs = _breeding.matingJobs;
          return Container(
            margin: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 360, maxWidth: 520),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
              ),
              borderRadius: vr(16),
              border: Border.all(
                color: CreamPalette.tan.withValues(alpha: 0.6),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mating',
                  style: FoE.title(size: 15).copyWith(color: _ink),
                ),
                const SizedBox(height: 10),
                if (jobs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'No pair mating.',
                      style: FoE.dim(size: 13).copyWith(color: _pageInkFaint),
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [for (final job in jobs) _jobCard(job)],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    ),
  );

  /// One running MATING. The egg it will lay, and everything after, belongs to
  /// the Hatchery screen — this page ends when the timer does.
  Widget _jobCard(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final a = _byId(job.parentAId);
    final b = _byId(job.parentBId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      // A raised tile on the card.
      decoration: raisedTile(radius: 12),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: species?.stageAt(0).imageUrl == null
                ? PixelIcon(Icons.pets, color: _accent, size: 26)
                : CreatureSprite(
                    url: species!.stageAt(0).imageUrl!,
                    fallback: PixelIcon(Icons.pets, color: _accent, size: 26),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  species?.name ?? job.speciesId,
                  style: FoE.label(size: 14).copyWith(color: _ink),
                ),
                Text(
                  '${a?.displayName ?? '?'} ♂ × ${b?.displayName ?? '?'} ♀',
                  style: FoE.dim(size: 10).copyWith(color: _inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  '⏳ ${_fmt(job.remaining)}',
                  style: FoE.label(size: 12).copyWith(color: _inkSoft),
                ),
              ],
            ),
          ),
          ..._jobActions(job),
        ],
      ),
    );
  }

  /// The trailing actions for a running mating: the optional speed-up item,
  /// the dev skip, and cancel. Eggs and incubations are the HATCHERY's job
  /// (user 2026-07-26), so nothing here places or hatches one.
  /// NO TOOLTIPS here (2026-07-27, chasing `mouse_tracker.dart` assertions on
  /// desktop). A Tooltip registers with the global MouseTracker in initState
  /// and unregisters in dispose, and these come and go on their own: the card
  /// rebuilds every second from the countdown ticker, and the first action
  /// appears and vanishes with the player's accelerator items. One created or
  /// disposed WHILE the tracker walks its listeners mutates that list
  /// mid-notification — which is what the assert catches. Semantics labels the
  /// buttons for screen readers without touching the tracker.
  List<Widget> _jobActions(BreedingJob job) => [
    if (_heldSpeedItems().isNotEmpty)
      Semantics(
        label: 'Speed up (item)',
        button: true,
        child: IconButton(
          icon: PixelIcon(Icons.bolt, color: _accent, size: 18),
          onPressed: _busy ? null : () => _useAccelerator(job),
        ),
      ),
    Semantics(
      label: 'Cancel',
      button: true,
      child: IconButton(
        icon: const PixelIcon(Icons.close, color: CreamPalette.warn, size: 18),
        onPressed: () => _breeding.cancel(job),
      ),
    ),
  ];

  /// breedSpeed items currently in the bag (id → count).
  List<MapEntry<String, int>> _heldSpeedItems() => [
    for (final e in SettlementController().items.entries)
      if (kItemDefs[e.key]?.kind == ItemKind.breedSpeed) e,
  ];

  Future<void> _useAccelerator(BreedingJob job) async {
    final held = _heldSpeedItems();
    if (held.isEmpty) return;
    setState(() => _busy = true);
    final err = await _breeding.useSpeedItem(job, held.first.key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) context.snack(err);
  }

  /// What a mating will ACTUALLY take: the rarity base already cut by the
  /// breeders posted in the hut (user 2026-07-26). Showing the raw base here
  /// contradicted the countdown the job then started with.
  double _matingHours(SpeciesDef s) => breedingHours(
    kSpeciesBalance.of(s.rarity).breedHours,
    SettlementController().breedingPower(kBreedingHutBuildingId),
  );

  /// "Mating time  12 h → 8 h 30 min  (−29 % from your breeders)".
  Widget _timeLine(SpeciesDef species) {
    final base = kSpeciesBalance.of(species.rarity).breedHours;
    final eff = _matingHours(species);
    final cut = base <= 0 ? 0.0 : (1 - eff / base).clamp(0.0, 1.0);
    final saved = cut >= 0.005;
    return Center(
      child: Text.rich(
        TextSpan(
          style: FoE.dim(size: 13).copyWith(color: _pageInkSoft),
          children: [
            const TextSpan(text: 'Mating time  '),
            if (saved) ...[
              TextSpan(
                text: _hoursText(base),
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
              const TextSpan(text: '  →  '),
            ],
            TextSpan(
              text: _hoursText(eff),
              style: FoE.value(size: 15).copyWith(color: _pageInk),
            ),
            TextSpan(
              text: saved
                  ? '   −${(cut * 100).round()} % from your breeders'
                  : '   no breeders posted',
              style: TextStyle(
                color: saved ? CreamPalette.better : _pageInkFaint,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// 12 → "12 h", 8.5 → "8 h 30 min", 0.4 → "24 min".
  static String _hoursText(double hours) {
    final totalMin = (hours * 60).round();
    if (totalMin <= 0) return '0 min';
    final h = totalMin ~/ 60, m = totalMin % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  /// One parent slot: the MONSTER TILE from the Monsters screen (user
  /// 2026-07-27 — "brauche hier die Kachel vom Monstermenü"), or an empty frame
  /// of the same shape inviting you to choose one.
  ///
  /// The tile rather than a bespoke sprite-plus-name row because it is the
  /// picture of a monster the player already reads everywhere else — name,
  /// level, power, gender, HP and element, in one glance. Tapping always
  /// reopens the list, so swapping a parent is one tap, not a clear then a
  /// pick.
  /// NO ♂/♀ CAPTION (user 2026-07-27: "Male und Female löschen … dies ist auf
  /// der Kachel bereits beschrieben"). The tile carries the gender symbol, and
  /// the slots are not genders any more — whichever you fill first decides what
  /// the other one may be.
  Widget _parentSlot({
    required bool first,
    required CreatureInstance? c,
  }) => Builder(
    builder: (context) => SizedBox(
      // The Monsters grid's own tile, in its own PIXELS (user
      // 2026-08-31: "genau gleich gross sein wie die Kacheln beim
      // Monstersscreen") — an AspectRatio here only fixed the shape;
      // the actual size still came from however wide this Row's own
      // Expanded happened to split, which is not the grid's width.
      // Fixed landscape size (2026-09-18): monsterTileWidth reads the
      // device's raw WIDTH, now the long axis, and would size this tile
      // taller than the whole screen. Same 0.6 aspect the tile expects.
      width: _kTileW,
      height: _kTileW / kMonsterTileAspect,
      child: c == null
          ? _emptySlot(first)
          : CreatureCard(
              creature: c,
              onTap: () => _pickParent(first),
              // No HP bar here (user 2026-07-27): a parent is picked on its
              // genes, not on its wounds. The current power stays in the foot;
              // the level-1 one (its genes) hangs from the tile as a flag.
              showHp: false,
              atLevel: _refLevel,
            ),
    ),
  );

  /// An unfilled parent slot, in the BUILD MENU'S dead-card style (user
  /// 2026-07-27: "Nimm für die Kacheln die Kacheln der Gebäude, welche nicht
  /// gebaut werden können vom Stil") — a faded ink fill with the soft brown
  /// shadow that makes it lie ON the paper, and no outline. An empty slot and
  /// an unaffordable building are the same thing: a card with nothing in it
  /// yet.
  Widget _emptySlot(bool first) =>
      EmptyMonsterSlot(label: 'Choose', onTap: () => _pickParent(first));

  // The gene table's fixed column widths, shared by the header and the rows so
  // every caption sits over the number it names.
  static const double _kGeneValueW = 34;
  static const double _kGeneGrowthW = 34;
  static const double _kGeneLabelW = 100;

  /// The parent tiles' width at the page's edges (the Monsters grid's 0.6
  /// aspect, so ~207 px tall — fits the ~239 px the table row gets).
  static const double _kTileW = 124;

  /// One gene value. The BETTER of the two is GREEN and BOLD (user 2026-07-27),
  /// the other faint — the contrast is visible before you read anything, where
  /// a ★ made you read the whole row to find the mark.
  ///
  /// Every value sits in a FIXED-WIDTH box, centred: bold glyphs are wider than
  /// plain ones, so without it the numbers would shuffle sideways as the winner
  /// changes from row to row and the table would never line up.
  Widget _geneValue(
    String text,
    bool better, {
    required double size,
    required double width,
  }) => SizedBox(
    width: width,
    child: Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      style: (size >= 14 ? FoE.value(size: size) : FoE.dim(size: size))
          .copyWith(
            height: 1,
            color: better ? CreamPalette.better : _pageInkFaint,
            fontWeight: better ? FontWeight.w400 : FontWeight.w400,
          ),
    ),
  );

  /// THE decision, laid out (user 2026-07-26: "Ich muss sicherlich sehen,
  /// welche Stats die Eltern haben").
  ///
  /// A child inherits each gene independently: the BETTER parent's value with
  /// probability [breedingFavoredChance] of the pair's breeding stat, the worse
  /// one otherwise. So the table compares GENES — not the level-scaled stats
  /// shown elsewhere, because a levelled parent has bigger numbers and passes
  /// on exactly the same genes.
  ///
  /// TWO genes per stat (user 2026-07-27: "Das Wachstum pro Stufe muss ebenfalls
  /// angezeigt und vererbt werden"). The starting value and the GROWTH PER LEVEL
  /// are separate genes and are rolled separately, so a parent can lose the
  /// first and win the second — which the table has to show, or half of what is
  /// being inherited is invisible.
  Widget _geneTable(CreatureInstance a, CreatureInstance b) {
    // BARS, MIRRORED FROM THE CENTRE (user 2026-07-27: "kannst du hier auch die
    // Balken machen, dass es immernoch ersichtlich ist, welches der Monster wo
    // besser ist?"). Each parent's bar grows away from the stat label, so the
    // two are read against each other by LENGTH — a butterfly chart — while the
    // green bold number keeps saying which one won.
    //
    // Both sides share ONE scale, the biggest gene either parent has, so a bar
    // is comparable across rows as well as across the middle. Scaling each row
    // to its own max would make every row's winner a full bar and say nothing.
    //
    // WHICH gene follows the header switch (user 2026-07-27) — and so does the
    // scale, or a growth of +3 would be a hairline against a base of 80.
    // The VALUE bars follow the level switch (Lv 1 or Max); growth is per level
    // whichever level is chosen.
    Map<CreatureStat, double> atRef(CreatureInstance c) => {
      for (final s in CreatureStat.values)
        s: c.statValueAtLevel(s, _refLevel ?? c.level).toDouble(),
    };
    final aGenes = _barsShowGrowth ? a.statSlope : atRef(a);
    final bGenes = _barsShowGrowth ? b.statSlope : atRef(b);
    final maxVal = CreatureStat.values.fold<double>(0.001, (m, s) {
      final av = aGenes[s] ?? 0;
      final bv = bGenes[s] ?? 0;
      return math.max(m, math.max(av, bv));
    });

    /// One side's bar. [mirrored] grows it leftwards, out of the centre.
    Widget bar(double value, bool wins, {required bool mirrored}) => Padding(
      // Sits with the number's baseline rather than at the top of the row.
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Directionality(
        textDirection: mirrored ? TextDirection.rtl : TextDirection.ltr,
        child: RecessBar(
          value: (value / maxVal).clamp(0.0, 1.0),
          // The winner's bar is the SAME green as its number, so colour and
          // length agree instead of being two separate readings.
          color: wins
              ? CreamPalette.better
              : CreamPalette.ink.withValues(alpha: 0.3),
          height: 9,
          onDark: false,
        ),
      ),
    );

    Widget row(CreatureStat stat) {
      final av = a.statValueAtLevel(stat, _refLevel ?? a.level);
      final bv = b.statValueAtLevel(stat, _refLevel ?? b.level);
      final ag = a.statSlope[stat] ?? 0;
      final bg = b.statSlope[stat] ?? 0;
      final aWins = av > bv;
      final bWins = bv > av;
      // Compared on the shown figure, so the highlight never contradicts the
      // numbers next to it.
      final agWins = ag.toStringAsFixed(1) != bg.toStringAsFixed(1) && ag > bg;
      final bgWins = ag.toStringAsFixed(1) != bg.toStringAsFixed(1) && bg > ag;
      // Value and growth SIDE BY SIDE (user 2026-07-27). Stacked, the two read
      // as one number over another; on one line they read as what they are —
      // two genes of the same stat.
      // Left side reads value-growth-bar, right side bar-growth-value: the
      // big number sits at the OUTER edge next to its own parent's tile.
      Widget value(int v, bool wins) =>
          _geneValue('$v', wins, size: 16, width: _kGeneValueW);
      Widget growth(double g, bool wins) => _geneValue(
        '+${g.toStringAsFixed(1)}',
        wins,
        size: 12,
        width: _kGeneGrowthW,
      );
      return Row(
        children: [
          value(av, aWins),
          growth(ag, agWins),
          // The bar draws the gene the header switch names, and its highlight
          // follows THAT gene's winner — bar and colour must never disagree.
          Expanded(
            child: bar(
              aGenes[stat] ?? 0,
              _barsShowGrowth ? agWins : aWins,
              mirrored: true,
            ),
          ),
          SizedBox(
            width: _kGeneLabelW,
            child: Text(
              stat.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 13).copyWith(color: _pageInkSoft, height: 1),
            ),
          ),
          Expanded(
            child: bar(
              bGenes[stat] ?? 0,
              _barsShowGrowth ? bgWins : bWins,
              mirrored: false,
            ),
          ),
          growth(bg, bgWins),
          value(bv, bWins),
        ],
      );
    }

    // No heading and no caption row (user 2026-07-27; 2026-11-03): the
    // parents stand left and right of it, and the two switches that name the
    // columns live in the foot row. Every row takes an equal share of the
    // height, so the table always fills the space between the tiles instead
    // of being scaled to fit it.
    return Column(
      children: [
        for (final stat in CreatureStat.values) Expanded(child: row(stat)),
      ],
    );
  }

  /// The candidate list for one slot, on the same parchment sheet the worker
  /// picker uses — ranked by GENES, because that is what a parent passes on.
  Future<void> _pickParent(bool first) async {
    final chosenId = first ? _slotAId : _slotBId;
    final otherId = first ? _slotBId : _slotAId;
    final other = _byId(otherId);
    // Sheet-local state (user 2026-07-27): WHICH monster, and by what to
    // order them — two dropdowns instead of a line of prose telling you the
    // order. With a full stable the list is long, and "best genes first" only
    // helps if best means the stat you are breeding FOR.
    String? filterSpeciesId; // null = every species you can breed
    CreatureStat? sortStat; // null = by total genes, the old ranking
    var descending = true; // best first
    // Tapping a candidate only PREVIEWS it here (user 2026-10-05, "Konzept
    // 4") — the detail panel's own button is what actually picks it.
    CreatureInstance? preview;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final all = _candidatesFor(otherId);
          final options = _sortedCandidates(
            otherId,
            filterSpeciesId,
            sortStat,
            descending,
          );
          return Container(
            margin: const EdgeInsets.all(12),
            constraints: const BoxConstraints(maxHeight: 560),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [CreamPalette.paperTop, CreamPalette.paperBottom],
              ),
              borderRadius: vr(16),
              border: Border.all(
                color: CreamPalette.tan.withValues(alpha: 0.6),
              ),
            ),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Which gender is left is a CONSEQUENCE of the other
                        // slot, not a choice you make (user 2026-07-27), so the
                        // title states it instead of asking for it.
                        other == null
                            ? 'Pick a parent'
                            : 'Pick the ${other.gender == CreatureGender.male ? '♀' : '♂'} partner',
                        style: FoE.title(size: 15).copyWith(color: _ink),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _filterPill(
                              all,
                              filterSpeciesId,
                              (v) => setSheet(() => filterSpeciesId = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _sortPill(
                              sortStat,
                              descending,
                              (v) => setSheet(() {
                                // Same pick flips the order, as in the egg
                                // picker; a new field starts best-first.
                                if (v == sortStat) {
                                  descending = !descending;
                                } else {
                                  sortStat = v;
                                  descending = true;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            PickerDetailPanel(
                              placeholder: 'Tap a monster to see its genes.',
                              art: preview == null
                                  ? null
                                  : CreatureCard(
                                      creature: preview!,
                                      showHp: false,
                                      atLevel: _refLevel,
                                    ),
                              title: preview?.displayName,
                              subtitle: preview == null
                                  ? null
                                  : '${preview!.gender.symbol} · Lv ${preview!.level}',
                              rows: preview == null
                                  ? const []
                                  : [
                                      pickerStatRow(
                                        'Genes',
                                        '⚡ ${_geneScore(preview!).round()}',
                                      ),
                                      pickerStatRow(
                                        'Type',
                                        preview!.species?.element.label ?? '—',
                                      ),
                                    ],
                              action: preview == null
                                  ? null
                                  : pickerChooseButton(
                                      label: preview!.id == chosenId
                                          ? 'Already chosen'
                                          : 'Choose this parent',
                                      onTap: preview!.id == chosenId
                                          ? null
                                          : () =>
                                                Navigator.pop(ctx, preview!.id),
                                    ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: options.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        filterSpeciesId == null
                                            ? 'Nobody available.'
                                            : 'None of those available.',
                                        style: FoE.dim(
                                          size: 12,
                                        ).copyWith(color: _inkSoft),
                                      ),
                                    )
                                  // The SAME tiles as the Monsters screen (user
                                  // 2026-07-27), three to a row — so choosing a
                                  // parent looks like browsing the collection,
                                  // not filling a form field. Through
                                  // [monsterTileGrid] now (user 2026-08-31:
                                  // "genau gleich gross sein wie die Kacheln
                                  // beim Monstersscreen"), not this sheet's own
                                  // copy of the sizing maths.
                                  : SingleChildScrollView(
                                      padding: const EdgeInsets.only(
                                        top: 6,
                                        bottom: 6,
                                      ),
                                      child: monsterTileGrid([
                                        for (final c in options)
                                          _candidateTile(
                                            c,
                                            c.id == chosenId,
                                            c.id == preview?.id,
                                            sortStat,
                                            (p) => setSheet(() => preview = p),
                                          ),
                                      ]),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (first) {
        _slotAId = picked;
      } else {
        _slotBId = picked;
      }
      // Swapping to another species — or to the partner's own gender — strands
      // the other slot. Clear it rather than let start() fail on a pair that
      // was never valid.
      final partner = _byId(first ? _slotBId : _slotAId);
      final now = _byId(picked);
      if (partner != null &&
          now != null &&
          (partner.speciesId != now.speciesId ||
              partner.gender == now.gender)) {
        if (first) {
          _slotBId = null;
        } else {
          _slotAId = null;
        }
      }
    });
  }

  /// [_candidatesFor] narrowed to one species and ordered by [sortStat] — or by
  /// the total genes when none is chosen, the old ranking.
  ///
  /// Sorted on the GENE (`statBase`), not the level-scaled stat: the list picks
  /// a parent, and a levelled monster passes on exactly the genes it was born
  /// with.
  List<CreatureInstance> _sortedCandidates(
    String? otherId,
    String? speciesId,
    CreatureStat? sortStat,
    bool descending,
  ) {
    final list = [
      for (final c in _candidatesFor(otherId))
        if (speciesId == null || c.speciesId == speciesId) c,
    ];
    double score(CreatureInstance c) =>
        sortStat == null ? _geneScore(c) : (c.statBase[sortStat] ?? 0);
    list.sort(
      (a, b) => descending
          ? score(b).compareTo(score(a))
          : score(a).compareTo(score(b)),
    );
    return list;
  }

  // ── The picker's controls ─────────────────────────────────────────────
  // The SHARED pills (user 2026-07-27: "alle filter und sortierfunktionien
  // sollen so aussehen wie bei den eggs") — features/common/widgets/
  // filter_pills.dart. They were captioned Material dropdowns here.
  //
  // The sort gained the egg picker's DIRECTION TOGGLE with the look: a pill
  // that shows an arrow it cannot flip would be a lie, and re-picking the
  // current field already had no effect to lose.

  /// WHICH monster (user 2026-07-27): the species present in the list, or all
  /// of them. A name search was the wrong tool — you pick a parent by species
  /// first, and once the partner is chosen this narrows to that one anyway.
  Widget _filterPill(
    List<CreatureInstance> all,
    String? value,
    ValueChanged<String?> onPick,
  ) {
    final ids = <String>{for (final c in all) c.speciesId}.toList()
      ..sort(
        (a, b) =>
            (kSpeciesDefs[a]?.name ?? a).compareTo(kSpeciesDefs[b]?.name ?? b),
      );
    final chosen = ids.contains(value) ? value : null;
    return MenuPill<String>(
      palette: _pills,
      icon: Icons.filter_alt_outlined,
      label: chosen == null
          ? 'All monsters'
          : (kSpeciesDefs[chosen]?.name ?? chosen),
      engaged: chosen != null,
      // '' is the "All" sentinel — see MenuPill: a null value reads as a
      // dismissed menu and could never be chosen.
      value: chosen ?? '',
      entries: [
        const MapEntry('', 'All monsters'),
        for (final id in ids) MapEntry(id, kSpeciesDefs[id]?.name ?? id),
      ],
      onSelected: (v) => onPick(v.isEmpty ? null : v),
    );
  }

  /// Order by any single gene, or by the total. Which stat matters depends
  /// entirely on what you are breeding FOR, so no fixed order can be right for
  /// everyone.
  Widget _sortPill(
    CreatureStat? value,
    bool descending,
    ValueChanged<CreatureStat?> onPick,
  ) => MenuPill<String>(
    palette: _pills,
    icon: Icons.swap_vert,
    label: value?.label ?? 'Total genes',
    engaged: value != null || !descending,
    value: value?.name ?? '',
    entries: [
      const MapEntry('', 'Total genes'),
      for (final s in CreatureStat.values) MapEntry(s.name, s.label),
    ],
    trailing: PixelIcon(
      descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: _accent,
    ),
    selectedTrailing: descending ? '↓' : '↑',
    onSelected: (v) => onPick(v.isEmpty ? null : CreatureStat.values.byName(v)),
  );

  /// One candidate: the Monsters-screen tile, plus the figure the list is
  /// currently ordered by and whether it is the one already in the slot. A
  /// tap only PREVIEWS it via [onPreview] now — [_pickParent]'s detail panel
  /// is what actually chooses it.
  Widget _candidateTile(
    CreatureInstance c,
    bool selected,
    bool previewed,
    CreatureStat? sortStat,
    ValueChanged<CreatureInstance> onPreview,
  ) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => onPreview(c),
    child: pickerPreviewFrame(
      active: previewed,
      child: Column(
        children: [
          Expanded(
            // LayoutBuilder OUTSIDE the Stack: the badges are placed off the
            // tile's own pop-out reserve (17 % of its height), and Positioned
            // only works as a direct child of the Stack.
            child: LayoutBuilder(
              builder: (context, box) {
                final artTop = box.maxHeight * 0.17;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: CreatureCard(
                        creature: c,
                        showHp: false,
                        atLevel: _refLevel,
                      ),
                    ),
                    // No separate gene badge any more: the tile's own ⚡ now
                    // carries the level-1 power, which IS the gene total
                    // this list is ranked by — printing it twice said the
                    // same thing in two different words.
                    if (selected)
                      Positioned(
                        top: artTop + 6,
                        left: 8,
                        child: const PixelIcon(
                          Icons.check_circle,
                          size: 18,
                          color: CreamPalette.better,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // Only the figure the list is SORTED by (user 2026-07-27). The line
          // used to fall back to the Breeding gene, which decides nothing
          // about which parent to pick — the tile's own ⚡ at level 1 already
          // says everything the default order is based on.
          if (sortStat != null) ...[
            const SizedBox(height: 2),
            Text(
              '${sortStat.label} ${(c.statBase[sortStat] ?? 0).round()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FoE.dim(size: 10).copyWith(color: _inkSoft),
            ),
          ],
        ],
      ),
    ),
  );
}
