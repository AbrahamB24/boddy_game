import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../workout/widgets/workout_back_button.dart';
import '../settlement/settlement_controller.dart';
import 'creature_detail_screen.dart';
import 'models/breeding_job.dart';
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/breeding_controller.dart';
import 'services/creatures_controller.dart';

// The breeding hut (interim entry: 🥚 button in the collection; moves onto a
// placeable settlement building later). Top: running jobs with live
// countdowns / hatchable eggs. Bottom: pick a species you own both genders
// of, pick the pair, start the timer (hours by rarity — ARK-style).
class BreedingScreen extends StatefulWidget {
  const BreedingScreen({super.key});

  @override
  State<BreedingScreen> createState() => _BreedingScreenState();
}

class _BreedingScreenState extends State<BreedingScreen> {
  final _breeding = BreedingController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  String? _speciesId;
  String? _maleId;
  String? _femaleId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _creatures.load();
    _breeding.load();
    // Live countdowns; cheap enough to just rebuild every second while open.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _breeding.jobs.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  // Species with at least one available creature of EACH gender.
  List<SpeciesDef> get _breedableSpecies {
    final bySpecies = <String, Set<CreatureGender>>{};
    for (final c in _creatures.creatures) {
      if (c.isKo || _creatures.isBreeding(c.id)) continue;
      bySpecies.putIfAbsent(c.speciesId, () => {}).add(c.gender);
    }
    return [
      for (final e in bySpecies.entries)
        if (e.value.length == 2 && kSpeciesDefs[e.key] != null)
          kSpeciesDefs[e.key]!,
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  List<CreatureInstance> _candidates(CreatureGender gender) => [
    for (final c in _creatures.creatures)
      if (c.speciesId == _speciesId &&
          c.gender == gender &&
          !c.isKo &&
          !_creatures.isBreeding(c.id))
        c,
  ];

  CreatureInstance? _byId(String? id) {
    if (id == null) return null;
    for (final c in _creatures.creatures) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _start() async {
    final male = _byId(_maleId);
    final female = _byId(_femaleId);
    if (male == null || female == null) return;
    setState(() => _busy = true);
    final error = await _breeding.start(male, female);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _maleId = null;
        _femaleId = null;
        _speciesId = null;
      }
    });
    _snack(error ?? '💞 Breeding started!');
  }

