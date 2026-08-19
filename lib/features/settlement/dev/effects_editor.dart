import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/creature_enums.dart';
import '../../creatures/models/species_balance.dart';
import '../../creatures/models/expedition.dart'
    show kBaseCaravanSlots, kBaseExpeditionSlots;
import '../data/building_definitions.dart'
    show
        BuildingEffect,
        WorkshopRole,
        buildPointsForCut,
        buildTimeCut,
        effectiveSlots,
        kBaseBuildSlots,
        kBuildPointsForHalfTime;
import '../data/era_definitions.dart';
import '../data/goods_definitions.dart';
import '../data/workshop_role_effects.dart';
import '../services/trade_center.dart' show kMaxTradeDiscount;

// Reusable editor for the generic `effects` JSON vocabulary shared by
// BuildingDef.fromDefRow/toDefRow and
// EraDef.fromDefRow/toDefRow (see building_definitions.dart /
// era_definitions.dart). One widget, reused
// unchanged across building_def_form.dart, tech_def_form.dart and
// era_def_form.dart — only the allowed `type`/`target` options differ per
// mode. era uses the same 'bonus' targets as tech (wood/stone/food/all/
// buildSpeed) — EraDef's one-time grants are a separate, simpler
// resource map (see ResourceMapEditor), not part of this vocabulary.
enum EffectsMode { building, era }

class EffectsEditor extends StatefulWidget {
  final List<Map<String, dynamic>> initialEffects;
  final EffectsMode mode;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  /// The building's maximum level — drives the per-level HOUSING inputs (one
  /// field per level 2..maxLevel). 1 = no upgrades / non-building modes.
  final int maxLevel;

  const EffectsEditor({
    super.key,
    required this.initialEffects,
    required this.mode,
    required this.onChanged,
    this.maxLevel = 1,
  });

  @override
  State<EffectsEditor> createState() => _EffectsEditorState();
}

class _EffectsEditorState extends State<EffectsEditor> {
  late List<Map<String, dynamic>> _effects;

  @override
  void initState() {
    super.initState();
    _effects = widget.initialEffects
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  List<String> get _typeOptions => switch (widget.mode) {
    // 'workshop' is the creature-driven scalable output; 'bonus' the flat
    // settlement-wide modifiers. The rest are the per-era palette (production,
    // resource %, expedition amplifiers, expedition slots, healing, housing) —
    // each active from its "ab Ära" onward (see _EffectRow).
    EffectsMode.building => const [
      'workshop',
      'bonus',
      'production',
      'resource',
      'expedition',
      'expeditionSlots',
      'caravan',
      'caravanSlots',
      'huntOptions',
      'heal',
      'healSlots',
      'healQueue',
      'housing',
      // NO 'xp': the work-XP rate is ONE settlement-wide number since
      // 2026-07-30 (Species-Budget → XP → "Arbeit"), so a per-building field
      // here could only lie — the game would ignore whatever it was set to.
      'breeding',
      'hatching',
      'queueSlots',
      'buildSlots',
      'trade',
      'craftSlots',
      'craftQueue',
      'storage',
    ],
    EffectsMode.era => const ['bonus'],
  };

  void _addEffect() {
    setState(() => _effects.add(_defaultFor(_typeOptions.first)));
    widget.onChanged(_effects);
  }

  void _removeAt(int i) {
    setState(() => _effects.removeAt(i));
    widget.onChanged(_effects);
  }

  void _updateAt(int i, Map<String, dynamic> next) {
    setState(() => _effects[i] = next);
    widget.onChanged(_effects);
  }

  Map<String, dynamic> _defaultFor(String type) => switch (type) {
    'workshop' => {
      'type': 'workshop',
      'stat': 'production',
      'resource': 'wood',
      'mult': 0.1,
      'slots': 1,
    },
    'bonus' => {
      'type': 'bonus',
      'target': widget.mode == EffectsMode.building ? 'buildSpeed' : 'wood',
      'value': 0.0,
    },
    'slots' => {'type': 'slots', 'target': 'build', 'amount': 0},
    'production' => {'type': 'production', 'key': 'wood', 'value': 0.0, 'era': 1},
    'resource' => {'type': 'resource', 'key': 'all', 'value': 0.0, 'era': 1},
    'expedition' => {
      'type': 'expedition',
      'key': 'carry',
      'value': 0.0,
      'era': 1,
    },
    'expeditionSlots' => {'type': 'expeditionSlots', 'value': 1, 'era': 1},
    'caravan' => {'type': 'caravan', 'key': 'carry', 'value': 0.0, 'era': 1},
    'caravanSlots' => {'type': 'caravanSlots', 'value': 1, 'era': 1},
    'huntOptions' => {'type': 'huntOptions', 'value': 1, 'era': 1},
    'heal' => {'type': 'heal', 'key': 'speed', 'value': 0.0, 'era': 1},
    // How many creatures the building can treat at once (per level). Default 1
    // so a freshly added effect immediately caps healing to one at a time.
    'healSlots' => {'type': 'healSlots', 'value': 1, 'era': 1},
    // How many more may WAIT for one of those slots (user 2026-07-27). Default
    // 2 so a freshly added effect is a real waiting room, not a cap of one.
    'healQueue' => {'type': 'healQueue', 'value': 2, 'era': 1},
    'housing' => {'type': 'housing', 'value': 0, 'era': 1},
    // How many MATINGS can run at once here (per level) — the Breeding Hut.
    'breeding' => {'type': 'breeding', 'value': 1, 'era': 1},
    // The same for INCUBATIONS — the Hatchery's own cap (user 2026-07-26).
    'hatching' => {'type': 'hatching', 'value': 1, 'era': 1},
    // Extra build-queue slots this building grants (per level).
    'queueSlots' => {'type': 'queueSlots', 'value': 1, 'era': 1},
    // Extra simultaneous construction sites this building grants (per level).
    'buildSlots' => {'type': 'buildSlots', 'value': 1, 'era': 1},
    // % off the trade spread (Trade Center). See services/trade_center.dart.
    'trade' => {'type': 'trade', 'value': 5.0, 'era': 1},
    // How many items the Workshop makes at once, and how many may wait for a
    // bench (user 2026-07-30) — the Healing Hut's pair, for crafting.
    'craftSlots' => {'type': 'craftSlots', 'value': 1, 'era': 1},
    'craftQueue' => {'type': 'craftQueue', 'value': 2, 'era': 1},
    // Room for ONE resource. Keyed, because every resource has its own
    // ceiling and its own ladder.
    'storage' => {'type': 'storage', 'key': 'wood', 'value': 500.0, 'era': 1},
    _ => {'type': type},
  };

  /// A BUILDING's effects are FIXED (user 2026-07-29: "ich muss nicht neue
  /// Effekte hinzufügen können, diese nur einstellen"). Which effects a
  /// building has is authored in building_effects.dart; this form only turns
  /// their numbers.
  ///
  /// That is what removes the three controls that made this screen hard: the
  /// 19-entry type dropdown, "+ Add Effect", and the per-row delete. Era defs
  /// keep all three — an era's bonus list really is freely composed.
  bool get _fixedShape => widget.mode == EffectsMode.building;

  /// The resources this building STORES, in authoring order — the keys of its
  /// `storage` effects. Handed to every row so a store post can offer one output
  /// dial per resource (user 2026-07-30); a row only knows its own map, and the
  /// set of goods a store holds lives in its sibling effects.
  List<String> get _storageKeys => [
    for (final e in _effects)
      if (e['type'] == 'storage')
        ((e['key'] ?? e['target'] ?? e['resource']) as String?) ?? '',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Effects',
              style: FoE.label(size: 14).copyWith(color: FoE.gold),
            ),
            if (_fixedShape) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '· im Code festgelegt, hier nur einstellbar',
                  style: FoE.dim(size: 10),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (_effects.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _fixedShape
                  ? 'Dieses Gebäude hat keine Effekte. Neue kommen in '
                      'data/building_effects.dart dazu.'
                  : 'Noch keine Effekte.',
              style: FoE.dim(size: 11),
            ),
          ),
        for (int i = 0; i < _effects.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _EffectRow(
              key: ValueKey(i),
              effect: _effects[i],
              mode: widget.mode,
              typeOptions: _typeOptions,
              maxLevel: widget.maxLevel,
              fixedShape: _fixedShape,
              onChanged: (e) => _updateAt(i, e),
              onRemove: () => _removeAt(i),
              defaultFor: _defaultFor,
              storageKeys: _storageKeys,
            ),
          ),
        if (!_fixedShape)
          GestureDetector(
            onTap: _addEffect,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: FoE.btn(),
              alignment: Alignment.center,
              child: Text(
                '+ Add Effect',
                style: FoE.label(size: 14).copyWith(color: FoE.goldBright),
              ),
            ),
          ),
      ],
    );
  }
}

