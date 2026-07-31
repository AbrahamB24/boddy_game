import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/foe_theme.dart';
import '../../creatures/models/area.dart' show kAreaDefs;
import '../../creatures/models/path_node.dart';
import '../../creatures/models/species_def.dart' show SpeciesDef, kSpeciesDefs;
import '../../creatures/services/overworld_path.dart'
    show enemyCountForBattle, enemyLevelForBattle, kBattlesPerEra;
import '../data/building_definitions.dart' show BuildingDef, kBuildingDefs;
import '../data/goods_definitions.dart' show kGoodsDefs;
import '../data/item_definitions.dart'
    show
        ItemDef,
        isPackId,
        kItemDefs,
        packEmoji,
        packId,
        packSizesFor,
        parsePackId;
import '../data/resource_icons.dart';
import '../services/game_defs_controller.dart';
import 'dev_theme.dart';

// Create/edit one battle NODE on the linear path (user 2026-07-25). Same
// trusted-single-author dev pattern as AreaDefForm; saved to Supabase
// `path_nodes` via GameDefsController.savePathNode. A node with no enemies falls
// back to the formula; rewards drive building/feature unlocks + expansions.
class PathNodeForm extends StatefulWidget {
  final PathNode? existing;

  /// Order to seed a NEW node with (max + 1), so it lands at the end of the path.
  final int nextOrder;
  const PathNodeForm({super.key, this.existing, this.nextOrder = 1});

  @override
  State<PathNodeForm> createState() => _PathNodeFormState();
}

class _EnemyDraft {
  String speciesId;
  int level;

  /// The row's own Level field. A CONTROLLER rather than an initialValue,
  /// because the level is written from two directions since 2026-07-31: you type
  /// it here, or the Gesamtlevel above spreads it. A field that only seeds itself
  /// once would keep showing the old number after a spread.
  final TextEditingController levelCtrl;

  _EnemyDraft({required this.speciesId, required this.level})
      : levelCtrl = TextEditingController(text: '$level');

  /// Set the level AND what the field shows. Used by the spread; typing goes the
  /// other way (the field is already right, only [level] needs to follow).
  void setLevel(int v) {
    level = v;
    if (levelCtrl.text != '$v') levelCtrl.text = '$v';
  }

  void dispose() => levelCtrl.dispose();
}

class _ItemDraft {
  String itemId;
  int count;
  _ItemDraft({required this.itemId, required this.count});
}

class _PathNodeFormState extends State<PathNodeForm> {
  bool _saving = false;

  late String _id;
  late int _order;
  late String _name;
  String? _areaId;
  late bool _isBoss;
  late List<_EnemyDraft> _enemies;

  /// The node's TOTAL level — the one difficulty number (user 2026-07-30:
  /// "nicht die level der Monster einzeln eingeben, sondern den Gesamtlevel").
  /// Spread over the enemies by [_spreadTotal]; the per-monster figures are a
  /// RESULT now, shown on each row but no longer typed.
  late int _totalLevel;

  /// The Gesamtlevel field. Also two-directional: typing here spreads DOWN to
  /// the monsters, editing one monster sums back UP into it.
  late final TextEditingController _totalCtrl;
  late List<_ItemDraft> _items;
  late Set<String> _buildings;
  late int _expansions;
  String _buildingFilter = '';

  /// ONE era filter for every picker on this form (user 2026-07-26: "gib mir
  /// einen filter für die Belohnungen und gegner nach ära"). null = show all.
  ///
  /// One knob rather than four, because a node belongs to exactly one era: when
  /// you author battle 7 you want era-I species, era-I buildings and era-I
  /// goods, and setting that three times is three chances to forget one.
  ///
  /// It NEVER hides something already on the node — a picked species/item that
  /// falls outside the filter still shows, or its dropdown would lose its own
  /// value and silently rewrite the node on the next save.
  int? _eraFilter;

  bool get _isNew => widget.existing == null;

  /// The era a node sits in: its area's battle stage when it has one, else the
  /// band its [order] falls in. This is what the filter starts on, so opening a
  /// node lands on its own era with no clicking.
  int get _nodeEra {
    final stage = _areaId == null ? null : kAreaDefs[_areaId]?.battleStage;
    if (stage != null) return stage;
    return ((_order - 1) ~/ kBattlesPerEra) + 1;
  }

