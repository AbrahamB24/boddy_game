import '../../core/ui/feel.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/scroll_paper.dart'
    show
        kPageShadow,
        kParchmentInk,
        kParchmentLight,
        parchmentButton,
        parchmentButtonInk;
import 'creature_detail_screen.dart';
import 'egg_picker_screen.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/species_balance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creatures_controller.dart';
import 'widgets/egg_card.dart';
import 'widgets/egg_details.dart';
import '../common/widgets/recess_bar.dart';

// ── The Hatchery (user 2026-07-26) ─────────────────────────────────────────
// "Eggs müssen nicht angezeigt werden, da diese ins Inventar (Bag) gehen und
// die Hatchery auch nicht, da dies ein eigenes Gebäude ist."
//
// So the Breeding Hut's page is now only about MAKING an egg, and everything
// after it lives here: the eggs waiting to go in, the ones incubating, and the
// hatch.
//
// BUILT ON THE BREEDING HUT'S PLAN (user 2026-07-27: "designe vom prinzip her
// die hatchery gleich wie breeding hut"). Same two halves, same order: what is
// RUNNING on top with its live countdowns, and the thing you came to DO
// underneath — a slot you fill from a grid of tiles, the values of what you
// picked laid out under it, and one button carrying the price.
//
// It was a flat list of egg rows before. That made the two screens read as
// unrelated features and, worse, hid the only thing that distinguishes one egg
// from another: an egg carries frozen child genes (migration 0027), and a list
// row had nowhere to show them — you committed a Hatchery slot blind.
class HatcheryScreen extends StatefulWidget {
  /// The egg to arrive PRE-SELECTED on, from the Bag's "➜ Incubate" (user
  /// 2026-07-27). The bag used to place the egg itself; now it hands the choice
  /// over and this screen makes the commit — so the egg you tapped is already
  /// in the slot, with its stats on screen.
  final String? selectedEggId;

  const HatcheryScreen({super.key, this.selectedEggId});

  @override
  State<HatcheryScreen> createState() => _HatcheryScreenState();
}

class _HatcheryScreenState extends State<HatcheryScreen> {
  // The same ink-on-parchment the breeding page, the building dialog and the
  // worker sheet wear.
  static const Color _ink = kParchmentInk;
  static final Color _inkSoft = kParchmentInk.withValues(alpha: 0.78);
  static final Color _inkFaint = kParchmentInk.withValues(alpha: 0.55);
  static const Color _accent = FoE.gold;
  static final Color _cardFill = kParchmentInk.withValues(alpha: 0.06);

  /// The Monsters-grid cell shape (crossAxisCount 3, childAspectRatio 0.70) —
  /// the breeding screen's parent slots use the same constant.
  static const double _kTileAspect = 0.70;

  final _breeding = BreedingController();
  final _creatures = CreaturesController();
  Timer? _ticker;
  bool _busy = false;

  /// The egg in the slot. Seeded from the Bag's tap; otherwise filled from the
  /// picker, exactly like a breeding parent slot.
  String? _selectedEggId;