class _EffectRow extends StatelessWidget {
  final Map<String, dynamic> effect;
  final EffectsMode mode;
  final List<String> typeOptions;
  final int maxLevel;

  /// Whether the effect's TYPE is fixed — see EffectsEditor._fixedShape.
  final bool fixedShape;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onRemove;
  final Map<String, dynamic> Function(String type) defaultFor;

  /// The resources THIS BUILDING stores — its sibling `storage` effects' keys,
  /// in authoring order. A store post gets one output dial per entry (user
  /// 2026-07-30: "Ich muss den output pro worker für jede Ressource einzeln
  /// einstellen können"), so the row has to know what the building holds; a
  /// workshop row cannot read that off its own map.
  final List<String> storageKeys;

  const _EffectRow({
    super.key,
    required this.effect,
    required this.mode,
    required this.typeOptions,
    required this.maxLevel,
    required this.fixedShape,
    required this.onChanged,
    required this.onRemove,
    required this.defaultFor,
    this.storageKeys = const [],
  });

  // 'queueSlots' is intentionally NOT here anymore (user 2026-07-25): build
  // queue slots are their own per-level `queueSlots` effect type now, so the old
  // flat bonus target would just be a second, non-per-level way to set the same
  // thing. Legacy rows that still carry bonus/queueSlots keep parsing (see
  // BuildingDef.fromDefRow) — this only removes it from the authoring dropdown.
  List<String> get _bonusTargets => mode == EffectsMode.building
      ? const ['buildSpeed', 'population']
      : const ['wood', 'stone', 'food', 'all', 'buildSpeed'];

  /// What a worker-free `production` effect can trickle: the settlement raws,
  /// every good — and `construction`, the build-point pool.
  ///
  /// Construction is here because the Castle's automatic build points
  /// were deleted with the other hardcoded bonuses (user 2026-07-25). Without
  /// this key there would be no way to give a building worker-free build power
  /// at all, and a settlement with no staffed Builder Camp could never build.
  List<String> get _productionKeys => [
    'wood',
    'stone',
    'gold',
    ...kGoodsDefs.keys,
    WorkshopRole.kConstruction,
  ];

  /// What a `workshop` role can output: the raws + goods + the pseudo outputs
  /// that feed a SYSTEM instead of the stockpile. All five non-resource roles
  /// must be listed — a value the dropdown can't show falls back to its first
  /// entry ('wood'), which on save would silently turn a breeder post or a
  /// legendary-boost slot into a wood producer (user 2026-07-25: "warum hat
  /// breeding hut als output wood?"). 'construction'/'research'/'training' plus
  /// 'breeding' (breeder post) and 'legendary_boost' (legendary slot).
  /// De-duplicated: 'construction' is already the last of [_productionKeys],
  /// and a DropdownButton ASSERTS on two items sharing a value — so a role that
  /// really outputs construction (the Builder Camp) used to crash this editor
  /// the moment its row was drawn.
  List<String> get _workshopOutputs => <String>{
    ..._productionKeys,
    WorkshopRole.kConstruction,
    WorkshopRole.kCrafting,
    WorkshopRole.kTraining,
    WorkshopRole.kBreeding,
    WorkshopRole.kHatching,
    WorkshopRole.kLegendaryBoost,
    // The civil-service posts (user 2026-07-25): their output is a FRACTION
    // fed to a system, not units in the storehouse.
    WorkshopRole.kHealSpeed,
    WorkshopRole.kTradeRate,
    WorkshopRole.kExpCarry,
    WorkshopRole.kExpTravel,
    WorkshopRole.kExpGoods,
    // The COMBINED post (user 2026-07-29): the three above in ONE effect, each
    // still on its own dial — see the `mults` fields below.
    WorkshopRole.kExpedition,
    WorkshopRole.kCaravan,
    // The STORE post (user 2026-07-30): room for what this building holds, one
    // dial per resource. Offered here so a store built in Dev Mode can have one
    // — the bundled stores get theirs from building_effects.dart.
    WorkshopRole.kStorageRoom,
  }.toList();

  /// Whether the chosen output is a post with several dials instead of one
  /// `mult` — the combined posts, see [WorkshopRole.kCombinedParts].
  bool get _combined => _combinedParts.isNotEmpty;

  /// The chosen output's parts, empty for a plain post.
  Map<String, String> get _combinedParts =>
      WorkshopRole.partsOf((effect['resource'] as String?) ?? '');

  /// Whether this row is a STORE post that has resources to split its output
  /// across — then it gets one dial per resource instead of one flat `mult`
  /// (user 2026-07-30). A store post on a building with no `storage` effect has
  /// nothing to key dials by and keeps the single field.
  bool get _perStorageResource =>
      effect['resource'] == WorkshopRole.kStorageRoom && storageKeys.isNotEmpty;

  /// The dials a store post shows, with today's effective value for each — the
  /// resource's own entry when authored, else the flat `mult` (the runtime's
  /// fallback, see [WorkshopRole.storageMultFor]).
  ///
  /// Seeding the WHOLE map on every edit is what keeps the fallback from
  /// surprising the author: change one resource and the other three keep the
  /// number they were already showing, instead of silently reverting to `mult`
  /// once the row's `mults` map exists.
  Map<String, double> get _storageSeed {
    final flat = (effect['mult'] as num?)?.toDouble() ?? 0;
    final mults = (effect['mults'] as Map?) ?? const {};
    return {
      for (final key in storageKeys)
        key: (mults[key] as num?)?.toDouble() ?? flat,
    };
  }

