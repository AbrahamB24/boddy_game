import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/settlement_controller.dart';
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'breeding_screen.dart';
import 'creature_detail_screen.dart';
import 'egg_detail_screen.dart';
import 'egg_picker_screen.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/species_balance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creature_power.dart';
import 'services/creatures_controller.dart';
import 'widgets/egg_card.dart';
import 'widgets/slot_kit.dart';
import '../../core/theme/voxel_icons.dart';

/// The two halves of the page (user 2026-09-20: "hatchery und breeding sollten
/// zusammen sein wie worker und population"): making an egg, and incubating it.
enum NurseryTab { breeding, hatchery }

/// BREEDING & HATCHERY — one page with two tabs, the way Work and Housing are.
///
/// Both buildings open it: the Breeding Hut on its Breeding tab, the Hatchery on
/// its own, and an egg from the Bag (with [selectedEggId]) lands on the Hatchery
/// tab with that egg's tile highlighted.
///
///  • **Breeding** — the matings running, and the new pair (two parents, the gene
///    comparison, the button). See [BreedingPane].
///  • **Hatchery** ("Variante 2, Slot-Karten") — the incubators on top as big
///    cards (the egg, a bar, the time left; a gold Hatch when it is ready), free
///    ones dashed; under them every egg in the bag as a tile with an Incubate
///    button, and a tap on the tile shows its genes.
///
/// The tabs sit in the title card (they are small), so the body keeps its height.
class HatcheryScreen extends StatefulWidget {
  /// The egg to arrive PRE-SELECTED on, from the Bag's "➜ Incubate" (user
  /// 2026-07-27): its tile is highlighted so the Incubate button is one tap away.
  final String? selectedEggId;

  /// Which half opens first.
  final NurseryTab startOn;

  const HatcheryScreen({
    super.key,
    this.selectedEggId,
    this.startOn = NurseryTab.hatchery,
  });

  @override
  State<HatcheryScreen> createState() => _HatcheryScreenState();
}

class _HatcheryScreenState extends State<HatcheryScreen> {
  final _breeding = BreedingController();
  late NurseryTab _tab = widget.startOn;

  @override
  void initState() {
    super.initState();
    _breeding.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _breeding,
    builder: (context, _) => MenuScaffold(
      title: 'Breeding & Hatchery',
      // The switch used to be two small buttons squeezed into the title bar's
      // trailing corner, each naming its OWN building in a font too small to
      // read as the real way between two screens (user 2026-09-28: "Buttons
      // müssen schöner und besser platziert werden … Titel hat jeweils nur das
      // eine oder andere Gebäude als Name"). Now it is the first thing in the
      // body: two full-width, equal segments, each its building's own name.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabSwitcher(),
          const SizedBox(height: 10),
          Expanded(
            child: _tab == NurseryTab.breeding
                ? const BreedingPane()
                : HatcheryPane(selectedEggId: widget.selectedEggId),
          ),
        ],
      ),
    ),
  );

  Widget _tabSwitcher() {
    final ready = _breeding.hatchingJobs.where((j) => j.isHatchable).length;
    Widget seg(NurseryTab t, String emoji, String name, String sub) {
      final on = _tab == t;
      return Expanded(
        child: Pressable(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _tab = t),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: on ? goldButton() : raisedTile(radius: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(emoji, style: const TextStyle(fontSize: 19)),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: kBoxInk,
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: kBoxInkSoft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(
          NurseryTab.breeding,
          '💞',
          'Breeding Hut',
          '${_breeding.matingJobs.length}/${_breeding.breedingSlots} mating',
        ),
        const SizedBox(width: 10),
        seg(
          NurseryTab.hatchery,
          '🥚',
          'Hatchery',
          ready > 0
              ? '$ready ready'
              : '${_breeding.hatchingJobs.length}/${_breeding.hatcherySlots} incubating',
        ),
      ],
    );
  }
}

/// The Hatchery half (see [HatcheryScreen]).
class HatcheryPane extends StatefulWidget {
  final String? selectedEggId;

  const HatcheryPane({super.key, this.selectedEggId});

  @override
  State<HatcheryPane> createState() => _HatcheryPaneState();
}

class _HatcheryPaneState extends State<HatcheryPane> {
  final _breeding = BreedingController();
  final _creatures = CreaturesController();
  Timer? _ticker;
  bool _busy = false;

  /// The egg whose tile is lit — from the Bag's tap, or the one just looked at.
  String? _selectedEggId;

