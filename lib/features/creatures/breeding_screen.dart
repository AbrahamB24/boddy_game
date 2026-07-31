import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../common/widgets/filter_pills.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/widgets/meander_strip.dart';
import '../settlement/widgets/scroll_paper.dart'
    show
        kPageShadow,
        kParchmentInk,
        kParchmentLight,
        kParchmentMid,
        parchmentButton,
        parchmentButtonInk;
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
import '../common/widgets/recess_bar.dart';

// The Breeding Hut: MATING, and nothing after it (user 2026-07-26 — "Eggs
// müssen nicht angezeigt werden … und die Hatchery auch nicht, da dies ein
// eigenes Gebäude ist"). Top: the matings running, with live countdowns.
// Bottom: pick the two parents and start the timer.
//
// Picking is a COMPARISON, not a form: you choose a monster (its species picks
// the partner's list for you) and the panel lays the two sets of genes side by
// side, because that — plus the odds the better gene wins — is the whole
// decision. Eggs, incubation and hatching live on the Hatchery screen.
class BreedingScreen extends StatefulWidget {
  const BreedingScreen({super.key});

  @override
  State<BreedingScreen> createState() => _BreedingScreenState();
}

class _BreedingScreenState extends State<BreedingScreen> {
  // ── Ink on parchment (user 2026-07-26: "gestalte das Breeding menü neu
  // und den anderen Menüs entsprechend") ──
  // The build menu, the building dialog, the worker sheet and the upgrade
  // preview all share one surface; this page was the last dark screen among
  // them, and it is reached from the same building.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _ornament = kParchmentInk.withValues(alpha: 0.22);
  static final Color _cardFill = kParchmentInk.withValues(alpha: 0.06);