  @override
  Widget build(BuildContext context) {
    final type = effect['type'] as String? ?? typeOptions.first;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: FoE.panel(radius: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // With the shape fixed, the row wears its NAME instead of a dropdown
          // and a delete button (user 2026-07-29). The name is the shared
          // vocabulary the player sees, so the form and the building dialog
          // call the same effect the same thing.
          if (fixedShape)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Text(
                    _fixedTitle(type),
                    style: FoE.label(size: 13).copyWith(color: FoE.goldBright),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: _dropdown(
                    'Type',
                    type,
                    typeOptions,
                    (v) => onChanged(defaultFor(v!)),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: onRemove,
                ),
              ],
            ),
          ..._fieldsFor(type),
          _LevelPreview(
            effect: effect,
            maxLevel: maxLevel,
            storageKeys: storageKeys,
          ),
        ],
      ),
    );
  }

  /// What `mult` MEANS for the chosen output. It was labelled "Output per stat
  /// point /h" for every role, which is only true for the stockpile ones: on a
  /// breeder post or a civil-service post the same number is a power figure or
  /// a fraction, and on construction/training it does nothing at all (user
  /// 2026-07-26).
  static String _multLabel(String? resource) => switch (resource) {
    WorkshopRole.kBreeding => 'Mating power per stat point',
    WorkshopRole.kHatching => 'Incubation power per stat point',
    WorkshopRole.kHealSpeed => 'Healing-time cut per stat point (0.01 = 1 %)',
    WorkshopRole.kTradeRate => 'Spread cut per stat point (0.01 = 1 %)',
    WorkshopRole.kExpTravel => 'Travel-time cut per stat point (0.01 = 1 %)',
    WorkshopRole.kExpCarry ||
    WorkshopRole.kExpGoods =>
      'Bonus per stat point (0.01 = +1 %)',
    WorkshopRole.kCrafting => 'Craft seconds per stat point /h',
    WorkshopRole.kConstruction => 'Build points per stat point (10 = 1 stat → '
        '10 points)',
    WorkshopRole.kTraining =>
      'no effect — XP rate lives in Species budget → XP',
    WorkshopRole.kLegendaryBoost =>
      'Bonus per stationed legendary (0.5 = +50 %)',
    // Only shown when the building stores NOTHING yet — otherwise the row draws
    // one dial per resource instead (user 2026-07-30). Labelled as the fallback
    // it is, so a number typed here does not look per-resource.
    WorkshopRole.kStorageRoom =>
      'Room per stat point (fallback for resources with no dial)',
    _ => 'Output per stat point /h',
  };

  /// What ONE dial of a combined post means, naming the stat it reads.
  static String _partLabel(String part) => switch (part) {
    'carry' => 'Carrying capacity per CARRY point (0.01 = +1 %)',
    'goods' => 'Goods yield per GATHERING point (0.01 = +1 %)',
    'travel' => 'Travel-time cut per SPEED point (0.01 = 1 %)',
    _ => '$part per stat point',
  };

  /// What this row IS, in the shared vocabulary — the same words the building
  /// dialog and the build menu use for the same effect.
  String _fixedTitle(String type) {
    if (type == 'workshop') {
      final res = (effect['resource'] as String?) ?? '';
      final stat = CreatureStat.fromName(effect['stat'] as String?);
      final what = workshopRoleName(res) ?? kGoodsDefs[res]?.name ??
          (res.isEmpty ? 'Resource' : res[0].toUpperCase() + res.substring(1));
      return '👷 $what · ${stat.label}';
    }
    final key = (effect['key'] as String?) ?? '';
    return '${buildingEffectEmoji(type)} ${buildingEffectLabel(type)}'
        '${key.isEmpty ? '' : ' · $key'}';
  }

  /// A dropdown that decides the effect's SHAPE (which stat, which resource,
  /// which target). Hidden when the shape is fixed — the row title already
  /// says it, and offering to change it would be offering to author a
  /// different effect (user 2026-07-29).
  Widget _shapeDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) => fixedShape
      ? const SizedBox.shrink()
      : _dropdown(label, value, options, onChanged);

  List<Widget> _fieldsFor(String type) {
    switch (type) {
      case 'workshop':
        return [
          _shapeDropdown(
            // kPostableStats, not kCivilianStats: the trip-amplifier posts read
            // `speed` and `carry`, which are not work roles (user 2026-07-26).
            'Worker stat (which stat drives output)',
            (effect['stat'] as String?) ?? kPostableStats.first.name,
            kPostableStats.map((s) => s.name).toList(),
            (v) => onChanged({...effect, 'stat': v}),
          ),
          _shapeDropdown(
            'Output',
            (effect['resource'] as String?) ?? _workshopOutputs.first,
            _workshopOutputs,
            (v) {
              final next = {...effect, 'resource': v};
              // A combined post is tuned through `mults`, not `mult` — seed a
              // dial per part so picking it from the dropdown gives a working
              // post instead of a row of zeroes.
              final parts = WorkshopRole.partsOf(v ?? '');
              if (parts.isNotEmpty &&
                  ((effect['mults'] as Map?) ?? const {}).isEmpty) {
                next['mults'] = {
                  for (final part in parts.keys)
                    part: part == 'travel' ? 0.002 : 0.001,
                };
              }
              onChanged(next);
            },
          ),
          // ONE post, one dial per PART (user 2026-07-29: "exp carry capacity,
          // exp goods und exp speed in einem Effekt … welchen ich aber separat
          // einstellen kann"; the Caravanserai joined it on 2026-07-30). One
          // seat count, one hire list — and each part reads the stat it
          // amplifies, so the labels name that stat rather than the post's own.
          //
          // Rendered FROM the role's parts, so a post with two of them shows
          // two fields: the caravan has no goods yield to give.
          if (_combined) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'One post for the whole trip. The "Worker stat" above only '
                'decides the seat and the hire ranking — each dial below reads '
                'the stat it amplifies.',
                style: FoE.dim(size: 10),
              ),
            ),
            for (final part in _combinedParts.keys)
              _multsField(part, _partLabel(part)),
            _numField('Monster slots (level 1)', 'slots', isInt: true),
          ] else if (_perStorageResource) ...[
            // ONE DIAL PER RESOURCE (user 2026-07-30: "Ich muss den output pro
            // worker für jede Ressource einzeln einstellen können"). The keys
            // are the building's OWN `storage` effects, so the dials and the
            // ceilings they raise can never drift apart — add a storage effect
            // and its dial appears here.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Room per point of the worker stat, per resource this store '
                'holds. A resource with no storage effect gets no room.',
                style: FoE.dim(size: 10),
              ),
            ),
            for (final key in storageKeys)
              _multsField(
                key,
                'Room per stat point · ${kGoodsDefs[key]?.name ?? key}',
                seed: _storageSeed,
              ),
            _numField('Monster slots (level 1)', 'slots', isInt: true),
          ] else
            Row(
              children: [
                Expanded(
                  child: _numField(
                    _multLabel(effect['resource'] as String?),
                    'mult',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numField('Monster slots (level 1)', 'slots',
                      isInt: true),
                ),
              ],
            ),
          _levelStepsBlock(
            title: 'Monsters per level (extra slots)',
            help: 'How many work slots this LEVEL adds. Empty/0 = no growth. '
                'Slots = the level-1 count + every step up to this level.',
            mapKey: 'slotSteps',
          ),
          _levelFactorField(),
        ];
      case 'bonus':
        return [
          _dropdown(
            'Target',
            (effect['target'] as String?) ?? _bonusTargets.first,
            _bonusTargets,
            (v) => onChanged({...effect, 'target': v}),
          ),
          _numField('Value (0.30 = +30%)', 'value'),
        ];
      case 'slots':
        return [
          _dropdown(
            'Target',
            (effect['target'] as String?) ?? 'build',
            const ['build', 'queue'],
            (v) => onChanged({...effect, 'target': v}),
          ),
          _numField('Amount', 'amount', isInt: true),
        ];
      case 'production':
        return [
          _shapeDropdown(
            'Resource (produced without workers)',
            (effect['key'] as String?) ?? _productionKeys.first,
            _productionKeys,
            (v) => onChanged({...effect, 'key': v}),
          ),
          // Construction is authored in the SAME unit as a builder's stat (user
          // 2026-07-26): the value is what a monster of that level would
          // contribute, not raw build-seconds.
          _numField(
            (effect['key'] as String?) == WorkshopRole.kConstruction
                ? 'Build points — same unit as a worker with that stat'
                : 'Einheiten pro Stunde',
            'value',
          ),
          _levelFactorField(),
          _eraField(),
        ];
      case 'resource':
        return [
          _shapeDropdown(
            'Ziel (+% Produktion)',
            (effect['key'] as String?) ?? 'all',
            const ['all', 'wood', 'stone', 'food'],
            (v) => onChanged({...effect, 'key': v}),
          ),
          _numField('Bonus (0.30 = +30 %)', 'value'),
          _levelFactorField(),
          _eraField(),
        ];
      case 'expedition':
        return [
          _shapeDropdown(
            'Ziel',
            (effect['key'] as String?) ?? 'carry',
            const ['carry', 'travel', 'goods'],
            (v) => onChanged({...effect, 'key': v}),
          ),
          _numField('Bonus (0.10 = +10 %; travel = Reisezeit-Cut)', 'value'),
          _levelFactorField(),
          _eraField(),
        ];
      case 'expeditionSlots':
        return [
          _numField(
            'Extra simultaneous expeditions (level 1)',
            'value',
            isInt: true,
          ),
          // A LADDER, like every other count (user 2026-07-29: "hier will ich
          // auch bei jedem level angeben können, wieviel dazukommen"). The
          // runtime has always read one — _countEffectTotal prefers levelSteps
          // over the factor, which is how the bundled Scout Post hands out its
          // second slot at L4 and its third at L8 — but the editor offered
          // only the percent factor, so a ladder was authorable in code and
          // nowhere else.
          _levelStepsBlock(
            title: 'Growth per level (extra expeditions)',
            help: 'How many more expeditions may run at once FROM this level. '
                'Empty/0 = no growth. Slots = the start value + every step up '
                'to this level. Any step at all overrides the factor below.',
          ),
          _levelFactorField(),
          _baseNote(kBaseExpeditionSlots, 'expedition'),
          _eraField(),
        ];
      // The caravan pair. Same shapes as the expedition pair on purpose — they
      // are the same two questions asked about the other road (user
      // 2026-07-29) — but their OWN effect types, so a scout post can never
      // widen a caravan's hold.
      case 'caravan':
        return [
          _shapeDropdown(
            'Ziel',
            (effect['key'] as String?) ?? 'carry',
            const ['carry', 'travel'],
            (v) => onChanged({...effect, 'key': v}),
          ),
          _numField('Bonus (0.10 = +10 %; travel = Reisezeit-Cut)', 'value'),
          _levelFactorField(),
          _eraField(),
        ];
      case 'caravanSlots':
        return [
          _numField(
            'Extra simultaneous caravans (level 1)',
            'value',
            isInt: true,
          ),
          _levelStepsBlock(
            title: 'Growth per level (extra caravans)',
            help: 'How many more caravans may be on the road FROM this level. '
                'Empty/0 = no growth. Slots = the start value + every step up '
                'to this level. Any step at all overrides the factor below.',
          ),
          _levelFactorField(),
          _baseNote(kBaseCaravanSlots, 'caravan'),
          _eraField(),
        ];
      case 'huntOptions':
        return [
          _numField(
            'Extra hunt lengths at level 1 (1 opens the 30-min hunt)',
            'value',
            isInt: true,
          ),
          _levelStepsBlock(
            title: 'Growth per level (extra hunt lengths)',
            help: 'How many more hunt variants open FROM this level, in order. '
                'Empty/0 = no growth. Any step at all overrides the factor '
                'below.',
          ),
          _levelFactorField(),
          _eraField(),
        ];
      case 'heal':
        return [
          _shapeDropdown(
            'Ziel',
            (effect['key'] as String?) ?? 'speed',
            const ['speed', 'cost'],
            (v) => onChanged({...effect, 'key': v}),
          ),
          _numField('Reduktion (0.30 = −30 %, max 90 %)', 'value'),
          _levelFactorField(),
          _eraField(),
        ];
      case 'housing':
        return [
          _numField('Start capacity (seats at level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra seats)',
            help: 'How many seats this LEVEL adds. Empty/0 = no growth. '
                'Capacity = the start value + every step up to this level.',
          ),
          _eraField(),
        ];
      case 'healSlots':
        return [
          _numField('Simultaneous healings (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra healing slots)',
            help: 'How many more monsters this LEVEL can treat at once. '
                'Empty = unlimited everywhere. '
                'Slots = the start value + every step up to this level.',
          ),
          _eraField(),
        ];
      case 'healQueue':
        return [
          _numField('Waiting room (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra waiting places)',
            help: 'How many more monsters this LEVEL can keep in line for a '
                'treatment. This is NOT the number treated at once (see '
                'healSlots) — it is how many may wait for one. '
                'No healQueue effect anywhere = an unlimited line.',
          ),
          _eraField(),
        ];
      // Two buildings, same shape, own keys (user 2026-07-26): 'breeding' caps
      // the Breeding Hut's matings, 'hatching' the Hatchery's incubations.
      case 'breeding':
      case 'hatching':
        final what = type == 'breeding' ? 'matings' : 'incubations';
        return [
          _numField(
            'Simultaneous $what (level 1)',
            'value',
            isInt: true,
          ),
          _levelStepsBlock(
            title: 'Growth per level (extra jobs)',
            help: 'How many more simultaneous $what this LEVEL adds. '
                'Empty/0 = no growth. '
                'Capacity = the start value + every step up to this level.',
          ),
          _eraField(),
        ];
      case 'queueSlots':
        return [
          _numField('Build queue slots (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra queue slots)',
            help: 'How many queue slots this LEVEL adds. Empty/0 = no growth. '
                'Slots = the start value + every step up to this level.',
          ),
          _eraField(),
        ];
      case 'buildSlots':
        return [
          _numField('Simultaneous build sites (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra build sites)',
            help: 'How many build sites this LEVEL adds. Empty/0 = no growth. '
                'Sites = the start value + every step up to this level.',
          ),
          // The settlement's OWN slot is easy to forget and turns every number
          // here into "one more than I authored" in play (user 2026-07-26:
          // "wiso habe ich bei build camp lvl2 bereits 2 build slots").
          _baseNote(kBaseBuildSlots, 'build site'),
          _eraField(),
        ];
      case 'craftSlots':
        return [
          _numField('Simultaneous crafts (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra benches)',
            help: 'How many more items this LEVEL can be making at once. '
                'Empty/0 = no growth. '
                'Benches = the start value + every step up to this level.',
          ),
          _eraField(),
        ];
      case 'craftQueue':
        return [
          _numField('Waiting room (level 1)', 'value', isInt: true),
          _levelStepsBlock(
            title: 'Growth per level (extra waiting places)',
            help: 'How many more items may QUEUE for a free bench. This is NOT '
                'how many are made at once (see craftSlots) — it is how many '
                'may line up. No craftQueue effect anywhere = an endless line.',
          ),
          _eraField(),
        ];
      case 'storage':
        return [
          _shapeDropdown(
            'Resource',
            (effect['key'] as String?) ?? _productionKeys.first,
            _productionKeys,
            (v) => onChanged({...effect, 'key': v}),
          ),
          _numField('Room at level 1', 'value'),
          // ONE way to grow a store, and it is the percentage (user
          // 2026-07-30: "gold und storehaus will ich auch einen prozentualen
          // anstieg festlegen können").
          //
          // The absolute per-level ladder is deliberately NOT offered here.
          // A store is authored as a compounding percentage in
          // building_effects.dart, and `levelSteps` silently beats
          // `levelFactor` — so a form with both fields would let the author
          // type a percentage into a box that the rungs above it quietly
          // override. Exact rungs for a resource are a code edit now, which is
          // where the growth MODE lives.
          _levelFactorField(),
          _baseNote(0, 'room of its own'),
          _eraField(),
        ];
      case 'trade':
        return [
          _numField('Better trade rates (percentage points at level 1)', 'value'),
          _levelFactorField(),
          _eraField(),
        ];
      default:
        return const [];
    }
  }

  /// Explicit per-level increments, shared by every count-like effect (user
  /// 2026-07-24 housing; extended 2026-07-25 to breeding, healSlots, queueSlots
  /// and worker slots). Instead of a percent factor the author enters how many
  /// EXTRA units the building gains AT each level — one field per level
  /// 2..maxLevel. Value at level L = the "Stufe 1" base + Σ steps up to L.
  /// Stored under [mapKey] ('levelSteps' for effects, 'slotSteps' for the
  /// workshop worker count) as {'2': n, '3': n, …} (empty entries dropped).
  Widget _levelStepsBlock({
    required String title,
    required String help,
    String mapKey = 'levelSteps',
  }) {
    final steps = <String, dynamic>{
      for (final e in ((effect[mapKey] as Map?) ?? const {}).entries)
        e.key.toString(): e.value,
    };
    if (maxLevel < 2) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          'Set a max level above 1 under "Build" to enter per-level growth.',
          style: FoE.dim(size: 11),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: FoE.label(size: 12).copyWith(color: FoE.gold)),
          Text(help, style: FoE.dim(size: 10)),
          const SizedBox(height: 8),
          // Compact grid instead of one long vertical list (user 2026-07-25):
          // several level fields side by side. Columns/width are computed from
          // the available space so it stays tidy on any form width.
          LayoutBuilder(
            builder: (context, c) {
              const cols = 3;
              const gap = 8.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 8,
                children: [
                  for (var lvl = 2; lvl <= maxLevel; lvl++)
                    SizedBox(
                      width: w,
                      child: _levelStepField(lvl, steps, mapKey),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  /// "The settlement already has N of these on its own" — the sentence that
  /// makes an authored count add up to what the player sees.
  ///
  /// Every one of these effects is a BONUS on top of a settlement-wide base, so
  /// the number in the field above is never the total. Reading it as the total
  /// is exactly the confusion this note exists to prevent.
  Widget _baseNote(int base, String noun) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      base == 0
          ? 'The settlement has no $noun of its own — this effect is the '
              'whole supply.'
          : 'ON TOP of the settlement\'s own $base $noun'
              '${base == 1 ? '' : 's'}: a level granting 1 here means '
              '${base + 1} in play.',
      style: FoE.dim(size: 11).copyWith(color: FoE.gold),
    ),
  );

  Widget _levelStepField(int lvl, Map<String, dynamic> steps, String mapKey) {
    final cur = steps['$lvl'] as num?;
    return TextFormField(
      // Stable key so typing keeps focus as the form rebuilds.
      key: ValueKey('$mapKey-step-$lvl'),
      initialValue: (cur == null || cur == 0) ? '' : cur.toString(),
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9-]'))],
      style: FoE.label(size: 14).copyWith(color: FoE.parchment),
      textAlign: TextAlign.center,
      decoration: InputDecoration(
        // Short label — the block title already says WHAT is being added, so the
        // cell only needs the level. Keeps the grid cells narrow and readable.
        labelText: 'Level $lvl',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      ),
      onChanged: (s) {
        final v = int.tryParse(s);
        final next = {...effect};
        final map = <String, dynamic>{
          for (final e in ((next[mapKey] as Map?) ?? const {}).entries)
            e.key.toString(): e.value,
        };
        if (v == null || v == 0) {
          map.remove('$lvl');
        } else {
          map['$lvl'] = v;
        }
        if (map.isEmpty) {
          next.remove(mapKey);
        } else {
          next[mapKey] = map;
        }
        onChanged(next);
      },
    );
  }

  /// Per-effect level scaling, shown as a plain PERCENT-per-level (user
  /// 2026-07-24: the raw "×/Stufe" factor was unclear). The user types how much
  /// the effect grows each building level — e.g. 30 = +30 % per level, 0 = stays
  /// the same. Stored as the multiplier (1 + %/100). Empty = the settlement's
  /// default +50 %/level curve.
  Widget _levelFactorField() {
    final v = effect['levelFactor'] as num?;
    final pct = v == null ? '' : ((v.toDouble() - 1) * 100).round().toString();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        initialValue: pct,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true, signed: true),
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: const InputDecoration(
          labelText: 'Growth per level (%)',
          helperText: 'e.g. 30 = +30 %/level · 0 = stays flat · '
              'empty = the default +50 %',
          helperMaxLines: 2,
          isDense: true,
        ),
        onChanged: (s) {
          final p = double.tryParse(s);
          final next = {...effect};
          if (p == null) {
            next.remove('levelFactor');
          } else {
            next['levelFactor'] = 1 + p / 100;
          }
          onChanged(next);
        },
      ),
    );
  }

  /// The "ab Ära" selector shared by every per-era palette effect: the effect
  /// is active once the settlement reaches this era (1 = from the start).
  Widget _eraField() {
    final eras = kEraDefs.values.toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    final current = (effect['era'] as num?)?.toInt() ?? 1;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<int>(
        initialValue: eras.any((e) => e.order == current) ? current : 1,
        decoration: const InputDecoration(
          labelText: 'From era (effect active from)',
          isDense: true,
        ),
        dropdownColor: FoE.panelDark,
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        items: [
          for (final e in eras)
            DropdownMenuItem(
              value: e.order,
              child: Text('Era ${e.order} · ${e.name}'),
            ),
        ],
        onChanged: (v) => onChanged({...effect, 'era': v ?? 1}),
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String?> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DropdownButtonFormField<String>(
        initialValue: options.contains(value) ? value : options.first,
        decoration: InputDecoration(labelText: label, isDense: true),
        dropdownColor: FoE.panelDark,
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  // (per-level preview lives in _LevelPreview at the bottom of this file)

  /// One dial of a MULTI-DIAL post — [_numField] writing into the role's `mults`
  /// map instead of a top-level key. It is what lets the three expedition
  /// amplifiers live in ONE effect row and still be tuned apart (user
  /// 2026-07-29), and what gives a store one output per resource (user
  /// 2026-07-30).
  ///
  /// [seed] supplies the value for keys the map does not carry yet, and is
  /// written back with the edit. A store post needs it: its dials fall back to
  /// the flat `mult`, so without seeding, filling in ONE resource would drop the
  /// others to whatever `mult` happens to be — a number the author just stopped
  /// being shown.
  Widget _multsField(
    String part,
    String label, {
    Map<String, double> seed = const {},
  }) {
    final mults = <String, dynamic>{
      ...seed,
      for (final e in ((effect['mults'] as Map?) ?? const {}).entries)
        e.key.toString(): e.value,
    };
    final cur = mults[part] as num?;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        // Stable key per part so typing keeps focus across the live rebuild.
        key: ValueKey('mults-$part'),
        initialValue: (cur ?? 0).toString(),
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
        ],
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) => onChanged({
          ...effect,
          'mults': {...mults, part: double.tryParse(v) ?? 0},
        }),
      ),
    );
  }

  Widget _numField(String label, String key, {bool isInt = false}) {
    final current = effect[key];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextFormField(
        // Stable key per (type, field) so a value survives the live rebuild on
        // every keystroke instead of resetting/losing focus.
        key: ValueKey('num-${effect['type']}-$key'),
        initialValue: current == null ? '0' : (current as num).toString(),
        keyboardType: TextInputType.numberWithOptions(
          decimal: !isInt,
          signed: true,
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            isInt ? RegExp(r'[0-9-]') : RegExp(r'[0-9.\-]'),
          ),
        ],
        style: FoE.label(size: 14).copyWith(color: FoE.parchment),
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (v) {
          final parsed = isInt ? int.tryParse(v) : double.tryParse(v);
          onChanged({...effect, key: parsed ?? 0});
        },
      ),
    );
  }
}