  @override
  void initState() {
    super.initState();
    _selectedEggId = widget.selectedEggId;
    _creatures.load();
    _breeding.load();
    // Live countdowns, and it promotes any finished mating to a collectable egg —
    // the same tick the breeding half runs.
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

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  /// What an incubation will ACTUALLY take: the rarity base already cut by the
  /// hatchers posted here — the breeding half quotes its mating the same way.
  double _hatchHours(SpeciesDef s) => breedingHours(
    kSpeciesBalance.of(s.rarity).hatchHours,
    SettlementController().hatchingPower(kHatcheryBuildingId),
  );

  /// Every egg whose incubation is done.
  List<BreedingJob> get _hatchable => [
    for (final j in _breeding.hatchingJobs)
      if (j.isHatchable) j,
  ];

  /// breedSpeed items currently in the bag (id → count).
  List<MapEntry<String, int>> _heldSpeedItems() => [
    for (final e in SettlementController().items.entries)
      if (kItemDefs[e.key]?.kind == ItemKind.breedSpeed) e,
  ];

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _place(BreedingJob job) async {
    setState(() => _busy = true);
    final error = await _breeding.placeInHatchery(job);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null && _selectedEggId == job.id) _selectedEggId = null;
    });
    context.snack(
      error ?? '🥚 Egg placed in the Hatchery.',
      error: error != null,
    );
  }

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
      context.snack(
        blocked
            ? '🏠 Settlement full — build more housing before hatching.'
            : 'Hatching failed.',
      );
      return;
    }
    Feel.fanfare();
    context.snack(
      blocked
          ? '🐣 ${names.length} hatched — then the settlement ran out of room.'
          : '🐣 ${names.length} hatched: ${names.join(', ')}',
    );
  }

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

  Future<void> _useAccelerator(BreedingJob job) async {
    final held = _heldSpeedItems();
    if (held.isEmpty) return;
    setState(() => _busy = true);
    final err = await _breeding.useSpeedItem(job, held.first.key);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) context.snack(err);
  }

  /// Frees the incubator and returns the egg to the bag. The incubation's
  /// progress is gone — say so, or it looks like a free pause.
  Future<void> _returnToBag(BreedingJob job) async {
    final ok = await confirmDialog(
      context,
      title: 'Take the egg out?',
      body: 'It goes back to your bag — its incubation starts over next time.',
      confirmLabel: 'Take it out',
      cancelLabel: 'Keep it in',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final err = await _breeding.returnToBag(job);
    if (!mounted) return;
    setState(() => _busy = false);
    context.snack(
      err ?? 'Egg back in your bag — its incubation starts over next time.',
      error: err != null,
    );
  }

  /// The free incubator: pick an egg from the bag AS A SCREEN (search, sort by
  /// gene value, filter by species) and put it straight in.
  Future<void> _pickEgg() async {
    final picked = await pushMenu<String>(
      context,
      EggPickerScreen(selectedEggId: _selectedEggId),
    );
    if (picked == null || !mounted) return;
    for (final j in _breeding.eggs) {
      if (j.id == picked) {
        await _place(j);
        return;
      }
    }
  }

  /// A tap on a tile: the egg in full — parents, when it was laid, all its
  /// genes — with the Incubate button at the end of it.
  Future<void> _openEgg(BreedingJob job) async {
    setState(() => _selectedEggId = job.id);
    final go = await pushMenu<String>(
      context,
      EggDetailScreen(eggId: job.id, returnChoice: true),
    );
    if (go == null || !mounted) return;
    for (final j in _breeding.eggs) {
      if (j.id == go) {
        await _place(j);
        return;
      }
    }
  }

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_breeding, _creatures]),
    builder: (context, _) {
      final hatching = _breeding.hatchingJobs;
      final eggs = _breeding.eggs;
      final noHatchery = _breeding.hatcherySlots <= 0;
      final free = _breeding.freeHatcherySlots;
      final ready = _hatchable;
      return SlotFamilyLayout(
        slots: [
          for (final job in hatching) _incubator(job),
          if (noHatchery)
            const FreeSlotCard(label: 'No incubator — build a Hatchery')
          else
            for (var i = 0; i < free; i++)
              FreeSlotCard(
                label: 'Free incubator',
                onTap: eggs.isEmpty || _busy ? null : _pickEgg,
              ),
        ],
        line: _ready(ready),
        tilesTitle: 'Eggs in the bag · ${eggs.length}',
        tilesTrailing: eggs.isEmpty
            ? null
            : Text(
                'Tap an egg for its genes',
                style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
              ),
        tiles: [for (final job in eggs) _eggTile(job, free, noHatchery)],
        whenNoTiles: slotEmptyNote(
          'No eggs in the bag.',
          'Mate a pair on the Breeding tab — the egg they lay lands here.',
        ),
      );
    },
  );

  /// One running incubation: the egg, a bar in its element's colour, the time
  /// left — and a gold Hatch when it is done.
  Widget _incubator(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final ready = job.isReady;
    final totalMs = species == null ? 0.0 : _hatchHours(species) * 3600000;
    // How far along, as a FRACTION. Estimated against the CURRENT incubation time
    // rather than measured: `startedAt` on the row is when the mating began, not
    // when the egg went in, and an accelerator item moves `readyAt` under it. So
    // the bar is honest about the remaining time (exact) and approximate about
    // how much came before it.
    final frac = ready || totalMs <= 0
        ? 1.0
        : (1 - job.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
    return SlotCard(
      avatar: SizedBox(width: 40, height: 50, child: EggGlyph(job: job)),
      name: species?.name ?? job.speciesId,
      sub: job.hasChildGenes ? '⚡ ${genePower(job.childBase)}' : '⚡ ?',
      progress: frac,
      barColor: species?.element.color,
      ready: ready,
      time: ready ? 'ready' : _fmt(job.remaining),
      // A full settlement used to answer the tap with a bare buzz — the
      // message that explained it was a silenced snack. Say it on the button
      // instead, the way the egg tiles below already do.
      action: ready
          ? SlotPill(
              _creatures.housingFull ? 'House full' : 'Hatch',
              gold: !_creatures.housingFull,
              onTap: _busy || _creatures.housingFull ? null : () => _hatch(job),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_heldSpeedItems().isNotEmpty)
                  _iconAction(
                    Icons.bolt,
                    'Speed up (item)',
                    _busy ? null : () => _useAccelerator(job),
                  ),
                // NOT a delete — it puts the egg back in the bag, so it wears
                // an "out" arrow rather than a red ✕.
                _iconAction(
                  Icons.logout,
                  'Back to the bag',
                  _busy ? null : () => _returnToBag(job),
                ),
              ],
            ),
    );
  }

  /// A small round action inside a card. [Semantics], not [Tooltip]: this row's
  /// actions come and go every second with the countdown, and a Tooltip created
  /// or disposed while the mouse tracker is walking its listeners trips an
  /// assertion on desktop.
  Widget _iconAction(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        label: label,
        button: true,
        child: Pressable(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 26,
            height: 24,
            margin: const EdgeInsets.only(left: 4),
            decoration: raisedTile(radius: 9),
            child: PixelIcon(icon, size: 14, color: kBoxInk),
          ),
        ),
      );

  /// The block beside the incubators: how many are done, and Hatch all.
  Widget _ready(List<BreedingJob> ready) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      slotLineHeading('Ready to hatch', '${ready.length}'),
      Text(
        ready.isEmpty
            ? 'Nothing is ready yet. Every incubation runs by itself; the egg '
                  'leaves the bag when it goes in.'
            : ready.length == 1
            ? 'One egg is ready.'
            : '${ready.length} eggs are ready.',
        style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
      ),
      const Spacer(),
      // HATCH THEM ALL (user 2026-07-30). With the Hatchery levelled, four or five
      // eggs come due at once and each one wanted its own tap. Only shown when
      // there is more than one, so it never doubles up with a card's own button.
      if (ready.length > 1)
        SocialGoldButton(
          _creatures.housingFull
              ? 'Settlement full'
              : 'Hatch all ${ready.length}',
          height: 30,
          fontSize: 12,
          onTap: _busy || _creatures.housingFull ? null : _hatchAll,
        ),
    ],
  );

  Widget _eggTile(BreedingJob job, int freeSlots, bool noHatchery) {
    final species = kSpeciesDefs[job.speciesId];
    final canPlace = freeSlots > 0 && !noHatchery && !_busy;
    return SlotTile(
      avatar: SizedBox(width: 34, height: 44, child: EggGlyph(job: job)),
      name: species?.name ?? job.speciesId,
      sub: job.hasChildGenes ? '⚡ ${genePower(job.childBase)}' : '⚡ ?',
      note: species == null ? null : '⏱ ${_hatchHours(species).round()}h',
      highlighted: _selectedEggId == job.id,
      // A greyed button that repeats its own label says it is off but not WHY —
      // name what is missing instead.
      actionLabel: noHatchery
          ? 'No Hatchery'
          : freeSlots <= 0
          ? 'Full'
          : 'Incubate',
      onAction: canPlace ? () => _place(job) : null,
      onTap: () => _openEgg(job),
    );
  }
}