  Future<void> _hatch(BreedingJob job) async {
    // A hatchling needs a housing slot — keep the egg pending if full.
    if (_creatures.housingFull) {
      _snack('🏠 Settlement full — build more housing before hatching.');
      return;
    }
    setState(() => _busy = true);
    final baby = await _breeding.hatch(job);
    if (!mounted) return;
    setState(() => _busy = false);
    if (baby == null) {
      _snack('Hatching failed.');
      return;
    }
    _snack('🐣 ${baby.displayName} hatched!');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatureDetailScreen(creatureId: baby.id),
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: FoE.label(size: 13)),
      backgroundColor: FoE.panelDark,
    ),
  );

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FoE.bg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_breeding, _creatures]),
          builder: (context, _) => Column(
            children: [
              _topBar(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    Text('Active breeding jobs', style: FoE.title(size: 13)),
                    const SizedBox(height: 8),
                    if (_breeding.jobs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No breeding job running.',
                          style: FoE.dim(size: 12),
                        ),
                      ),
                    for (final job in _breeding.jobs) _jobCard(job),
                    const SizedBox(height: 18),
                    Text('New pair', style: FoE.title(size: 13)),
                    const SizedBox(height: 8),
                    _newPairPanel(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() => Container(
    height: 48,
    decoration: FoE.topBarDecor,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        WorkoutBackButton(
          color: FoE.parchment,
          onTap: () => Navigator.of(context).pop(),
        ),
        Text('🥚 Breeding', style: FoE.title(size: 15)),
        const Spacer(),
        Text('${_breeding.jobs.length} active', style: FoE.dim(size: 11)),
        const SizedBox(width: 12),
      ],
    ),
  );

  Widget _jobCard(BreedingJob job) {
    final species = kSpeciesDefs[job.speciesId];
    final a = _byId(job.parentAId);
    final b = _byId(job.parentBId);
    final ready = job.isReady;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: FoE.panel(
        radius: 10,
        overrideBorder: ready ? FoE.goldBright : null,
        glow: ready,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: ready
                ? const Center(
                    child: Text('🥚', style: TextStyle(fontSize: 30)),
                  )
                : (species?.stageAt(0).imageUrl == null
                      ? const Icon(Icons.pets, color: FoE.gold, size: 26)
                      : Image.network(
                          species!.stageAt(0).imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.pets, color: FoE.gold, size: 26),
                        )),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  species?.name ?? job.speciesId,
                  style: FoE.label(size: 14).copyWith(color: FoE.parchment),
                ),
                Text(
                  '${a?.displayName ?? '?'} ♂ × ${b?.displayName ?? '?'} ♀',
                  style: FoE.dim(size: 10),
                ),
                const SizedBox(height: 2),
                Text(
                  ready ? 'Ready to hatch!' : '⏳ ${_fmt(job.remaining)}',
                  style: FoE.label(size: 12).copyWith(
                    color: ready ? FoE.goldBright : FoE.gold,
                  ),
                ),
              ],
            ),
          ),
          if (ready)
            GestureDetector(
              onTap: _busy ? null : () => _hatch(job),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: FoE.btn(active: true),
                child: Text(
                  '🐣 Hatch',
                  style: FoE.label(size: 12).copyWith(color: FoE.goldBright),
                ),
              ),
            )
          else ...[
            if (SettlementController().isDev)
              IconButton(
                tooltip: 'Finish now (Dev)',
                icon: const Icon(Icons.fast_forward, color: FoE.gold, size: 18),
                onPressed: () => _breeding.devFinishNow(job),
              ),
            IconButton(
              tooltip: 'Cancel',
              icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
              onPressed: () => _breeding.cancel(job),
            ),
          ],
        ],
      ),
    );
  }

  Widget _newPairPanel() {
    final breedable = _breedableSpecies;
    if (breedable.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: FoE.panel(radius: 10),
        child: Text(
          'You need an available male AND female of the same species '
          '(not K.O., not already breeding).',
          style: FoE.dim(size: 12),
        ),
      );
    }
    final species = kSpeciesDefs[_speciesId];
    final males = _speciesId == null ? const <CreatureInstance>[] : _candidates(CreatureGender.male);
    final females = _speciesId == null ? const <CreatureInstance>[] : _candidates(CreatureGender.female);
    final canStart = _maleId != null && _femaleId != null && !_busy;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: FoE.panel(radius: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _speciesId,
            decoration: const InputDecoration(labelText: 'Species'),
            dropdownColor: FoE.panelDark,
            style: FoE.label(size: 14).copyWith(color: FoE.parchment),
            items: breedable
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      '${s.element.emoji} ${s.name} · ${s.rarity.breedHours}h',
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() {
              _speciesId = v;
              _maleId = null;
              _femaleId = null;
            }),
          ),
          if (_speciesId != null) ...[
            const SizedBox(height: 12),
            _parentPicker('♂ Male', males, _maleId, (id) {
              setState(() => _maleId = id);
            }, CreatureGender.male.color),
            const SizedBox(height: 10),
            _parentPicker('♀ Female', females, _femaleId, (id) {
              setState(() => _femaleId = id);
            }, CreatureGender.female.color),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: canStart ? _start : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: FoE.btn(active: canStart),
                  alignment: Alignment.center,
                  child: Text(
                    species == null
                        ? ''
                        : '💞 Start breeding (${species.rarity.breedHours}h)',
                    style: FoE.label(size: 13).copyWith(
                      color: canStart ? FoE.goldBright : FoE.textDim,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _parentPicker(
    String label,
    List<CreatureInstance> options,
    String? selected,
    ValueChanged<String> onPick,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: FoE.dim(size: 11).copyWith(color: accent)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (options.isEmpty)
              Text('— none available —', style: FoE.dim(size: 11)),
            for (final c in options)
              GestureDetector(
                onTap: () => onPick(c.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: FoE.btn(active: selected == c.id),
                  child: Text(
                    '${c.displayName} · Lv ${c.level}',
                    style: FoE.label(size: 12).copyWith(
                      color: selected == c.id ? FoE.goldBright : FoE.parchment,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