  bool _inEra(int? era) => _eraFilter == null || era == null || era == _eraFilter;


  /// A building's first buildable era. An empty eraIds means "every era", so it
  /// is never filtered out (null = always shown).
  int? _eraOfBuilding(BuildingDef d) =>
      d.eraIds.isEmpty ? null : d.startEraOrder;

  /// A resource's era comes from the goods table; wood/stone/gold are era I.
  int _eraOfResource(String id) => kGoodsDefs[id]?.eraOrder ?? 1;

  /// An item has no era of its own — its RECIPE does. The latest good it
  /// consumes is the era it belongs to; a recipe with no concrete ingredients
  /// is billed against whatever the settlement has, so it counts as era I.
  int _eraOfItem(ItemDef d) => d.ingredients.keys
      .map(_eraOfResource)
      .fold<int>(1, (a, b) => a > b ? a : b);

  /// The items the filter currently offers — also what "+ Item" starts a new
  /// row on, and what decides whether that button is shown at all.
  List<ItemDef> get _itemsInEra =>
      kItemDefs.values.where((d) => _inEra(_eraOfItem(d))).toList()
        ..sort((a, b) => a.name.compareTo(b.name));


  @override
  void initState() {
    super.initState();
    final d = widget.existing;
    _order = d?.order ?? widget.nextOrder;
    _id = d?.id ?? 'node_$_order';
    _name = d?.name ?? '';
    _areaId = d?.areaId;
    _isBoss = d?.isBoss ?? false;
    _enemies = [
      for (final e in d?.enemies ?? const <PathEnemy>[])
        _EnemyDraft(speciesId: e.speciesId, level: e.level),
    ];
    // Read back off the node it was spread across, so opening a node shows the
    // number it was authored with rather than resetting it.
    _totalLevel = _enemies.isEmpty
        // A node with no authored enemies is worth what the FORMULA would have
        // spawned there — so "+ Enemy" on a fresh node lands on the curve
        // instead of at level 1, and the number you overwrite is a real one.
        ? enemyLevelForBattle(_order) * enemyCountForBattle(_order)
        : _enemies.fold<int>(0, (sum, e) => sum + e.level);
    _totalCtrl = TextEditingController(text: '$_totalLevel');
    _items = [
      for (final e in (d?.rewards.items ?? const {}).entries)
        _ItemDraft(itemId: e.key, count: e.value),
    ];
    _buildings = {...?d?.rewards.buildings};
    _expansions = d?.rewards.expansions ?? 0;
    // Open on the node's OWN era — that is what you are authoring, and it makes
    // the filter useful without a click. "Alle" is one dropdown entry away.
    _eraFilter = _nodeEra;
  }

  @override
  void dispose() {
    for (final e in _enemies) {
      e.dispose();
    }
    _totalCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_id.trim().isEmpty) {
      _snack('id is required');
      return;
    }
    setState(() => _saving = true);
    final node = PathNode(
      id: _id.trim(),
      order: _order,
      name: _name.trim(),
      areaId: _areaId,
      isBoss: _isBoss,
      enemies: [
        for (final e in _enemies)
          if (e.speciesId.isNotEmpty)
            PathEnemy(speciesId: e.speciesId, level: e.level.clamp(1, 99999)),
      ],
      rewards: PathRewards(
        items: {
          for (final i in _items)
            if (i.itemId.isNotEmpty && i.count > 0) i.itemId: i.count,
        },
        buildings: _buildings.toList(),
        expansions: _expansions,
      ),
    );
    try {
      await GameDefsController().savePathNode(node);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Save failed: $e');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDeleteDialog(
      context,
      title: 'Delete node?',
      message: 'This removes "$_id" from the path for every player.',
    );
    if (!ok) return;
    try {
      await GameDefsController().deletePathNode(_id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _snack('Delete failed: $e');
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));


  // ── Zufällige Gegner (user 2026-07-30) ─────────────────────
  // "für beim Pfad im dev menü die Option ein, dass ich die Monster zufällig
  // hinzufügen kann. Dabei soll die Anzahl der Monster gleichbleiben, wie ich
  // sie angegeben habe."
  //
  // Filling forty nodes by hand means forty dropdowns; the interesting decision
  // is HOW MANY fight here and at what level, not which three names. So the
  // count and the levels are yours and the roll only replaces the SPECIES.