  @override
  void initState() {
    super.initState();
    _selectedEggId = widget.selectedEggId;
    _creatures.load();
    _breeding.load();
    // Live countdowns, and it promotes any finished mating to a collectable
    // egg — the same tick the breeding page runs.
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

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  /// The egg currently in the slot, or null — including when the one that was
  /// there has since left the bag (placed, hatched or discarded elsewhere).
  BreedingJob? get _selectedEgg {
    final id = _selectedEggId;
    if (id == null) return null;
    for (final j in _breeding.eggs) {
      if (j.id == id) return j;
    }
    return null;
  }

  Future<void> _place(BreedingJob job) async {
    setState(() => _busy = true);
    final error = await _breeding.placeInHatchery(job);
    if (!mounted) return;
    setState(() {
      _busy = false;
      // It has left the bag — the slot empties, the way the breeding screen
      // clears its parents once the mating starts.
      if (error == null && _selectedEggId == job.id) _selectedEggId = null;
    });
    context.snack(error ?? '🥚 Egg placed in the Hatchery.');
  }


  /// Every egg whose incubation is done.
  List<BreedingJob> get _hatchable =>
      [for (final j in _breeding.hatchingJobs) if (j.isHatchable) j];

  /// Hatches everything that is ready, in one go.
  ///
  /// Deliberately does NOT open each newborn's screen — that is the single-egg
  /// gesture, where you asked about that egg. Here the point is to clear the
  /// nest, so it reports how many arrived and leaves you where you were.
  Future<void> _hatchAll() async {
    final ready = _hatchable;
    if (ready.isEmpty) return;
    setState(() => _busy = true);
    final names = <String>[];
    var blocked = false;
    for (final job in ready) {
      // Checked per egg, not once: each hatchling takes a slot, so the nest can
      // fill up halfway through.
      if (_creatures.housingFull) {
        blocked = true;
        break;
      }
      final baby = await _breeding.hatch(job);
      if (baby != null) names.add(baby.displayName);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (names.isEmpty) {
      Feel.deny();
      context.snack(blocked
          ? '🏠 Settlement full — build more housing before hatching.'
          : 'Hatching failed.');
      return;
    }
    Feel.fanfare();
    context.snack(
      blocked
          ? '🐣 ${names.length} hatched — then the settlement ran out of room.'
          : '🐣 ${names.length} hatched: ${names.join(', ')}',
    );
  }

  Widget _hatchAllButton() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _busy ? null : _hatchAll,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 11),
      alignment: Alignment.center,
      decoration: parchmentButton(active: !_busy),
      child: Text(
        'Hatch all ${_hatchable.length}',
        style: FoE.label(size: 13).copyWith(
          color: parchmentButtonInk(active: !_busy),
        ),
      ),
    ),
  );

  Future<void> _hatch(BreedingJob job) async {
    // A hatchling needs a housing slot — keep the egg pending if full.
    if (_creatures.housingFull) {
      Feel.deny();
      context.snack('🏠 Settlement full — build more housing before hatching.');
      return;
    }
    setState(() => _busy = true);
    final baby = await _breeding.hatch(job);
    if (!mounted) return;
    setState(() => _busy = false);
    if (baby == null) {
      Feel.deny();
      context.snack('Hatching failed.');
      return;
    }
    Feel.fanfare();
    context.snack('🐣 ${baby.displayName} hatched!');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatureDetailScreen(creatureId: baby.id),
      ),
    );
  }

  Future<void> _discard(BreedingJob job) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kParchmentLight,
        title: Text(
          'Discard this egg?',
          style: FoE.title(size: 15).copyWith(color: _ink),
        ),
        content: Text(
          'It is gone for good — the child inside it is never born.',
          style: FoE.dim(size: 12).copyWith(color: _inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep', style: FoE.label(size: 12).copyWith(color: _ink)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Discard',
              style: FoE.label(size: 12).copyWith(color: FoE.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _breeding.cancel(job);
    if (!mounted) return;
    setState(() {
      if (_selectedEggId == job.id) _selectedEggId = null;
    });
  }

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

  /// What an incubation will ACTUALLY take: the rarity base already cut by the
  /// hatchers posted here — the breeding screen quotes its mating the same way.
  double _hatchHours(SpeciesDef s) => breedingHours(
    kSpeciesBalance.of(s.rarity).hatchHours,
    SettlementController().hatchingPower(kHatcheryBuildingId),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_breeding, _creatures]),
    builder: (context, _) => ParchmentPage(
      title: 'Hatchery',
      trailing: Text(
        '${_breeding.hatchingJobs.length}/${_breeding.hatcherySlots}',
        style: FoE.value(size: 12).copyWith(color: _accent),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          ParchmentPage.kParchmentPagePad,
          12,
          ParchmentPage.kParchmentPagePad,
          20,
        ),
        children: [
          // HATCH THEM ALL (user 2026-07-30). With the Hatchery levelled, four or
          // five eggs come due at once and each one wanted its own tap — plus a
          // detour into the newborn's screen before the next could be opened.
          // Only shown when there is more than one waiting, so it never doubles
          // up with the row's own button.
          if (_hatchable.length > 1) ...[
            _hatchAllButton(),
            const SizedBox(height: 12),
          ],
          // RUNNING FIRST, as on the breeding page.
          ..._phaseSection(
            'Incubating',
            _breeding.hatchingJobs,
            'Nothing incubating.',
          ),
          const SizedBox(height: 18),
          Text('New incubation', style: FoE.title(size: 13).copyWith(color: _ink)),
          const SizedBox(height: 8),
          _newIncubationPanel(),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );

  /// A titled group with its cards, or a dim placeholder line when empty — the
  /// breeding page's own section, so the two stack identically.
  List<Widget> _phaseSection(
    String title,
    List<BreedingJob> jobs,
    String emptyLabel,
  ) => [
    Text(title, style: FoE.title(size: 13).copyWith(color: _ink)),
    const SizedBox(height: 8),
    if (jobs.isEmpty)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Text(emptyLabel, style: FoE.dim(size: 12).copyWith(color: _inkFaint)),
      )
    else
      for (final job in jobs) _jobCard(job),
    const SizedBox(height: 14),
  ];

  /// One running incubation.
  ///
  /// REBUILT 2026-07-27 ("gestalte dies neu, so dass es gut zum Design der App
  /// passt"). It was a flat row — egg, name, a bare countdown, two grey icon
  /// buttons — with a "Ready to hatch!" caption that only appeared at the end.
  /// Four items on one line, none of them showing how far along the thing was.
  ///
  /// Now the card carries a PROGRESS BAR in the species' element colour, the
  /// same bar the gene table and the monster detail screen use. A full bar and
  /// a green button say "ready" without a word for it (user 2026-07-27:
  /// '"ready to hatch" löschen'), and while it runs the bar answers the one
  /// question a countdown alone leaves open — is this nearly done, or barely
  /// started?
  Widget _jobCard(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final ready = job.isReady;
    final barColor = species?.element.color ?? _accent;

    // How far along, as a FRACTION. Estimated against the CURRENT incubation
    // time rather than measured: `startedAt` on the row is when the mating
    // began, not when the egg went into the Hatchery, and an accelerator item
    // moves `readyAt` under it — neither of which the row records. So the bar
    // is honest about the remaining time (which is exact) and approximate
    // about how much came before it.
    final totalMs = species == null
        ? 0.0
        : _hatchHours(species) * 3600000;
    final frac = ready || totalMs <= 0
        ? 1.0
        : (1 - job.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: ShapeDecoration(color: ready ? _accent.withValues(alpha: 0.12) : _cardFill, shape: FoE.facet(radius: 12, side: BorderSide(color: ready ? _accent : kParchmentInk.withValues(alpha: 0.18),
          width: ready ? 1.5 : 1))),
      child: Row(
        children: [
          // THE EGG, not the species sprite (user 2026-07-27). The sprite was a
          // picture of a monster that does not exist yet; the shell with its
          // silhouette is what is actually sitting in the Hatchery.
          SizedBox(width: 52, height: 52, child: EggGlyph(job: job)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        species?.name ?? job.speciesId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(size: 14).copyWith(color: _ink),
                      ),
                    ),
                    // The clock only while there is one — done, the bar and the
                    // button say it.
                    if (!ready)
                      Text(
                        _fmt(job.remaining),
                        style: FoE.value(size: 12).copyWith(color: _inkSoft),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                RecessBar(value: frac, color: barColor, height: 10),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ..._jobActions(job, ready: ready),
        ],
      ),
    );
  }

  List<Widget> _jobActions(BreedingJob job, {required bool ready}) {
    if (ready) {
      return [
        GestureDetector(
          onTap: _busy ? null : () => _hatch(job),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: parchmentButton(),
            // No 🐣 on the button (user 2026-07-27) — the egg on the same row
            // is the picture, and no other button in the app wears an emoji.
            child: Text(
              'Hatch',
              style: FoE.label(size: 13).copyWith(color: parchmentButtonInk()),
            ),
          ),
        ),
      ];
    }
    // Compact round ink buttons rather than Material's 48 px IconButtons: three
    // of those ate half the card's width and pushed the bar into a stub.
    return [
      if (_heldSpeedItems().isNotEmpty)
        _iconAction(
          Icons.bolt,
          'Speed up (item)',
          _accent,
          _busy ? null : () => _useAccelerator(job),
        ),
      if (SettlementController().isDev)
        _iconAction(
          Icons.fast_forward,
          'Finish now (Dev)',
          _accent,
          () => _breeding.devFinishNow(job),
        ),
      // NOT a delete any more (user 2026-07-27) — it puts the egg back in the
      // bag, so it wears an "out" arrow in the accent rather than a red ✕.
      _iconAction(
        Icons.logout,
        'Back to the bag',
        _accent,
        _busy ? null : () => _returnToBag(job),
      ),
    ];
  }

  /// Frees the Hatchery slot and returns the egg to the bag. The incubation's
  /// progress is gone — say so, or it looks like a free pause.
  Future<void> _returnToBag(BreedingJob job) async {
    setState(() => _busy = true);
    final err = await _breeding.returnToBag(job);
    if (!mounted) return;
    setState(() => _busy = false);
    context.snack(
      err ?? 'Egg back in your bag — its incubation starts over next time.',
      error: err != null,
    );
  }

  /// One trailing action on a job card: a 30 px tinted disc. Same shape for
  /// every card, so the row of them reads as a set.
  ///
  /// [Semantics], NOT [Tooltip] (2026-07-27, chasing a stream of
  /// `mouse_tracker.dart` assertions on desktop). A Tooltip registers itself
  /// with the global MouseTracker in initState and unregisters in dispose —
  /// and this row's tooltips come and go on their own: the card rebuilds every
  /// second from the countdown ticker, and the set of actions changes when an
  /// accelerator is used up or the timer finishes. A Tooltip created or
  /// disposed WHILE the tracker is walking its listeners mutates that list
  /// mid-notification, which is what the assert catches.
  ///
  /// Semantics gives screen readers the same label with no MouseTracker
  /// involvement. The cost is the hover text on desktop, which this
  /// touch-first game never depended on.
  Widget _iconAction(
    IconData icon,
    String label,
    Color color,
    VoidCallback? onTap,
  ) => Semantics(
    label: label,
    button: true,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    ),
  );

  // ── The picker half: slot → values → one button ────────────────────────
  // The breeding screen's "New pair" panel with one slot instead of two.

  Widget _newIncubationPanel() {
    final eggs = _breeding.eggs;
    if (eggs.isEmpty) {
      return Text(
        'No eggs in the bag. Mate a pair in the Breeding Hut — the egg they '
        'lay lands there.',
        style: FoE.dim(size: 12).copyWith(color: _inkSoft),
      );
    }

    final job = _selectedEgg;
    final species = job == null ? null : kSpeciesDefs[job.speciesId];
    final free = _breeding.freeHatcherySlots > 0;
    final noHatchery = _breeding.hatcherySlots <= 0;
    final canPlace = job != null && free && !_busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THE EGG IN THE MIDDLE (user 2026-07-27: "Das Ei mit Energie und Name
        // zentrieren"). It sat in the left half with a caption in the right,
        // which put the one object this panel is about off to one side and
        // printed its name twice — the tile already carries the name and the ⚡.
        //
        // Half width, not full: a lone tile stretched across the page would
        // read as a banner, not as a card you picked out of a grid.
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.46,
            child: _eggSlot(job),
          ),
        ),
        if (job != null) ...[
          const SizedBox(height: 12),
          // WHERE IT CAME FROM AND WHEN (user 2026-07-27: "Parents anzeigen und
          // wann das Ei gelegt wurde"). The genes below say what is inside; the
          // parents say which pair produced it, which is the only way to tell
          // two eggs of one species apart before reading fourteen numbers.
          EggFacts(job: job),
          const SizedBox(height: 12),
          EggGeneTable(job: job),
        ],
        // NO BUTTON WITHOUT AN EGG (user 2026-07-27). It used to render greyed
        // out reading "Pick an egg" — an action offered for a thing not chosen
        // yet, saying what the empty card above it already says.
        if (job != null) ...[
          const SizedBox(height: 16),
          _hatchButton(
            job,
            species,
            canPlace: canPlace,
            free: free,
            noHatchery: noHatchery,
          ),
          // The two SECONDARY moves, side by side under the action that
          // commits (user 2026-07-27: "der Button soll unten bei hatch sein").
          // "Choose another" sat under the egg, halfway up the panel — so the
          // one control that changes what everything below it describes was
          // read before any of it. At the foot it is where you land after
          // deciding this egg is not the one.
          //
          // Discarding lived on every egg row before; with the rows gone it
          // belongs to the egg you are looking at, and behind a confirmation —
          // it destroys a child that can never be bred again from dead parents.
          const SizedBox(height: 10),
          _secondaryRow(job, hasOtherEggs: eggs.length > 1),
        ],
      ],
    );
  }

  /// The filled slot (the egg tile) or an empty frame inviting the picker —
  /// tapping either always reopens the grid, so swapping is one tap.
  Widget _eggSlot(BreedingJob? job) => AspectRatio(
    aspectRatio: _kTileAspect,
    child: job == null
        ? _emptySlot()
        : EggCard(job: job, onTap: _pickEgg),
  );

  /// An unfilled slot, in the BUILD MENU'S dead-card style — the same frame the
  /// breeding screen's empty parent slot uses.
  Widget _emptySlot() => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: _pickEgg,
    child: LayoutBuilder(
      // The tile reserves its top 17 % for the art that pops out of it; the
      // empty card leaves the same gap so the row lines up.
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: box.maxHeight * 0.17),
        child: Container(
          decoration: ShapeDecoration(color: kParchmentInk.withValues(alpha: 0.10),
            
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
              Text('Choose', style: FoE.label(size: 12).copyWith(color: _inkFaint)),
            ],
          ),
        ),
      ),
    ),
  );

  /// THE COMMIT: the flat [parchmentButton] green every other page wears, with
  /// the wait INSIDE it — exactly as the mating's cost and duration sit on the
  /// breeding page's own button.
  ///
  /// A raised version of this (top-lit gradient, a solid ledge under it, the
  /// duration lifted into a chip on the right) was tried and REJECTED (user
  /// 2026-07-27: "den hatchbutton wieder so wie vorher"). The two ghost pills
  /// below it are the redesign that stayed. Do not re-embellish it: it matches
  /// the Breed button, and the pair have to look like one button in two places.
  Widget _hatchButton(
    BreedingJob job,
    SpeciesDef? species, {
    required bool canPlace,
    required bool free,
    required bool noHatchery,
  }) {
    // A greyed button that repeats its own label says it is off but not WHY —
    // name what is missing instead.
    final label = noHatchery
        ? 'This Hatchery has no incubation slots'
        : !free
        ? 'Hatchery full — free a slot'
        : 'Hatch';
    final ink = parchmentButtonInk(active: canPlace);

    return GestureDetector(
      onTap: canPlace ? () => _place(job) : null,
      child: Opacity(
        opacity: canPlace ? 1 : 0.5,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: parchmentButton(active: canPlace),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // "Hatch", and no glyphs on either line (user 2026-07-27: "Button
              // unten heisst hatch ohne Icons") — the ➜ and the ⏱ are gone;
              // "18h" on the sub-line is already read as a duration.
              Text(label, style: FoE.label(size: 13).copyWith(color: ink)),
              if (species != null && free) ...[
                const SizedBox(height: 3),
                Text(
                  '${_hatchHours(species).round()}h',
                  style: FoE.dim(size: 10).copyWith(color: ink),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The two secondary moves under it, REDESIGNED as a MATCHED PAIR (user
  /// 2026-07-27).
  ///
  /// They were an outlined pill on the left and a bare Material TextButton on
  /// the right, pushed apart by a Spacer — two different shapes, two different
  /// heights, at two different distances from the edge. Now they share one
  /// height, one radius and one row, so the foot of the panel reads as a set
  /// rather than as two leftovers.
  ///
  /// Both stay GHOSTS: the green above is the action that commits a Hatchery
  /// slot, and neither of these may compete with it. Discard keeps the danger
  /// ink and gets the fainter outline of the two — it destroys a child that can
  /// never be bred again from dead parents, so it must be findable but never
  /// inviting.
  ///
  /// "Choose another" only appears when there IS another (`hasOtherEggs`);
  /// alone, Discard shrinks to its own width rather than stretching a
  /// destructive action across the page.
  Widget _secondaryRow(BreedingJob job, {required bool hasOtherEggs}) {
    final discard = _ghostPill(
      // Words only (user 2026-07-27: "ohne icon") — the outline already says it
      // is a control, so a glyph would be decoration.
      'Discard egg',
      FoE.danger,
      _busy ? null : () => _discard(job),
      borderAlpha: 0.30,
    );
    if (!hasOtherEggs) return Center(child: discard);
    return Row(
      children: [
        Expanded(
          child: _ghostPill('Choose another egg', _accent, _pickEgg),
        ),
        const SizedBox(width: 10),
        Expanded(child: discard),
      ],
    );
  }

  /// One outlined secondary control: 38 px tall, faintly tinted, in [color].
  Widget _ghostPill(
    String label,
    Color color,
    VoidCallback? onTap, {
    double borderAlpha = 0.50,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: color.withValues(alpha: 0.07), shape: FoE.facet(radius: 12, side: BorderSide(color: color.withValues(alpha: borderAlpha)))),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FoE.label(size: 12).copyWith(color: color),
      ),
    ),
  );

  /// Opens the egg picker AS A SCREEN (user 2026-07-27: "Das Eimen� soll kein
  /// pop up sein, sondern ein eigener screen, dann gibt es mehr Platz") and
  /// takes the egg it comes back with. Backing out changes nothing.
  Future<void> _pickEgg() async {
    final picked = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => EggPickerScreen(selectedEggId: _selectedEggId),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedEggId = picked);
  }
}
