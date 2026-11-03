import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../settlement/data/item_definitions.dart';
import '../settlement/settlement_controller.dart';
import '../common/widgets/recess_bar.dart';
import '../social/social_actions.dart' show confirmDialog;
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
import '../../core/theme/voxel_icons.dart';
import '../../core/theme/voxel_kit.dart' show vr;

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
  //
  // "BEUTEL-LISTE + EI-DETAIL" (user 2026-11-03, concept 3 of 10 — the old
  // slot cards and egg tiles were 10–11 px text). Three parts, no scrolling
  // except a long bag list:
  //   · the incubators as one slim strip on top (egg, time, bar, Hatch);
  //   · the eggs in the bag as a list on the left, best genes first;
  //   · the chosen egg on the right — its facts, all 14 genes, Incubate.
  // The title and the Breeding | Hatchery switch above it are the
  // HatcheryScreen's, the same frame the breeding half sits in.

  /// The bag, best genes first — the order you want to incubate in.
  List<BreedingJob> get _bagSorted {
    final eggs = [..._breeding.eggs];
    eggs.sort(
      (a, b) => genePower(b.childBase).compareTo(genePower(a.childBase)),
    );
    return eggs;
  }

  /// The egg the right-hand panel shows: the one picked, else the best.
  BreedingJob? _selected(List<BreedingJob> eggs) {
    for (final j in eggs) {
      if (j.id == _selectedEggId) return j;
    }
    return eggs.isEmpty ? null : eggs.first;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_breeding, _creatures]),
    builder: (context, _) {
      final eggs = _bagSorted;
      final chosen = _selected(eggs);
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 56, child: _incubatorStrip(chosen)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 320, child: _bagList(eggs, chosen)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: chosen == null
                        ? zoneBox(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: Text(
                                'Mate a pair on the Breeding tab — the egg '
                                'they lay lands here.',
                                textAlign: TextAlign.center,
                                style: FoE.dim(
                                  size: 15,
                                ).copyWith(color: kBoxInkSoft),
                              ),
                            ),
                          )
                        : _eggPanel(chosen),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  // ── The incubator strip ───────────────────────────────────────────────

  Widget _incubatorStrip(BreedingJob? chosen) {
    final hatching = _breeding.hatchingJobs;
    final noHatchery = _breeding.hatcherySlots <= 0;
    final free = _breeding.freeHatcherySlots;
    final ready = _hatchable;
    final cells = <Widget>[
      for (final job in hatching) _incubatorChip(job),
      if (noHatchery)
        _freeChip('No incubator — build a Hatchery', null)
      else
        for (var i = 0; i < free; i++)
          _freeChip(
            chosen == null ? 'Free incubator' : 'Free · incubate the egg →',
            _busy
                ? null
                : chosen == null
                ? (_breeding.eggs.isEmpty ? null : _pickEgg)
                : () => _place(chosen),
          ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: cells[i]),
        ],
        // HATCH THEM ALL (user 2026-07-30) — only with more than one ready, so
        // it never doubles up with a chip's own Hatch.
        if (ready.length > 1) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: _goldButton(
              _creatures.housingFull
                  ? 'Settlement full'
                  : 'Hatch all ${ready.length}',
              _busy || _creatures.housingFull ? null : _hatchAll,
              size: 15,
            ),
          ),
        ],
      ],
    );
  }

  /// One running incubation: the egg, its name and time, a bar in its
  /// element's colour — and Hatch when it is done.
  Widget _incubatorChip(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final ready = job.isReady;
    final totalMs = species == null ? 0.0 : _hatchHours(species) * 3600000;
    // Estimated against the CURRENT incubation time: `startedAt` is when the
    // mating began, and an accelerator item moves `readyAt` under it — exact
    // about what is left, approximate about what came before.
    final frac = ready || totalMs <= 0
        ? 1.0
        : (1 - job.remaining.inMilliseconds / totalMs).clamp(0.0, 1.0);
    final barColor = species?.element.color ?? CreamPalette.accent;
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
      decoration: ready
          ? raisedTile(
              radius: 12,
            ).copyWith(border: Border.all(color: CreamPalette.better, width: 2))
          : raisedTile(radius: 12),
      child: Row(
        children: [
          SizedBox(width: 32, height: 42, child: EggGlyph(job: job)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        species?.name ?? job.speciesId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.label(size: 15).copyWith(color: kBoxInk),
                      ),
                    ),
                    Text(
                      ready ? 'Ready' : _fmt(job.remaining),
                      style: FoE.value(size: 15).copyWith(
                        color: ready ? CreamPalette.better : kBoxInkSoft,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 8,
                    backgroundColor: CreamPalette.tanShadow.withValues(
                      alpha: 0.5,
                    ),
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          if (ready)
            // A full settlement says so on the button (it used to be a bare
            // buzz plus a silenced snack).
            SizedBox(
              width: 74,
              height: 36,
              child: _goldButton(
                _creatures.housingFull ? 'House full' : 'Hatch',
                _busy || _creatures.housingFull ? null : () => _hatch(job),
                size: 15,
              ),
            )
          else ...[
            if (_heldSpeedItems().isNotEmpty)
              _iconAction(
                Icons.bolt,
                'Speed up (item)',
                _busy ? null : () => _useAccelerator(job),
              ),
            // NOT a delete — it puts the egg back in the bag.
            _iconAction(
              Icons.logout,
              'Back to the bag',
              _busy ? null : () => _returnToBag(job),
            ),
          ],
        ],
      ),
    );
  }

  /// A free incubator (or none at all): a dashed seat.
  Widget _freeChip(String label, VoidCallback? onTap) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: CustomPaint(
      painter: _DashedRRect(
        color: CreamPalette.accent.withValues(alpha: onTap == null ? 0.3 : 0.6),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: FoE.label(size: 14).copyWith(
              color: onTap == null ? kBoxInkFaint : CreamPalette.accent,
            ),
          ),
        ),
      ),
    ),
  );

  /// A small round action inside a chip. [Semantics], not [Tooltip]: these
  /// come and go every second with the countdown, and a Tooltip created or
  /// disposed while the mouse tracker walks its listeners trips an assertion
  /// on desktop.
  Widget _iconAction(IconData icon, String label, VoidCallback? onTap) =>
      Semantics(
        label: label,
        button: true,
        child: Pressable(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: CreamPalette.tanShadow.withValues(alpha: 0.35),
              borderRadius: vr(9),
            ),
            child: PixelIcon(icon, size: 16, color: kBoxInk),
          ),
        ),
      );

  /// The kit's gold button face with a label (and an optional sub-line).
  Widget _goldButton(
    String label,
    VoidCallback? onTap, {
    double size = 17,
    String? sub,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: goldButton(active: onTap != null),
      // Shrinks rather than overflows where a glyph (⏱) sets a taller line.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: size,
                height: 1.1,
                fontWeight: FontWeight.w800,
                color: goldButtonInk(active: onTap != null),
              ),
            ),
            if (sub != null)
              Text(
                sub,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  color: goldButtonInk(active: onTap != null),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  // ── The bag ───────────────────────────────────────────────────────────

  Widget _bagList(List<BreedingJob> eggs, BreedingJob? chosen) => zoneBox(
    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'In the bag · ${eggs.length}',
                  style: FoE.label(size: 16).copyWith(color: kBoxAccent),
                ),
              ),
              Text(
                'best ⚡ first',
                style: FoE.dim(size: 13).copyWith(color: kBoxInkSoft),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        Expanded(
          child: eggs.isEmpty
              ? Center(
                  child: Text(
                    'No eggs in the bag.',
                    style: FoE.dim(size: 15).copyWith(color: kBoxInkSoft),
                  ),
                )
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final job in eggs) _bagRow(job, job.id == chosen?.id),
                  ],
                ),
        ),
      ],
    ),
  );

  Widget _bagRow(BreedingJob job, bool selected) {
    final species = kSpeciesDefs[job.speciesId];
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _selectedEggId = job.id),
      child: Container(
        height: 36,
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: selected
            ? raisedTile(radius: 9)
            : const BoxDecoration(color: Colors.transparent),
        child: Row(
          children: [
            SizedBox(width: 22, height: 29, child: EggGlyph(job: job)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                species?.name ?? job.speciesId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(size: 15).copyWith(color: kBoxInk),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                job.hasChildGenes ? '⚡ ${genePower(job.childBase)}' : '⚡ ?',
                style: FoE.value(size: 15).copyWith(color: kBoxInk),
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                species == null ? '' : '${_hatchHours(species).round()}h',
                textAlign: TextAlign.right,
                style: FoE.dim(size: 14).copyWith(color: kBoxInkSoft),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── The chosen egg ────────────────────────────────────────────────────

  Widget _eggPanel(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final free = _breeding.freeHatcherySlots;
    final noHatchery = _breeding.hatcherySlots <= 0;
    final canPlace = free > 0 && !noHatchery && !_busy;
    final dad = _creatures.byId(job.parentAId);
    final mum = _creatures.byId(job.parentBId);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: raisedTile(radius: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 150,
            child: Column(
              children: [
                // The facts take what is left above the button and shrink
                // rather than push it out (2026-11-03: the parents' line, with
                // ♂/♀ drawn as tall emoji, wrapped and overflowed it by 6 px).
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: 150,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Pressable(
                            onTap: () => _openEgg(job),
                            child: SizedBox(
                              width: 62,
                              height: 80,
                              child: EggGlyph(job: job),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            species?.name ?? job.speciesId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FoE.title(size: 18).copyWith(color: kBoxInk),
                          ),
                          Text(
                            [
                              job.hasChildGenes
                                  ? '⚡ ${genePower(job.childBase)}'
                                  : '⚡ ?',
                              if (species != null) species.rarity.label,
                            ].join(' · '),
                            style: FoE.value(
                              size: 14,
                            ).copyWith(color: kBoxInkSoft),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${dad?.displayName ?? '?'} ♂ × ${mum?.displayName ?? '?'} ♀',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: FoE.dim(
                              size: 12,
                            ).copyWith(color: kBoxInkFaint),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  // A greyed button that repeats its own label says it is
                  // off but not WHY — name what is missing instead.
                  child: _goldButton(
                    noHatchery
                        ? 'No Hatchery'
                        : free <= 0
                        ? 'All full'
                        : 'Incubate',
                    canPlace ? () => _place(job) : null,
                    sub: species == null
                        ? null
                        : '⏱ ${_hoursLabel(_hatchHours(species))}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: _geneGrid(job)),
        ],
      ),
    );
  }

  static String _hoursLabel(double hours) {
    final totalMin = (hours * 60).round();
    final h = totalMin ~/ 60, m = totalMin % 60;
    if (h == 0) return '$m min';
    if (m == 0) return '$h h';
    return '$h h $m min';
  }

  /// All 14 genes of the child inside, two columns of seven: the level-1
  /// value and the growth per level.
  Widget _geneGrid(BreedingJob job) {
    if (!job.hasChildGenes) {
      return Center(
        child: Text(
          'Its genes are only known once it hatches.',
          textAlign: TextAlign.center,
          style: FoE.dim(size: 14).copyWith(color: kBoxInkSoft),
        ),
      );
    }
    const stats = CreatureStat.values;
    final half = (stats.length / 2).ceil();
    // BARS, as on the Breeding tab (user 2026-11-03: "kannst du hier nicht
    // auch die Balken nehmen?"). ONE scale for all 14 — this egg's biggest
    // gene — so a bar reads against every other row, not just its own.
    final maxGene = stats.fold<double>(
      0.001,
      (m, s) => math.max(m, job.childBase[s] ?? 0),
    );
    Widget cell(CreatureStat s) => Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CreamPalette.tan.withValues(alpha: 0.4)),
        ),
      ),
      // The bar runs UNDER the name and the numbers, over the cell's whole
      // width — beside them it got barely 10 px of a ~195 px column.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(
                    size: 14,
                  ).copyWith(color: kBoxInkSoft, height: 1),
                ),
              ),
              Text(
                '${(job.childBase[s] ?? 0).round()}',
                style: FoE.value(size: 17).copyWith(color: kBoxInk, height: 1),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '+${(job.childSlope[s] ?? 0).toStringAsFixed(1)}',
                  textAlign: TextAlign.right,
                  style: FoE.dim(
                    size: 13,
                  ).copyWith(color: kBoxInkFaint, height: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          RecessBar(
            value: ((job.childBase[s] ?? 0) / maxGene).clamp(0.0, 1.0),
            color: CreamPalette.accent,
            height: 6,
            onDark: false,
          ),
        ],
      ),
    );
    Widget column(Iterable<CreatureStat> list) =>
        Column(children: [for (final s in list) Expanded(child: cell(s))]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: column(stats.take(half))),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            children: [
              for (final s in stats.skip(half)) Expanded(child: cell(s)),
              // Keeps both columns' rows the same height when the count is odd.
              for (var i = stats.length - half; i < half; i++)
                const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ],
    );
  }
}

/// A dashed rounded outline — the free incubator's seat.
class _DashedRRect extends CustomPainter {
  final Color color;

  const _DashedRRect({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (!size.isFinite || size.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          const Radius.circular(12),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 7), paint);
        d += 12;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}