  final _rng = math.Random();

  /// How many enemies the roll should produce. Starts at whatever the node
  /// already has, so the first press re-rolls exactly what is there.
  late int _randomCount = _enemies.isEmpty ? 3 : _enemies.length;

  /// Rolls [_randomCount] enemies from the era-filtered pool.
  ///
  /// The rules live in rollPathEnemies (path_node.dart) — count kept, levels
  /// kept, species distinct while the pool allows.
  /// Hands [_totalLevel] out over the current enemies, ±20 %.
  ///
  /// Called whenever the total or the NUMBER of monsters changes — those are the
  /// only two things the level distribution depends on.
  void _spreadTotal() {
    if (_enemies.isEmpty) return;
    final levels = spreadLevels(
      total: _totalLevel,
      count: _enemies.length,
      rng: _rng,
    );
    for (var i = 0; i < _enemies.length; i++) {
      _enemies[i].setLevel(levels[i]);
    }
  }

  /// The other direction (user 2026-07-31: "bei edit node, will ich die
  /// einzlnen Level trotzdem bearbeiten können"): a hand-set level makes the
  /// total follow, so the two numbers can never contradict each other. The
  /// spread is a STARTING POINT — the last word is still yours.
  void _sumUp() {
    _totalLevel = _enemies.fold<int>(0, (sum, e) => sum + e.level);
    if (_totalCtrl.text != '$_totalLevel') _totalCtrl.text = '$_totalLevel';
  }

  void _rollEnemies(List<SpeciesDef> pool) {
    // Balanced against the WHOLE path (user 2026-07-30: "Die Verteilung soll
    // etwa gleichmässig sein") — a single node's dice should reach for what the
    // campaign is short of, not roll blind and add to a pile.
    final usage = {
      for (final e in pathSpeciesDistribution(pathNodesInOrder()).entries)
        e.key: e.value.total,
    };
    final rolled = rollPathEnemies(
      poolIds: [for (final s in pool) s.id],
      count: _randomCount,
      keepLevels: [for (final e in _enemies) e.level],
      rng: _rng,
      usage: usage,
    );
    if (rolled.isEmpty) return;
    setState(() {
      for (final e in _enemies) {
        e.dispose();
      }
      _enemies = [
        for (final e in rolled)
          _EnemyDraft(speciesId: e.speciesId, level: e.level),
      ];
      // The count may have changed with the roll, so the total is handed out
      // again — the node's difficulty is the total, not the sum of whatever the
      // dice happened to leave behind.
      _spreadTotal();
    });
  }