/// What this effect ACTUALLY does at each building level (user 2026-07-25:
/// "zeige direkt an, wie sich der Effekt auf die einzelnen Levels auswirkt —
/// wieviel produziert ein Holzproduktionsgebäude auf Lvl 4 oder 8").
///
/// Authoring a level curve blind was the problem: `value` is only the LEVEL-1
/// figure, and what a level-8 building really yields depends on three separate
/// rules (explicit levelSteps, a per-effect levelFactor, or the global
/// +50%/level curve) — plus the fact that a few types are not level-scaled at
/// runtime at all. This block states the result outright, per level.
///
/// It computes through the SAME model the app loads (BuildingEffect.fromJson /
/// WorkshopRole.fromJson) and mirrors each type's real call site:
///  * `valueAtLevel` — production, expedition, housing, xp, healSlots, breeding,
///    queueSlots, buildSlots, trade (all read via BuildingDef.effectAt(level));
///  * `value × levelScaleExplicit` — resource, expeditionSlots, heal: they stay
///    FLAT unless the author sets a per-level %, exactly how the controller
///    reads them (resourceBonus / expeditionSlotBonus / healReduction);
///  * workshop — slots from slotSteps, output per stat point from levelScale.
///
/// If one of those call sites changes, this preview has to change with it.
class _LevelPreview extends StatefulWidget {
  final Map<String, dynamic> effect;
  final int maxLevel;