  /// This page is parchment, so its pills are.
  static final PillPalette _pills = PillPalette.parchment;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kParchmentMid,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kParchmentLight, kParchmentMid],
          ),
        ),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([_breeding, _creatures]),
            builder: (context, _) => Column(
              children: [
                _topBar(),
                Expanded(
                  child: Stack(
                    children: [
                      // The meander bands, as on every other parchment surface.
                      // Wallpaper first, so they never land over a card.
                      Positioned(
                        left: 4,
                        top: 0,
                        bottom: 0,
                        width: 14,
                        child: MeanderStrip(color: _ornament),
                      ),
                      Positioned(
                        right: 4,
                        top: 0,
                        bottom: 0,
                        width: 14,
                        child: MeanderStrip(color: _ornament, flip: true),
                      ),
                      ListView(
                        // Wide sides: the bands live in that margin.
                        padding: const EdgeInsets.fromLTRB(28, 14, 28, 14),
                        children: [
                          // ONLY the matings (user 2026-07-26). A laid egg goes
                          // to the Bag and incubating happens in the Hatchery —
                          // its own building — so neither has a section here.
                          ..._phaseSection(
                            'Mating',
                            _breeding.matingJobs,
                            'No pair mating.',
                            slotLabel:
                                '${_breeding.matingJobs.length}/${_breeding.breedingSlots}',
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'New pair',
                            style: FoE.title(size: 13).copyWith(color: _ink),
                          ),
                          const SizedBox(height: 8),
                          _newPairPanel(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// THE bar (user 2026-07-31: "überall wo es einen header hat, soll dieser
  /// immer genau gleich aussehen"). It used to be a hand-built 48-px box in the
  /// scroll's deepest parchment — the same INTENT as the shared band, four
  /// values apart from it.
  ///
  /// No "n active" (user 2026-07-27): the Mating section right below counts its
  /// own jobs against the hut's slots.
  Widget _topBar() => const ParchmentHeader(title: 'Breeding');

  /// A titled group (breeding / eggs / hatchery) with its cards, or a dim
  /// placeholder line when empty. Returns the slivers to splice into the list.
  List<Widget> _phaseSection(
    String title,
    List<BreedingJob> jobs,
    String emptyLabel, {
    String? slotLabel,
  }) => [
    Row(
      children: [
        Text(title, style: FoE.title(size: 13).copyWith(color: _ink)),
        const Spacer(),
        // Bare, like every other readout on this paper: a boxed or gilded
        // number reads as a button.
        if (slotLabel != null)
          Text(slotLabel, style: FoE.value(size: 12).copyWith(color: _accent)),
      ],
    ),
    const SizedBox(height: 8),
    if (jobs.isEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          emptyLabel,
          style: FoE.dim(size: 12).copyWith(color: _inkFaint),
        ),
      )
    else
      for (final job in jobs) _jobCard(job),
    const SizedBox(height: 14),
  ];

  /// One running MATING. The egg it will lay, and everything after, belongs to
  /// the Hatchery screen — this page ends when the timer does.
  Widget _jobCard(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final a = _byId(job.parentAId);
    final b = _byId(job.parentBId);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(color: _cardFill, shape: FoE.facet(radius: 10, side: BorderSide(color: kParchmentInk.withValues(alpha: 0.18)))),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: species?.stageAt(0).imageUrl == null
                ? Icon(Icons.pets, color: _accent, size: 26)
                : CreatureSprite(
                    url: species!.stageAt(0).imageUrl!,
                    fallback: Icon(Icons.pets, color: _accent, size: 26),
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
          icon: Icon(Icons.bolt, color: _accent, size: 18),
          onPressed: _busy ? null : () => _useAccelerator(job),
        ),
      ),
    if (SettlementController().isDev)
      Semantics(
        label: 'Finish now (Dev)',
        button: true,
        child: IconButton(
          icon: Icon(Icons.fast_forward, color: _accent, size: 18),
          onPressed: () => _breeding.devFinishNow(job),
        ),
      ),
    Semantics(
      label: 'Cancel',
      button: true,
      child: IconButton(
        icon: const Icon(Icons.close, color: FoE.danger, size: 18),
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

  Widget _newPairPanel() {
    final a = _byId(_slotAId);
    final b = _byId(_slotBId);
    final species = kSpeciesDefs[_pairSpeciesId];
    // A mating COSTS SUPPLIES (user 2026-07-27), in the goods of the era the
    // PARENTS come from — so the price is quoted with the pair, not with the
    // settlement.
    final stock = SettlementController().resources?.asMap ?? const {};
    final cost = a == null || b == null
        ? const <String, double>{}
        : breedCost(a, b, stock);
    final affordable = canAffordBreed(cost, stock);
    final canStart = a != null && b != null && affordable && !_busy;

    if (_candidatesFor(null).isEmpty) {
      return Text(
        'You need an available male AND female of the same species '
        '(not K.O., not already breeding).',
        style: FoE.dim(size: 12).copyWith(color: _inkSoft),
      );
    }

    // No frame around it (user 2026-07-27): the two tiles, the table and the
    // button are already one block, and a recess around them only competed
    // with the tiles' own shapes.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The two slots ARE the picker (user 2026-07-26). The species
        // dropdown is gone: you choose a monster, and its species narrows the
        // other slot — the order you actually think in.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _parentSlot(first: true, c: a)),
            const SizedBox(width: 10),
            Expanded(child: _parentSlot(first: false, c: b)),
          ],
        ),
        if (a != null && b != null) ...[
          const SizedBox(height: 14),
          _geneTable(a, b),
        ],
        // NO BUTTON WITH BOTH SLOTS EMPTY (user 2026-07-27: "pick both parents
        // kann gelöscht werden") — the same rule the Hatchery's panel follows.
        // A greyed button reading "Pick both parents" was an action offered for
        // a thing not chosen yet, saying what the two empty cards above it
        // already say. From the first parent on it comes back, because then it
        // names what is still MISSING rather than restating the invitation.
        if (a != null || b != null) ...[
          const SizedBox(height: 14),
          // The price lives INSIDE the button, built exactly like Upgrade (user
          // 2026-07-27): the same parchment face, the label on top, the cost
          // and the duration on the sub-line — red when the store cannot cover
          // it. The price is part of the offer, not a caption above it.
          GestureDetector(
            onTap: canStart ? _start : null,
            child: Opacity(
              opacity: canStart ? 1 : 0.5,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: parchmentButton(active: canStart),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A greyed button that repeats its own label says it is off
                    // but not WHY. Name the missing half instead.
                    Text(
                      a == null || b == null
                          ? 'Pick the partner'
                          // "Breed" (user 2026-07-27) — one word, like Hatch on
                          // the Hatchery's button.
                          : 'Breed',
                      style: FoE.label(
                        size: 13,
                      ).copyWith(color: parchmentButtonInk(active: canStart)),
                    ),
                    if (cost.isNotEmpty && species != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${breedCostLabel(cost)}   '
                        '⏱ ${_matingHours(species).round()}h',
                        textAlign: TextAlign.center,
                        style: FoE.dim(size: 10).copyWith(
                          color: affordable
                              ? parchmentButtonInk(active: canStart)
                              : FoE.danger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
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
  Widget _parentSlot({required bool first, required CreatureInstance? c}) =>
      AspectRatio(
        // The Monsters grid's own cell shape, so the tile is the exact tile.
        aspectRatio: _kTileAspect,
        child: c == null
            ? _emptySlot(first)
            : CreatureCard(
                creature: c,
                onTap: () => _pickParent(first),
                // No XP arc and no HP bar here (user 2026-07-27): a parent is
                // picked on its genes, not on its level progress or wounds.
                showXp: false,
                showHp: false,
                // The current power big, the level-1 one (its genes) small
                // under it.
                showLevelOnePower: true,
              ),
      );

  /// The Monsters-grid cell shape (crossAxisCount 3, childAspectRatio 0.70).
  static const double _kTileAspect = 0.70;

  /// An unfilled parent slot, in the BUILD MENU'S dead-card style (user
  /// 2026-07-27: "Nimm für die Kacheln die Kacheln der Gebäude, welche nicht
  /// gebaut werden können vom Stil") — a faded ink fill with the soft brown
  /// shadow that makes it lie ON the paper, and no outline. An empty slot and
  /// an unaffordable building are the same thing: a card with nothing in it
  /// yet.
  Widget _emptySlot(bool first) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _pickParent(first),
    child: LayoutBuilder(
      // The tile reserves its top 17 % for the art that pops out of it; the
      // empty card leaves the same gap so both halves of the row line up.
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: box.maxHeight * 0.17),
        child: Container(
          decoration: ShapeDecoration(// The build menu's own _cardInactive / shadow, to the value.
            color: kParchmentInk.withValues(alpha: 0.10),
            
            shadows: [
              BoxShadow(
                color: kPageShadow.withValues(alpha: 0.24),
                blurRadius: 0,
                offset: const Offset(0, 3),
              ),
            ], shape: FoE.facet(radius: 22)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_circle_outline, size: 26, color: _inkFaint),
              const SizedBox(height: 6),
              Text(
                'Choose',
                style: FoE.label(size: 12).copyWith(color: _inkFaint),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  /// The gene table's column captions, over BOTH parents' columns: "lvl 1" over
  /// the stat and [Icons.upgrade] — the same glyph the monster detail screen
  /// puts over its growth column — over the per-level gain (user 2026-07-27).
  ///
  /// Built from the same fixed widths as the value cells, so each caption sits
  /// exactly over the number it names.
  /// THE CAPTIONS ARE THE CONTROL (user 2026-07-27) — they name the two number
  /// columns and pick which of them the bars draw. One switch for the whole
  /// table, centred between the two parents' columns: two of them, one per
  /// side, would look like two independent settings.
  Widget _geneHeaderRow() => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        const Spacer(),
        GeneBarToggle(
          showGrowth: _barsShowGrowth,
          onChanged: (v) => setState(() => _barsShowGrowth = v),
          ink: _ink,
          inkFaint: _inkFaint,
          accent: _accent,
        ),
        const Spacer(),
      ],
    ),
  );

  // The gene table's fixed column widths, shared by the header and the rows so
  // every caption sits over the number it names.
  static const double _kGeneValueW = 28;
  static const double _kGeneGrowthW = 26;
  static const double _kGeneLabelW = 74;

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
      style: (size >= 12 ? FoE.value(size: size) : FoE.dim(size: size))
          .copyWith(
            color: better ? FoE.positive : _inkFaint,
            fontWeight: better ? FontWeight.w800 : FontWeight.w400,
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
    final favored = breedingFavoredChance();

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
    final aGenes = _barsShowGrowth ? a.statSlope : a.statBase;
    final bGenes = _barsShowGrowth ? b.statSlope : b.statBase;
    final maxVal = CreatureStat.values.fold<double>(0.001, (m, s) {
      final av = aGenes[s] ?? 0;
      final bv = bGenes[s] ?? 0;
      return math.max(m, math.max(av, bv));
    });

    /// One side's bar. [mirrored] grows it leftwards, out of the centre.
    Widget bar(double value, bool wins, {required bool mirrored}) => Padding(
      // Sits with the number's baseline rather than at the top of the row.
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Directionality(
        textDirection: mirrored ? TextDirection.rtl : TextDirection.ltr,
        child: RecessBar(
          value: (value / maxVal).clamp(0.0, 1.0),
          // The winner's bar is the SAME green as its number, so colour and
          // length agree instead of being two separate readings.
          color: wins ? FoE.positive : kParchmentInk.withValues(alpha: 0.40),
          height: 9,
        ),
      ),
    );

    Widget row(CreatureStat stat) {
      final av = (a.statBase[stat] ?? 0).round();
      final bv = (b.statBase[stat] ?? 0).round();
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
      Widget cell(int v, double growth, bool wins, bool growthWins) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _geneValue('$v', wins, size: 12, width: _kGeneValueW),
          _geneValue(
            '+${growth.toStringAsFixed(1)}',
            growthWins,
            size: 9,
            width: _kGeneGrowthW,
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            cell(av, ag, aWins, agWins),
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
                style: FoE.dim(size: 10).copyWith(color: _inkSoft),
              ),
            ),
            Expanded(
              child: bar(
                bGenes[stat] ?? 0,
                _barsShowGrowth ? bgWins : bWins,
                mirrored: false,
              ),
            ),
            cell(bv, bg, bWins, bgWins),
          ],
        ),
      );
    }

    return Column(
      children: [
        // No heading (user 2026-07-27): the two parent tiles above it already
        // say what the table is. The columns caption THEMSELVES instead — "lvl
        // 1" over the value and the detail screen's own level-up icon over the
        // growth, so the two figures are named where they stand.
        _geneHeaderRow(),
        for (final stat in CreatureStat.values) row(stat),
        const SizedBox(height: 8),
        // ONLY the odds (user 2026-07-27): what the highlight is worth and the
        // fact that every gene — value and growth alike — is rolled on its own.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: ShapeDecoration(color: _accent.withValues(alpha: 0.12), shape: FoE.facet(radius: 8)),
          child: Text(
            'Every single stat has a ${(favored * 100).round()} % chance to '
            'inherit the better stat of its parents.',
            style: FoE.dim(size: 11).copyWith(color: _ink),
          ),
        ),
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
            decoration: ShapeDecoration(
              color: kParchmentLight,
              shape: FoE.facet(radius: 16),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 12,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: MeanderStrip(color: _ornament),
                ),
                Positioned(
                  right: 12,
                  top: 0,
                  bottom: 0,
                  width: 14,
                  child: MeanderStrip(color: _ornament, flip: true),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(34, 16, 34, 16),
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
                      Flexible(
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
                            // 2026-07-27), three to a row — so choosing a parent
                            // looks like browsing the collection, not filling a
                            // form field.
                            : GridView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.only(
                                  top: 6,
                                  bottom: 6,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 10,
                                      // Taller than the Monsters grid's 0.70 by the
                                      // caption underneath each tile.
                                      childAspectRatio: 0.60,
                                    ),
                                itemCount: options.length,
                                itemBuilder: (_, i) => _candidateTile(
                                  options[i],
                                  options[i].id == chosenId,
                                  sortStat,
                                  ctx,
                                ),
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
    trailing: Icon(
      descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: _accent,
    ),
    selectedTrailing: descending ? '↓' : '↑',
    onSelected: (v) =>
        onPick(v.isEmpty ? null : CreatureStat.values.byName(v)),
  );

  /// One candidate: the Monsters-screen tile, plus the figure the list is
  /// currently ordered by and whether it is the one already in the slot.
  Widget _candidateTile(
    CreatureInstance c,
    bool selected,
    CreatureStat? sortStat,
    BuildContext ctx,
  ) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => Navigator.pop(ctx, c.id),
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
                      showXp: false,
                      showHp: false,
                      showLevelOnePower: true,
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
                      child: const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: FoE.positive,
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
  );
}