  Widget _randomRow(List<SpeciesDef> pool) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: pool.isEmpty ? null : () => _rollEnemies(pool),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              decoration: FoE.btn(active: pool.isNotEmpty),
              child: Text(
                '🎲 Zufällig aus ${pool.length} Arten',
                style: FoE.label(size: 13).copyWith(
                  color: pool.isEmpty ? FoE.textDim : Colors.white,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // The count is yours: the roll produces exactly this many, and a
        // re-roll keeps the levels that are already there.
        SizedBox(
          width: 92,
          child: _numRow(
            'Anzahl',
            _randomCount,
            onChanged: (v) => setState(
              () => _randomCount = v.toInt().clamp(1, 12),
            ),
          ),
        ),
      ],
    ),
  );


  // ── Pakete statt Ressourcen (user 2026-07-30) ──────────────
  // "«normale» Ressourcen gibt es nicht mehr als Belohnungen. Diese können
  // gelöscht werden. D.h ich will die Packete Anwählen. Bsp. 5x500 Wood etc."
  //
  // A package is an ITEM, so it could be authored in the item list below — but
  // picking "Wood Crate" out of fifty-odd entries is not what "5×500 Wood" reads
  // like. This row is the sentence itself: WHICH resource, WHICH size, HOW MANY.
  // It writes into the same `items` map; the split is only in the authoring.

  /// Everything else — potions, lures, revives.
  List<_ItemDraft> get _plainItems => [
    for (final i in _items)
      if (!isPackId(i.itemId)) i,
  ];

  /// Which resources a package may hold, filtered by the era like everything
  /// else on this form.
  List<String> get _packResourcesInEra => [
    for (final id in ['wood', 'stone', 'gold', ...kGoodsDefs.keys])
      if (_inEra(_eraOfResource(id))) id,
  ];

  void _setPack(_ItemDraft row, {String? resourceId, int? amount}) {
    final parts = parsePackId(row.itemId);
    final res = resourceId ?? parts?.resourceId ?? 'wood';
    final sizes = packSizesFor(res);
    // Changing the RESOURCE can land on a ladder that has no such rung (a
    // 5000-wood package has no fish equivalent), so it falls to the nearest one
    // rather than producing an id nothing defines.
    final wanted = amount ?? parts?.amount ?? sizes.first;
    final rung = sizes.contains(wanted)
        ? wanted
        : sizes.reduce((a, b) =>
            (a - wanted).abs() <= (b - wanted).abs() ? a : b);
    setState(() => row.itemId = packId(res, rung));
  }

  Widget _packRow(_ItemDraft row) {
    // Read off the ID, not the def — see parsePackId.
    final parts = parsePackId(row.itemId);
    final resourceId = parts?.resourceId ?? 'wood';
    final sizes = packSizesFor(resourceId);
    final amount = parts?.amount ?? sizes.first;
    final options = [
      for (final id in _packResourcesInEra) id,
      if (!_packResourcesInEra.contains(resourceId)) resourceId,
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: resourceId,
              isExpanded: true,
              dropdownColor: FoE.panelMid,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              decoration:
                  const InputDecoration(labelText: 'Resource', isDense: true),
              items: [
                for (final id in options)
                  DropdownMenuItem(
                    value: id,
                    child: Text('${resourceEmoji(id)} ${resourceName(id)}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) =>
                  v == null ? null : _setPack(row, resourceId: v),
            ),
          ),
          const SizedBox(width: 8),
          // The package IS its amount — the ladders differ per resource, so the
          // dropdown lists the real rungs rather than three generic names.
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<int>(
              initialValue: sizes.contains(amount) ? amount : sizes.first,
              isExpanded: true,
              dropdownColor: FoE.panelMid,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              decoration:
                  const InputDecoration(labelText: 'Package', isDense: true),
              items: [
                for (final a in sizes)
                  DropdownMenuItem(
                    value: a,
                    child: Text('${packEmoji(a)} $a',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => v == null ? null : _setPack(row, amount: v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: TextFormField(
              initialValue: '${row.count}',
              keyboardType: TextInputType.number,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              decoration:
                  const InputDecoration(labelText: '×', isDense: true),
              onChanged: (v) =>
                  setState(() => row.count = int.tryParse(v) ?? row.count),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                color: Colors.redAccent),
            onPressed: () => setState(() => _items.remove(row)),
          ),
        ],
      ),
    );
  }

  /// What the row adds up to, in the words the briefing will use.
  String _packSummary() {
    var total = 0.0;
    final per = <String, double>{};
    for (final i in _items) {
      final parts = parsePackId(i.itemId);
      if (parts == null) continue;
      final amount = parts.amount * i.count;
      per[parts.resourceId] = (per[parts.resourceId] ?? 0) + amount;
      total += amount;
    }
    if (total <= 0) return '';
    return per.entries
        .map((e) =>
            '${e.value.toStringAsFixed(0)} ${resourceEmoji(e.key)}')
        .join('   ');
  }

  @override
  Widget build(BuildContext context) {
    // Filtered, but never without the species this node already fights: a
    // dropdown whose value is missing from its own item list throws.
    // EVERY species, whatever the era filter says (user 2026-07-30: "Monster
    // werden keine Ära mehr haben in Zukunft"). The filter still governs
    // resources, items and buildings — those really do belong to an era — but a
    // monster is no longer tied to one, so hiding it here would only hide
    // content that is perfectly valid to fight in region I.
    //
    // (SpeciesDef.tier still exists and still decides which era's GOODS a
    // mating or a treatment is billed in — that is an economic fact about a
    // monster, not a statement about where it may appear.)
    final species = kSpeciesDefs.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final areas = kAreaDefs.values.toList()
      ..sort((a, b) => a.battleStage.compareTo(b.battleStage));
    return Theme(
      data: buildDevModeTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'New Node' : 'Edit Node',
              style: FoE.title(size: 16)),
          actions: [
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _delete,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _textRow('Id', _id,
                      enabled: _isNew, onChanged: (v) => _id = v),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _numRow('Order', _order,
                      onChanged: (v) => _order = v.toInt()),
                ),
              ],
            ),
            _textRow('Name (leer = "Battle N")', _name,
                onChanged: (v) => _name = v),
            _areaDropdown(areas),
            _checkboxRow('Boss (opens the next region/era)', _isBoss,
                (v) => setState(() => _isBoss = v)),
            const SizedBox(height: 12),
            _eraFilterDropdown(areas),
            const SizedBox(height: 16),

            _sectionLabel('Enemies (empty = formula: random species from the pool)'),
            const SizedBox(height: 8),
            // ONE difficulty number for the whole fight, spread over the
            // monsters (user 2026-07-30). Everything below reads it: adding a
            // monster, removing one and the dice all re-spread the same total,
            // so a node's strength only changes when you change THIS.
            TextFormField(
              controller: _totalCtrl,
              keyboardType: TextInputType.number,
              style: FoE.label(size: 15).copyWith(color: FoE.parchment),
              decoration: const InputDecoration(
                labelText: 'Gesamtlevel (verteilt auf alle Gegner, ±20 %)',
              ),
              onChanged: (v) {
                final parsed = int.tryParse(v);
                if (parsed == null) return;
                setState(() {
                  _totalLevel = parsed.clamp(0, 99999);
                  _spreadTotal();
                });
              },
            ),
            const SizedBox(height: 10),
            ..._enemies.map((e) => _enemyRow(e, species)),
            if (species.isEmpty)
              Text(
                kSpeciesDefs.isEmpty
                    ? 'No species defined yet (Dev Mode → Species).'
                    : 'No species in this era — set the filter to «All eras».',
                style: FoE.dim(size: 10).copyWith(color: Colors.redAccent),
              )
            else
              _addButton('+ Enemy', () {
                setState(() {
                  _enemies.add(_EnemyDraft(
                    speciesId: species.first.id,
                    level: 1,
                  ));
                  // A fourth monster does not make the node harder — it makes
                  // the same total thinner. Difficulty stays where the author
                  // put it.
                  _spreadTotal();
                });
              }),
            if (species.isNotEmpty) _randomRow(species),
            const SizedBox(height: 18),

            _sectionLabel('Rewards'),
            const SizedBox(height: 8),
            // PACKAGES, not raw resources (user 2026-07-30). A node pays out the
            // instant the battle ends, so a raw reward was worth whatever the
            // player's stores had room for; a package waits in the bag at full
            // value until it is opened.
            Row(
              children: [
                Expanded(
                  child: Text('Resource packages', style: FoE.dim(size: 11)),
                ),
                if (_packSummary().isNotEmpty)
                  Text(_packSummary(),
                      style: FoE.label(size: 11).copyWith(color: FoE.gold)),
              ],
            ),
            const SizedBox(height: 4),
            ..._items.where((i) => isPackId(i.itemId)).map(_packRow),
            _addButton('+ Package', () {
              final first = _packResourcesInEra.isEmpty
                  ? 'wood'
                  : _packResourcesInEra.first;
              // Starts on the SMALLEST rung: a reward that is too big is worse
              // than one that is too small, and the ladder is one tap away.
              setState(() => _items.add(_ItemDraft(
                    itemId: packId(first, packSizesFor(first).first),
                    count: 1,
                  )));
            }),
            const SizedBox(height: 12),
            Text('Items (dropped into the bag)', style: FoE.dim(size: 11)),
            const SizedBox(height: 4),
            ..._plainItems.map(_itemRow),
            if (_itemsInEra.isEmpty)
              Text(
                kItemDefs.isEmpty
                    ? 'No items defined yet (Dev Mode → Items).'
                    : 'No items in this era — set the filter to «All eras».',
                style: FoE.dim(size: 10).copyWith(color: Colors.redAccent),
              )
            else
              _addButton('+ Item', () {
                setState(() => _items.add(_ItemDraft(
                      itemId: _itemsInEra.first.id,
                      count: 1,
                    )));
              }),
            const SizedBox(height: 12),
            _numRow('Territory expansions (points)', _expansions,
                onChanged: (v) =>
                    setState(() => _expansions = v.toInt().clamp(0, 99))),
            const SizedBox(height: 12),
            Text('Unlock buildings', style: FoE.dim(size: 11)),
            const SizedBox(height: 6),
            _buildingPicker(),
            const SizedBox(height: 20),
            _saveButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _areaDropdown(List areas) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String?>(
      initialValue: kAreaDefs.containsKey(_areaId) ? _areaId : null,
      dropdownColor: FoE.panelMid,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: const InputDecoration(labelText: 'Region (area)'),
      items: [
        const DropdownMenuItem(value: null, child: Text('— derive from era —')),
        for (final a in areas)
          DropdownMenuItem(
            value: a.id as String,
            child: Text('${a.emoji} ${a.name} · S${a.battleStage}'),
          ),
      ],
      onChanged: (v) => setState(() => _areaId = v),
    ),
  );

  /// The one filter that narrows EVERY picker below: species, resources, items
  /// and buildings (user 2026-07-26). It changes nothing about the node — it is
  /// a lens on the lists, so switching it can never alter what is saved.
  ///
  /// Eras are named from the AREAS, since that is where a battle stage is
  /// authored; an era with no area still gets a numbered entry so a filter is
  /// never missing a step.
  Widget _eraFilterDropdown(List areas) {
    final stages = <int>{
      for (final a in areas) a.battleStage as int,
      _nodeEra,
    }.toList()
      ..sort();
    String label(int stage) {
      for (final a in areas) {
        if (a.battleStage == stage) return '${a.emoji} Era $stage · ${a.name}';
      }
      return 'Era $stage';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: DropdownButtonFormField<int?>(
        initialValue: stages.contains(_eraFilter) ? _eraFilter : null,
        isExpanded: true,
        dropdownColor: FoE.panelMid,
        style: FoE.label(size: 15).copyWith(color: FoE.parchment),
        decoration: const InputDecoration(
          labelText: 'Filter: era (pickers only — it does not change the node)',
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('All eras')),
          for (final s in stages)
            DropdownMenuItem(
              value: s,
              child: Text(label(s), overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => setState(() => _eraFilter = v),
      ),
    );
  }

  Widget _enemyRow(_EnemyDraft e, List species) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: FoE.panel(radius: 8),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: kSpeciesDefs.containsKey(e.speciesId)
                ? e.speciesId
                : (species.isEmpty ? null : species.first.id as String),
            isExpanded: true,
            dropdownColor: FoE.panelMid,
            style: FoE.label(size: 13).copyWith(color: FoE.parchment),
            decoration: const InputDecoration(labelText: 'Species', isDense: true),
            items: [
              for (final s in species)
                DropdownMenuItem(
                  value: s.id as String,
                  // The name carries the RARITY (user 2026-07-30) — picking an
                  // enemy without seeing whether it is a common or a legendary
                  // is picking blind.
                  child: Text(
                    '${s.element.emoji} ${s.name}',
                    overflow: TextOverflow.ellipsis,
                    style: FoE.label(size: 13)
                        .copyWith(color: speciesNameColor(s.id as String)),
                  ),
                ),
            ],
            onChanged: (v) => setState(() => e.speciesId = v ?? e.speciesId),
          ),
        ),
        const SizedBox(width: 8),
        // EDITABLE, and the Gesamtlevel above follows it (user 2026-07-31: "bei
        // edit node, will ich die einzlnen Level trotzdem bearbeiten können").
        // The spread hands out a sensible starting point; a boss's escort that
        // should be five levels under it is still a decision you make here.
        SizedBox(
          width: 66,
          child: TextFormField(
            controller: e.levelCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: FoE.label(size: 14).copyWith(color: FoE.gold),
            decoration: const InputDecoration(labelText: 'Lv', isDense: true),
            onChanged: (v) {
              final parsed = int.tryParse(v);
              if (parsed == null) return;
              // NOT clamped while typing — snapping a half-typed "0" up to 1
              // would fight anyone on their way to "10". Level 1 is enforced on
              // save, where it is the last word rather than an interruption.
              e.level = parsed;
              setState(_sumUp);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
          onPressed: () => setState(() {
            _enemies.remove(e);
            e.dispose();
            // The node keeps the difficulty it had — the survivors share it out
            // again (see [_spreadTotal]).
            _spreadTotal();
          }),
        ),
      ],
    ),
  );

  Widget _itemRow(_ItemDraft i) {
    // Packages are excluded here: they have their own row above, and fifty of
    // them would bury the six real items.
    final items = kItemDefs.values
        .where((d) =>
            !isPackId(d.id) && (d.id == i.itemId || _inEra(_eraOfItem(d))))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: FoE.panel(radius: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String>(
              initialValue: kItemDefs.containsKey(i.itemId)
                  ? i.itemId
                  : (items.isEmpty ? null : items.first.id),
              isExpanded: true,
              dropdownColor: FoE.panelMid,
              style: FoE.label(size: 13).copyWith(color: FoE.parchment),
              decoration: const InputDecoration(labelText: 'Item', isDense: true),
              items: [
                for (final d in items)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text('${d.emoji} ${d.name}',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => i.itemId = v ?? i.itemId),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: i.count.toString(),
              keyboardType: TextInputType.number,
              style: FoE.label(size: 14).copyWith(color: FoE.parchment),
              decoration: const InputDecoration(labelText: 'Count', isDense: true),
              onChanged: (v) => i.count = int.tryParse(v) ?? i.count,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
            onPressed: () => setState(() => _items.remove(i)),
          ),
        ],
      ),
    );
  }

  /// Every building this node can hand out — the LIVE Dev-Mode roster
  /// (`kBuildingDefs`), so exactly what you have defined is what you can pick.
  ///
  /// This list used to be cut off at 60 chips. With 84 pickable buildings that
  /// silently hid the last 24 — `trading_post`, `warehouse`, half the luxury
  /// works — INCLUDING ones already ticked on the node (user 2026-07-26: "Knoten
  /// 11 gibt das Trading center, dies wird mir jedoch nicht angezeigt und
  /// dadurch kann ich es nicht ändern"). A picker that hides the state it is
  /// meant to edit is worse than a long list, so nothing is dropped anymore and
  /// the ticked ones are pinned to the front where the search can't lose them.
  // ── Schon woanders vergeben (user 2026-07-31) ───────────────
  // "wenn ich ein Gebäude als Unlock buildings bei einem Knoten angewählt habe,
  // dann soll dies bei den anderen nicht mehr angezeigt werden, da es bereits
  // freigeschalten wurde oder wird."
  //
  // A building unlocks at the FIRST node that grants it (pathBuildingUnlockBattle
  // takes the minimum), so a second node granting the same one is a reward that
  // pays nothing — and eighty chips of which a dozen are already spoken for is a
  // list you cannot author against.
  //
  /// buildingId → the order of the earliest OTHER node that grants it.
  ///
  /// This node is skipped on purpose: unticking a chip must leave it pickable
  /// again, and the saved copy of this very node still lists it until you save.
  Map<String, int> _grantedElsewhere() {
    final out = <String, int>{};
    for (final n in kPathNodes.values) {
      if (n.id == _id) continue;
      for (final b in n.rewards.buildings) {
        final at = out[b];
        if (at == null || n.order < at) out[b] = n.order;
      }
    }
    return out;
  }

  Widget _buildingPicker() {
    final q = _buildingFilter.trim().toLowerCase();
    final elsewhere = _grantedElsewhere();
    bool matches(BuildingDef d) =>
        q.isEmpty ||
        d.name.toLowerCase().contains(q) ||
        d.id.toLowerCase().contains(q);

    final all = kBuildingDefs.values
        .where((d) => !d.isRoad && !d.isMainBuilding)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    // Anything already granted stays visible whatever the era filter says —
    // same rule as the dropdowns, and for the stronger reason here: a hidden
    // chip is a reward you cannot untick.
    final selected = all.where((d) => _buildings.contains(d.id)).toList();
    final rest = all
        .where((d) =>
            !_buildings.contains(d.id) &&
            !elsewhere.containsKey(d.id) &&
            matches(d) &&
            _inEra(_eraOfBuilding(d)))
        .toList();
    // Not offered, but findable: a SEARCH is a question, and "it is not here"
    // is a worse answer than "node 11 already gives it". Nothing shows until you
    // type — the point is a shorter list.
    final taken = q.isEmpty
        ? const <BuildingDef>[]
        : (all.where((d) =>
                !_buildings.contains(d.id) &&
                elsewhere.containsKey(d.id) &&
                matches(d)).toList());
    // Ids on the node whose def no longer exists: they still unlock nothing and
    // would otherwise be invisible AND unremovable. Show them so they can go.
    final orphans = _buildings.where((id) => !kBuildingDefs.containsKey(id));

    Widget chipFor(String id, String label) => _chip(
      label,
      _buildings.contains(id),
      () => setState(() => _buildings.contains(id)
          ? _buildings.remove(id)
          : _buildings.add(id)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          style: FoE.label(size: 13).copyWith(color: FoE.parchment),
          decoration: InputDecoration(
            // The count of what is actually OFFERED, not of the whole roster —
            // with an era filter on, the two differ and the roster number
            // would just look like a broken list.
            hintText: 'Search buildings… '
                '(${selected.length + rest.length} of ${all.length})',
            prefixIcon: const Icon(Icons.search, color: FoE.gold, size: 18),
            isDense: true,
          ),
          onChanged: (v) => setState(() => _buildingFilter = v),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final id in orphans) chipFor(id, '⚠ $id'),
            for (final d in selected) chipFor(d.id, d.name),
            for (final d in rest) chipFor(d.id, d.name),
            // Dim and dead: tapping it would author a reward that pays nothing,
            // because the earlier node already unlocked the building.
            for (final d in taken)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: FoE.panel(radius: 8),
                child: Text(
                  '${d.name} · Knoten ${elsewhere[d.id]}',
                  style: FoE.dim(size: 12),
                ),
              ),
          ],
        ),
        if (elsewhere.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${elsewhere.length} Gebäude sind schon an anderen Knoten '
                'vergeben und darum hier nicht aufgeführt'
                '${q.isEmpty ? ' (suchen zeigt, wo)' : ''}.',
            style: FoE.dim(size: 10),
          ),
        ],
      ],
    );
  }

  // ── Small shared widgets (same style as AreaDefForm) ──
  Widget _sectionLabel(String text) =>
      Text(text, style: FoE.label(size: 14).copyWith(color: FoE.gold));

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: FoE.btn(active: selected),
          child: Text(label,
              style: FoE.label(size: 12)
                  .copyWith(color: selected ? Colors.white : FoE.parchment)),
        ),
      );

  Widget _addButton(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      alignment: Alignment.center,
      decoration: FoE.panel(radius: 8),
      child: Text(label, style: FoE.label(size: 13).copyWith(color: FoE.gold)),
    ),
  );

  Widget _checkboxRow(String label, bool value, ValueChanged<bool> onChanged) =>
      GestureDetector(
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(value ? Icons.check_box : Icons.check_box_outline_blank,
                  color: value ? FoE.gold : FoE.textDim),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: FoE.label(size: 14).copyWith(color: FoE.parchment)),
              ),
            ],
          ),
        ),
      );

  Widget _saveButton() => SizedBox(
    width: double.infinity,
    child: GestureDetector(
      onTap: _saving ? null : _save,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: FoE.btn(active: true),
        alignment: Alignment.center,
        child: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: FoE.goldBright),
              )
            : Text('Save', style: FoE.label(size: 14).copyWith(color: Colors.white)),
      ),
    ),
  );

  Widget _textRow(
    String label,
    String value, {
    bool enabled = true,
    required ValueChanged<String> onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: value,
      enabled: enabled,
      style: FoE.label(size: 15).copyWith(color: FoE.parchment),
      decoration: InputDecoration(labelText: label),
      onChanged: onChanged,
    ),
  );

  Widget _numRow(
    String label,
    num value, {
    required ValueChanged<num> onChanged,
  }) => TextFormField(
    initialValue: value.toInt().toString(),
    keyboardType: TextInputType.number,
    style: FoE.label(size: 15).copyWith(color: FoE.parchment),
    decoration: InputDecoration(labelText: label),
    onChanged: (v) {
      final parsed = int.tryParse(v);
      if (parsed != null) onChanged(parsed);
    },
  );
}