  /// The resources this building stores — a store post previews one line per
  /// entry, since it has one dial per entry (user 2026-07-30).
  final List<String> storageKeys;

  const _LevelPreview({
    required this.effect,
    required this.maxLevel,
    this.storageKeys = const [],
  });

  /// Worker stat the "fully staffed" workshop line assumes — EDITABLE (user
  /// 2026-07-25), because 30 is a guess and the whole point of the line is to
  /// answer "what does this yield with the monsters I actually have".
  ///
  /// Static so one edit applies to every workshop row and survives closing the
  /// form: it is a viewing lens, not content, so it deliberately isn't saved to
  /// the def. Reset per test via [debugSetPreviewStat].
  static double refStat = 30;

  /// Which rarity the breeder-post rows are shown for — the base durations are
  /// per rarity, so the line has to name one. Same lens contract as [refStat].
  static CreatureRarity previewRarity = CreatureRarity.rare;

  @override
  State<_LevelPreview> createState() => _LevelPreviewState();
}

/// Test hook: restores the shared preview stat so one test can't leak its lens
/// into the next.
@visibleForTesting
void debugSetPreviewStat(double v) => _LevelPreview.refStat = v;

/// Test hook for the breeding preview's rarity lens — see [debugSetPreviewStat].
@visibleForTesting
void debugSetPreviewRarity(CreatureRarity r) => _LevelPreview.previewRarity = r;

class _LevelPreviewState extends State<_LevelPreview> {
  late final TextEditingController _statCtrl =
      TextEditingController(text: _fmt(_LevelPreview.refStat));

  Map<String, dynamic> get effect => widget.effect;
  int get maxLevel => widget.maxLevel;
  List<String> get storageKeys => widget.storageKeys;
  double get _refStat => _LevelPreview.refStat;

  @override
  void dispose() {
    _statCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final type = effect['type'] as String? ?? '';
    // Every level the def really has (user 2026-07-26). The old clamp at 20
    // hid the tail of a longer building's curve — the same silent truncation
    // effectiveSlots did at 10.
    final levels = [for (var l = 1; l <= math.max(1, maxLevel); l++) l];

    final rows = <Widget>[];
    if (type == 'workshop') {
      final role = WorkshopRole.fromJson(effect);
      rows.add(_chipRow(
        'Monster-Slots',
        levels,
        (l) => '${effectiveSlots(role, l)}',
      ));
      rows.addAll(_workshopRows(role, levels));
      // A post pays XP just for being held, at the settlement-wide work rate
      // (user 2026-07-30) — stated here because this is where the author asks
      // "what does a monster get out of this post?", and the rate itself is not
      // editable on this screen any more. Training says its own rate above.
      if (role.resource != WorkshopRole.kTraining) {
        rows.add(_chipRow(
          'XP je Monster (Arbeit)',
          levels,
          (l) => '${_fmt(workXpPerHourAt(l))} XP/h',
        ));
        rows.add(_note('The same in EVERY building with a work post — one rate '
            'in Species budget → XP → "Arbeit", not a per-building number.'));
      }
    } else if (type == 'bonus') {
      rows.add(_note('Level-independent — this bonus is the same size whatever '
          'level the building is on.'));
    } else if (BuildingEffect.paletteTypes.contains(type)) {
      final e = BuildingEffect.fromJson(effect);
      final scaled = _isLevelScaled(type);
      rows.add(_chipRow(
        buildingEffectLabel(type),
        levels,
        // EXACTLY the runtime's own reader (buildingEffectValueAt): a flat
        // type still honours an explicit ladder, and a preview that ignored
        // one would have shown a Scout Post granting its level-1 slot at every
        // level (user 2026-07-29).
        (l) => formatBuildingEffect(
          type,
          e.key,
          scaled || e.levelSteps.isNotEmpty
              ? e.valueAtLevel(l)
              : e.value * e.levelScaleExplicit(l),
        ),
      ));
      // Passive construction is points, like a builder's stat — so it gets the
      // same "what does that DO" line the staffed role has (user 2026-07-26).
      if (type == 'production' && e.key == WorkshopRole.kConstruction) {
        rows.add(_chipRow(
          'Build time',
          levels,
          (l) => _timeCut(e.valueAtLevel(l)),
        ));
        rows.add(_note(_buildCutNote));
      }
      if (!scaled && e.levelFactor == null && e.levelSteps.isEmpty) {
        rows.add(_note('The game does NOT scale this type per level on its own. '
            'Enter a "Growth per level (%)" if it should grow.'));
      } else if (scaled && e.levelSteps.isEmpty && e.levelFactor == null) {
        rows.add(_note('Default curve +50 % per level (level L = value × '
            '(1 + 0.5·(L−1))) — override with "Growth per level (%)".'));
      }
    } else {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: ShapeDecoration(color: FoE.panelDark, shape: FoE.facet(radius: 8, side: BorderSide(color: FoE.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Effect per level',
                style: FoE.label(size: 12).copyWith(color: FoE.gold)),
            const SizedBox(height: 6),
            ...rows,
          ],
        ),
      ),
    );
  }

  /// What a WORKSHOP role really does at each level, in the unit the player
  /// feels (user 2026-07-26: "zeige, um wieviel Prozent das breeding
  /// beschleunigt wird, dann muss es nicht umgerechnet werden").
  ///
  /// Only the stockpile roles produce "N units/h". The others feed a SYSTEM:
  /// the same stat × mult × level figure is a fraction off a duration, a
  /// fraction off a price, or a build-speed factor — printing it with a "/h"
  /// suffix stated a number nobody could act on. Each branch below mirrors its
  /// real call site (SettlementController.breedingPower / healReduction /
  /// tradeDiscount / expeditionBonuses / buildRatePerHour / craftRatePerHour),
  /// so if one of those changes, the matching branch has to change with it.
  List<Widget> _workshopRows(WorkshopRole role, List<int> levels) {
    // The one figure every stat-driven role is built from: a full house of
    // monsters at the reference stat.
    double power(int l) =>
        effectiveSlots(role, l) * role.mult * role.levelScale(l) * _refStat;
    // TWO things grow per level, and only one of them is visible as a slot
    // count (user 2026-07-26: "weshalb ist L2 420 und nicht 280?"). The second
    // is this factor on each worker's output — spelled out per level, because
    // an unstated ×1.5 makes the whole row look wrong.
    final scale = _chipRow(
      'Level factor (yield per worker)',
      levels,
      (l) => '×${_fmt(role.levelScale(l))}',
    );
    final calc = _note('Maths: slots × ${_fmt(role.mult)} × level factor × '
        'stat ${_fmt(_refStat)}'
        '${role.levelFactor == null ? ' · level factor = the default '
            '+50 %/level, changeable via "Growth per level (%)" '
            '(0 = flat)' : ''}'
        ' — adjust the stat above to run your real monsters through it.');

    switch (role.resource) {
      case WorkshopRole.kTraining:
        return [
          _chipRow('XP per monster', levels,
              (l) => '${_fmt(kTrainingXpPerHour)} XP/h'),
          _note('Training slots produce nothing — every stationed monster '
              'earns XP, whatever its stat and level. That is '
              '${_fmtHours(xpToNextLevel(10) / kTrainingXpPerHour)} per level '
              'at Lv 10 (era 1). Rate in Species budget → XP.'),
        ];

      case WorkshopRole.kConstruction:
        // An ordinary role since 2026-07-26 — mult and level both count, and
        // the mult IS the "Bau-Punkte pro Statpunkt" dial. Only the unit is its
        // own: points, which buy a percent off the build time.
        return [
          scale,
          _chipRow(
            'Build points (fully staffed)',
            levels,
            (l) => _fmt(power(l)),
            trailing: _statField(role),
          ),
          _chipRow('Build time', levels, (l) => _timeCut(power(l))),
          _note(_buildCutNote),
          calc,
        ];

      // The two breeder posts are the same machine on different clocks (user
      // 2026-07-26), so one branch — it just reads the duration belonging to
      // THIS building's phase.
      case WorkshopRole.kBreeding:
      case WorkshopRole.kHatching:
        final cfg = kSpeciesBalance.of(_LevelPreview.previewRarity);
        final mating = role.resource == WorkshopRole.kBreeding;
        final base = mating ? cfg.breedHours : cfg.hatchHours;
        return [
          scale,
          _chipRow('${mating ? 'Paarungs' : 'Brüt'}-Power (voll besetzt)',
              levels, (l) => _fmt(power(l)), trailing: _statField(role)),
          _chipRow('Time saved', levels,
              (l) => workshopRoleEffect(role.resource, power(l))),
          _chipRow(
            mating ? '💞 Mating time' : '🐣 Incubation time',
            levels,
            (l) => _fmtHours(breedingHours(base, power(l))),
            trailing: _rarityField(),
          ),
          _note('Base ${_fmtHours(base)} for '
              '${_LevelPreview.previewRarity.label} — change it in '
              'Species budget → Breeding. No ceiling, but it flattens: '
              '−50 % at power ${_fmt(kBreedingK)}, −80 % at '
              '${_fmt(kBreedingK * 4)}, −90 % at ${_fmt(kBreedingK * 9)}.'),
          calc,
        ];

      // ONE post, one dial per PART (user 2026-07-29, both posts 2026-07-30) —
      // so one row per part, each read through the role's own formula with the
      // stat that part amplifies. Same wording as the single-purpose posts,
      // because they end up in the very same buckets.
      case WorkshopRole.kExpedition:
      case WorkshopRole.kCaravan:
        double partPower(String part, int l) =>
            effectiveSlots(role, l) *
            (role.mults[part] ?? 0) *
            role.levelScale(l) *
            _refStat;
        return [
          scale,
          for (final (i, part) in role.parts.entries.indexed)
            _chipRow(
              '${workshopRoleEmoji(part.value)} '
              '${workshopRoleName(part.value)} · '
              '${WorkshopRole.combinedPartStat(part.key).label}',
              levels,
              (l) => workshopRoleEffect(part.value, partPower(part.key, l)),
              // The lens belongs on the first row only — it is one stat box
              // for all of them, which is exactly what the note below says.
              trailing: i == 0 ? _statField(role) : null,
            ),
          _note('Travel has no cap — each point helps less than the last, and '
              'a trip never reaches zero. Carry and goods add up plainly.'),
          _note('Maths per part: slots × ITS dial × level factor × the stat '
              'above. The preview runs every part at the same reference stat; '
              'in play each reads its own, so one monster can be strong on one '
              'count and weak on another.'),
        ];

      // The civil-service posts all read the same way: one percentage, its own
      // ceiling. The wording and the clamps come from the shared vocabulary, so
      // this preview can't drift from what the building dialog tells the player.
      // A STORE post (user 2026-07-30): ONE ROW PER RESOURCE, because it has one
      // dial per resource. The number is a COUNT of units — not a percentage
      // like the amplifiers below and not a rate like a production post.
      case WorkshopRole.kStorageRoom:
        double roomFor(String res, int l) =>
            effectiveSlots(role, l) *
            role.storageMultFor(res) *
            role.levelScale(l) *
            _refStat;
        return [
          scale,
          if (storageKeys.isEmpty)
            _chipRow(workshopRoleName(role.resource)!, levels,
                (l) => workshopRoleEffect(role.resource, power(l)),
                trailing: _statField(role))
          else
            for (final res in storageKeys)
              _chipRow(
                '🏚 ${kGoodsDefs[res]?.name ?? res}',
                levels,
                (l) => workshopRoleEffect(role.resource, roomFor(res, l)),
                trailing: res == storageKeys.first ? _statField(role) : null,
              ),
          _note(storageKeys.isEmpty
              ? 'This building stores nothing, so the post has no ceiling to '
                  'raise. Add a storage effect and a dial per resource appears.'
              : 'Room a FULL house of logisticians adds, on top of each '
                  'resource\'s own ceiling. Each line has its own dial above.'),
          // NOT the shared `calc` note: it prints the flat `mult`, which here is
          // only the fallback for a resource without its own dial.
          _note('Maths per line: slots × that resource\'s dial × level factor × '
              'stat ${_fmt(_refStat)}.'),
        ];

      case WorkshopRole.kHealSpeed:
      case WorkshopRole.kTradeRate:
      case WorkshopRole.kExpCarry:
      case WorkshopRole.kExpGoods:
      case WorkshopRole.kExpTravel:
        return [
          scale,
          _chipRow(workshopRoleName(role.resource)!, levels,
              (l) => workshopRoleEffect(role.resource, power(l)),
              trailing: _statField(role)),
          if (role.resource == WorkshopRole.kHealSpeed)
            _note('Capped at −90 %, together with the building\'s heal effect.')
          else if (role.resource == WorkshopRole.kTradeRate)
            _note('Capped at −${(kMaxTradeDiscount * 100).round()} %, together '
                'with the building\'s trade effect.')
          else if (role.resource == WorkshopRole.kExpTravel ||
              role.resource == WorkshopRole.kCarTravel)
            // No ceiling since 2026-07-29 (user: "expeditions soll kein cap bei
            // 60% haben") — the hyperbola approaches an instant trip without
            // ever arriving, so the note describes the shape, not a wall.
            _note('No cap — each point helps less than the last, and a trip '
                'never reaches zero.'),
          calc,
        ];

      case WorkshopRole.kCrafting:
        return [
          scale,
          _chipRow('Craft seconds', levels, (l) => '${_fmt(power(l))}/h',
              trailing: _statField(role)),
          _chipRow('Craft time', levels, (l) => _timeCut(power(l) / 3600)),
          _note('−0 % = an item takes exactly the time it is authored with; '
              'that costs 3600 craft seconds/h.'),
          calc,
        ];

      case WorkshopRole.kLegendaryBoost:
        return [
          _chipRow('Produktions-Bonus (voll besetzt)', levels,
              (l) => '+${_fmt(role.slots * role.mult * 100)} %'),
          _note('Only LEGENDARIES count, and their stats do not — the bonus '
              'does NOT grow with the building level (only the slots do). '
              'It multiplies the building\'s worker-free production.'),
        ];

      default:
        return [
          scale,
          _chipRow('Per stat point', levels,
              (l) => '${_fmt(role.mult * role.levelScale(l))}/h'),
          _chipRow('Fully staffed at stat', levels,
              (l) => '${_fmt(power(l))} ${role.resource}/h',
              trailing: _statField(role)),
          calc,
        ];
    }
  }

  /// Whether the runtime reads this type through effectAt(level) — i.e. whether
  /// the level curve applies by default. The three exceptions read effectEntry
  /// and multiply by levelScaleExplicit, which is 1.0 unless a factor is set.
  static bool _isLevelScaled(String type) => !kFlatEffectTypes.contains(type);

  /// The rarity the breeding rows are read for — a lens, exactly like
  /// [_statField], and inline in the label row for the same reason.
  Widget _rarityField() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('for', style: FoE.dim(size: 10)),
      const SizedBox(width: 4),
      SizedBox(
        height: 30,
        child: DropdownButton<CreatureRarity>(
          key: const Key('previewRarity'),
          value: _LevelPreview.previewRarity,
          isDense: true,
          underline: const SizedBox.shrink(),
          dropdownColor: FoE.panelDark,
          style: FoE.label(size: 12).copyWith(color: FoE.goldBright),
          items: [
            for (final r in CreatureRarity.values)
              if (rarityCanBreed(r))
                DropdownMenuItem(value: r, child: Text(r.label)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _LevelPreview.previewRarity = v);
          },
        ),
      ),
    ],
  );

  /// The editable reference stat. Narrow and inline in the label row: it is a
  /// knob on the PREVIEW, not a field of the def, so it must not look like one
  /// of the effect's own inputs.
  ///
  /// It CARRIES ITS OWN CAPTION, naming the role's stat (user 2026-07-26:
  /// "Heildauer 30 — sind das nicht die Statpunkte?"). Unlabelled and glued to
  /// the row title, the box read as the row's value instead of as the input
  /// those values are computed from.
  Widget _statField(WorkshopRole role) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // A combined post applies this ONE box to all three of its parts, each of
      // which reads a different stat in play — so it must not name just one.
      Text(
        'at ${role.isCombined ? 'every stat' : role.stat.label}',
        style: FoE.dim(size: 10),
      ),
      const SizedBox(width: 4),
      SizedBox(
        width: 58,
        height: 30,
        child: TextField(
          key: const Key('previewStat'),
          controller: _statCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          textAlign: TextAlign.center,
          style: FoE.label(size: 12).copyWith(color: FoE.goldBright),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          ),
          onChanged: (s) {
            final v = double.tryParse(s);
            // An empty or half-typed field keeps the last usable value rather
            // than collapsing every chip to 0 mid-keystroke.
            if (v == null || v <= 0) return;
            setState(() => _LevelPreview.refStat = v);
          },
        ),
      ),
    ],
  );

  /// One label plus a wrapped run of `L<level> value` chips. [trailing] hangs a
  /// control (the stat field) off the label without stealing a whole row.
  Widget _chipRow(
    String label,
    List<int> levels,
    String Function(int) value, {
    Widget? trailing,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailing == null)
              Text(label, style: FoE.dim(size: 10))
            else
              Row(
                children: [
                  Text(label, style: FoE.dim(size: 10)),
                  const SizedBox(width: 6),
                  trailing,
                ],
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final l in levels) _chip(l, value(l))],
            ),
          ],
        ),
      );

  Widget _chip(int level, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: ShapeDecoration(color: FoE.panelMid, shape: FoE.facet(radius: 6, side: BorderSide(color: FoE.border))),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('L$level', style: FoE.dim(size: 9).copyWith(color: FoE.textMuted)),
        const SizedBox(width: 5),
        Text(value, style: FoE.label(size: 12).copyWith(color: FoE.parchment)),
      ],
    ),
  );

  Widget _note(String text) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(text, style: FoE.dim(size: 10)),
  );

  /// What a count of BUILD POINTS is worth, stated the way every other duration
  /// effect in this editor is: as the cut it takes off the authored time (user
  /// 2026-07-26 — "nicht Bau-Tempo Beschleuniger, sondern um wieviel Prozent
  /// wird die Bauzeit reduziert, wie bei anderen Menüs auch").
  ///
  /// Never negative anymore: zero points is the floor and means the authored
  /// time exactly, so no staffing can make a build take LONGER than its def
  /// says (user 2026-07-26).
  static String _timeCut(double points) =>
      '−${_fmt(buildTimeCut(points) * 100)} %';

  /// The one explanation both construction rows carry — the staffed role and
  /// the building's own passive `construction` effect are the same points in
  /// the same pot, so they must not describe themselves differently.
  static final String _buildCutNote =
      '0 points = the building takes exactly its authored build time; '
      'every point cuts into that. ${_fmt(kBuildPointsForHalfTime)} points '
      '= −50 %, ${_fmt(buildPointsForCut(0.8)!)} = −80 %, '
      '${_fmt(buildPointsForCut(0.9)!)} = −90 % — flattening, but with NO '
      'ceiling, and never below 0 seconds. A building\'s passive points and '
      'stationed builders count exactly the same.';

  /// A duration in the unit that reads best: minutes under an hour, days past
  /// two — the same scale the creature sheet uses for its XP estimate.
  static String _fmtHours(double h) {
    if (!h.isFinite) return '∞';
    if (h < 1) return '${(h * 60).round()}m';
    if (h < 48) return '${_fmt(h)}h';
    return '${_fmt(h / 24)}d';
  }

  /// Compact number: no trailing .0, at most one decimal.
  static String _fmt(double v) {
    if (v.abs() >= 100) return v.round().toString();
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.round().toString() : r.toString();
  }
}
