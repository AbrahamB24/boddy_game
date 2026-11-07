import 'package:flutter/material.dart' hide Text;

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/snack.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/recess_bar.dart';
import '../creatures/egg_detail_screen.dart';
import '../creatures/models/breeding_job.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/models/species_def.dart';
import '../creatures/services/breeding_controller.dart';
import '../creatures/services/creature_power.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/widgets/creature_family.dart' show CreatureAvatar;
import '../creatures/widgets/egg_card.dart';
import '../common/widgets/monster_tile_grid.dart' show kMonsterTileAspect;
import 'data/item_definitions.dart';
import 'data/resource_icons.dart';
import 'services/new_items.dart';
import 'settlement_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/ui/game_text.dart';

/// The bag: everything the settlement owns that isn't a resource.
///
/// It had no home before (user 2026-07-25: "meine Items sind aktuell nicht
/// sichtbar, ich muss auf diese zugreifen können vom Homescreen aus") — items
/// only surfaced where they happened to be usable: the Workshop's recipe chips,
/// a monster's detail screen, the battle menu. So a potion you owned was
/// invisible until the exact moment you needed it, and there was no way to ask
/// "what have I got?".
///
/// Heals and revives can be used straight from here. Everything else says where
/// it is used instead of offering a button that would need a fight or a hunt to
/// mean anything.
///
/// ── A SCREEN, NOT A SHEET (user 2026-07-31: "bag soll ein eigener screen
/// sein") ──
///
/// A place you go to and come back from is a page: the bag has three drawers,
/// opens monster pickers and pushes an egg's own screen on top of itself.
///
/// ── "Raster und Detail" (user 2026-09-19, picked from ten layouts) ──
///
/// Left, the drawer's contents as TILES; right, the chosen one in full. The
/// picker step that heals and revives used to need — pick the item, then pick the
/// monster from a list that opened under it — is gone: the monsters that could
/// take the chosen item stand in the detail, each with its own "Use".
Future<void> openBag(BuildContext context) =>
    pushMenu<void>(context, const BagScreen());

/// The bag's DRAWERS (user 2026-07-27: "mache beim Bag verschiedene
/// Reiter/Kategorien wie Ressourcenpakete (kommen noch)/Items/Eggs etc.").
///
/// One flat list mixed eggs in with the consumables and would have mixed
/// resource packs in on top — three things you reach for at completely
/// different moments. A drawer each keeps every list short enough to read at a
/// glance.
enum _BagTab {
  items('Items'),
  eggs('Eggs'),
  packs('Resource packs');

  final String label;
  const _BagTab(this.label);
}

class BagScreen extends StatefulWidget {
  const BagScreen({super.key});

  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = SettlementController();
  final _creatures = CreaturesController();
  final _breeding = BreedingController();

  /// The item id (or pack id) whose pack is being opened right now — a pack's
  /// button is dead while its own redeem is in flight.
  String? _using;

  /// What is chosen in each drawer; null (or an id that is gone) = the first.
  String? _selItem;
  String? _selPack;
  String? _selEgg;

  // A real TabBar/TabController (user 2026-09-06: "Oben die Reiter genau gleich
  // gestalten wie bei Management").
  late final TabController _tabs = TabController(
    length: _BagTab.values.length,
    vsync: this,
  );

  _BagTab get _tab => _BagTab.values[_tabs.index];

  /// A frozen copy of NewItems' counts, taken the instant this screen opens
  /// — BEFORE [NewItems.markSeen] clears the live map (user 2026-08-29:
  /// "Wenn ich einmal den entsprechenden Reiter geöffnet habe, dann soll
  /// der Counter für neue Items verschwinden. Dafür die entsprechenden
  /// Items markieren, welche neu sind und wieviele"). The QuickPad badge
  /// reads the LIVE map, so it goes to 0 right away; this screen keeps
  /// showing what WAS new, off its own snapshot, for as long as it's open.
  late final Map<String, int> _newSnapshot;

  @override
  void initState() {
    super.initState();
    _newSnapshot = NewItems().snapshot();
    NewItems().markSeen();
    // The eggs drawer reads BreedingController's list, which is loaded lazily.
    // Both halves matter (user 2026-07-27): [load] fetches the rows if no
    // screen has yet, and [refreshEggs] promotes a mating that finished while
    // the bag was being opened.
    _breeding.addListener(_onChanged);
    _creatures.addListener(_onChanged);
    _breeding.load().then((_) => _breeding.refreshEggs());
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _breeding.removeListener(_onChanged);
    _creatures.removeListener(_onChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Monsters an out-of-battle item can actually be spent on: hurt ones for a
  /// heal, K.O.'d ones for a revive — the most hurt first. Listing the rest
  /// would only offer taps that get refused.
  List<CreatureInstance> _targetsFor(ItemDef def) {
    final list = switch (def.kind) {
      ItemKind.heal =>
        _creatures.creatures.where((c) => !c.isKo && c.hp < c.maxHp).toList(),
      ItemKind.revive => _creatures.creatures.where((c) => c.isKo).toList(),
      _ => <CreatureInstance>[],
    };
    double frac(CreatureInstance c) => c.maxHp <= 0 ? 0 : c.hp / c.maxHp;
    list.sort((a, b) => frac(a).compareTo(frac(b)));
    return list;
  }

  Future<void> _use(ItemDef def, CreatureInstance c) async {
    final err = await _creatures.useItemOn(def.id, c);
    if (!mounted) return;
    if (err != null) {
      Feel.deny();
      context.snack(err, error: true);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bag = _ctrl.items;
    // Unknown ids (an item deleted in Dev Mode while still in a bag) are shown
    // raw rather than dropped — silently swallowing a possession is worse.
    // A pack IS an item (see item_definitions), so the two drawers split one
    // bag rather than reading two.
    final packs =
        bag.entries.where((e) => e.value > 0 && isPackId(e.key)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final entries =
        bag.entries.where((e) => e.value > 0 && !isPackId(e.key)).toList()
          ..sort((a, b) {
            final an = kItemDefs[a.key]?.name ?? a.key;
            final bn = kItemDefs[b.key]?.name ?? b.key;
            return an.compareTo(bn);
          });
    // EGGS ARE ITEMS (user 2026-07-26: "Bitte ei als Item bezeichnen und somit
    // in den Bag senden können"). They are not kItemDefs rows and cannot be —
    // an egg carries the two parents its child's genes are rolled from, which a
    // fungible id→count bag has nowhere to put. So the bag lists them as their
    // own kind of item: one entry each, named by species.
    final eggs = _breeding.eggs;
    final itemCount = entries.fold<int>(0, (s, e) => s + e.value);
    final packCount = packs.fold<int>(0, (s, e) => s + e.value);
    final total = itemCount + eggs.length;

    return MenuScaffold(
      // No icon (user 2026-07-27) — the newer menus name themselves in words.
      title: 'Bag',
      trailing: Text(
        total == 0 ? 'empty' : '$total item${total > 1 ? 's' : ''}',
        style: FoE.value(size: 11).copyWith(color: kBoxInkSoft),
      ),
      // The drawer list and its chosen item ARE different Gebiete (user
      // 2026-09-29, "Trennlinien und Zonen gemischt", app-wide) — browsing
      // versus the one thing you are looking at in full — so the detail
      // side gets a [zoneBox] of its own. (MenuScaffold is the one card
      // now — no [pageCard] here.)
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // LEFT: the drawers and the chosen drawer's tiles.
            Expanded(
              flex: 14,
              child: Column(
                children: [
                  _tabBar({
                    _BagTab.items: itemCount,
                    _BagTab.eggs: eggs.length,
                    _BagTab.packs: packCount,
                  }),
                  Container(
                    height: 1,
                    color: CreamPalette.tan.withValues(alpha: 0.55),
                  ),
                  Expanded(
                    child: switch (_tab) {
                      _BagTab.items => _tileDrawer(
                        entries,
                        _selItem,
                        (id) => setState(() => _selItem = id),
                        'No items.\n\nCraft them in the Workshop, buy them at '
                        'the Trade Center, or win them on the map.',
                      ),
                      _BagTab.eggs => _eggDrawer(eggs),
                      _BagTab.packs => _tileDrawer(
                        packs,
                        _selPack,
                        (id) => setState(() => _selPack = id),
                        'No resource packs.\n\nThey are won on the map — every '
                        'battle pays one — and open into your stores from here.',
                      ),
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // RIGHT: the chosen one, in full.
            Expanded(
              flex: 11,
              child: zoneBox(
                padding: EdgeInsets.zero,
                child: switch (_tab) {
                  _BagTab.items => _itemDetail(_chosen(entries, _selItem)),
                  _BagTab.eggs => _eggDetail(_chosenEgg(eggs)),
                  _BagTab.packs => _itemDetail(_chosen(packs, _selPack)),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The chosen entry of a drawer — the first when nothing (or something that
  /// is gone) is chosen.
  MapEntry<String, int>? _chosen(List<MapEntry<String, int>> list, String? id) {
    if (list.isEmpty) return null;
    for (final e in list) {
      if (e.key == id) return e;
    }
    return list.first;
  }

  BreedingJob? _chosenEgg(List<BreedingJob> eggs) {
    if (eggs.isEmpty) return null;
    for (final j in eggs) {
      if (j.id == _selEgg) return j;
    }
    return eggs.first;
  }

  /// The drawers, with what each one holds. A count on the tab means you never
  /// have to open an empty one to find that out.
  Widget _tabBar(Map<_BagTab, int> counts) => TabBar(
    controller: _tabs,
    labelColor: kBoxInk,
    unselectedLabelColor: kBoxInkSoft,
    indicatorColor: CreamPalette.goldDeep,
    // Scrollable: "Resource packs" plus a count is wide enough on its own to
    // push a fixed-width split into wrapping on a narrow phone.
    isScrollable: true,
    tabAlignment: TabAlignment.center,
    tabs: [
      for (final t in _BagTab.values)
        Tab(text: counts[t]! > 0 ? '${t.label} ${counts[t]}' : t.label),
    ],
  );

  Widget _empty(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft, height: 1.4),
      ),
    ),
  );

  // ── The tiles ────────────────────────────────────────────
  Widget _tileDrawer(
    List<MapEntry<String, int>> list,
    String? selectedId,
    ValueChanged<String> onSelect,
    String emptyMessage,
  ) {
    if (list.isEmpty) return _empty(emptyMessage);
    final chosen = _chosen(list, selectedId)!.key;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 104,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _itemTile(
        list[i].key,
        list[i].value,
        list[i].key == chosen,
        onSelect,
      ),
    );
  }

  /// One item as a square tile: its glyph, its name, how many, and a gold dot
  /// when some arrived since the bag was last opened. The chosen one wears an
  /// amber rim.
  Widget _itemTile(
    String id,
    int count,
    bool selected,
    ValueChanged<String> onSelect,
  ) {
    final def = kItemDefs[id];
    final newCount = _newSnapshot[id] ?? 0;
    return Pressable(
      onTap: () => onSelect(id),
      child: Container(
        decoration: raisedTile(radius: 14).copyWith(
          border: selected
              ? Border.all(color: CreamPalette.gold, width: 3)
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    def?.emoji ?? '❔',
                    style: const TextStyle(fontSize: 32, height: 1.1),
                  ),
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      def?.name ?? id,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: FoE.label(size: 11).copyWith(
                        color: kBoxInk,
                        fontWeight: FontWeight.w400,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              right: 8,
              child: Text(
                '×$count',
                style: FoE.value(size: 12).copyWith(color: kBoxAccent),
              ),
            ),
            if (newCount > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.rectangle,
                    color: CreamPalette.gold,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── The eggs ─────────────────────────────────────────────
  /// THE EGGS, AS THE HATCHERY SHOWS THEM (user 2026-07-27: "Nimm das Design
  /// von den Eggs der Hatchery fuer den Bag. Es muessen nur die Eier, Power und
  /// name angezeigt werden") — [EggCard] is the tile the Hatchery's slot and its
  /// picker already use. A tap CHOOSES the egg; the detail opens it.
  Widget _eggDrawer(List<BreedingJob> eggs) {
    if (eggs.isEmpty) {
      return _empty(
        'No eggs.\n\nPair two monsters in the Breeding Hut — the egg they lay '
        'lands here.',
      );
    }
    final chosen = _chosenEgg(eggs)!.id;
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 110,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: kMonsterTileAspect,
      ),
      itemCount: eggs.length,
      itemBuilder: (_, i) => EggCard(
        job: eggs[i],
        selected: eggs[i].id == chosen,
        onTap: () => setState(() => _selEgg = eggs[i].id),
      ),
    );
  }

  Widget _eggDetail(BreedingJob? job) {
    if (job == null) {
      return _empty('Nothing to show — no eggs yet.');
    }
    final species = kSpeciesDefs[job.speciesId];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 96,
                height: 96 / kMonsterTileAspect,
                child: EggCard(job: job),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${species?.name ?? job.speciesId} egg',
                      style: FoE.title(size: 18).copyWith(color: kBoxInk),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.hasChildGenes
                          ? '⚡ ${genePower(job.childBase)}'
                          : '⚡ ?',
                      style: FoE.value(size: 15).copyWith(color: kBoxAccent),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The child inside was rolled when the egg was laid — two eggs of a '
            'species are not the same egg. Open it to see the stats and to put '
            'it in the Hatchery.',
            style: FoE.dim(
              size: 11.5,
            ).copyWith(color: kBoxInkSoft, height: 1.4),
          ),
          const Spacer(),
          Pressable(
            // A TAP OPENS THE EGG (user 2026-07-27): the stats are what you came
            // to look at, and the trip to the Hatchery is one button further on.
            onTap: () => pushMenu(context, EggDetailScreen(eggId: job.id)),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              alignment: Alignment.center,
              decoration: goldButton(),
              child: Text(
                'Open egg',
                style: FoE.title(size: 15).copyWith(color: goldButtonInk()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── The detail ───────────────────────────────────────────
  /// The chosen item, in full: what it is and how many, then what can be done
  /// with it — the monsters that could take a potion (each with its own "Use"),
  /// a pack's "Open" with what it costs, or where an item is used.
  Widget _itemDetail(MapEntry<String, int>? entry) {
    if (entry == null) {
      return _empty('Nothing chosen yet.');
    }
    final id = entry.key;
    final count = entry.value;
    final def = kItemDefs[id];
    // How many of THIS item arrived since the bag was last opened (user
    // 2026-08-29: "die entsprechenden Items markieren, welche neu sind und
    // wieviele") — off the frozen snapshot, not NewItems' live map.
    final newCount = _newSnapshot[id] ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                def?.emoji ?? '❔',
                style: const TextStyle(fontSize: 44, height: 1),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def?.name ?? id,
                      style: FoE.title(size: 18).copyWith(color: kBoxInk),
                    ),
                    Text(
                      def?.description ??
                          "This item no longer exists in the content — it can't be used.",
                      style: FoE.dim(size: 12).copyWith(
                        color: def == null ? CreamPalette.warn : kBoxInkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '×$count',
                    style: FoE.value(size: 20).copyWith(color: kBoxAccent),
                  ),
                  if (newCount > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CreamPalette.gold.withValues(alpha: 0.32),
                        borderRadius: vr(6),
                        border: Border.all(color: CreamPalette.goldDeep),
                      ),
                      child: Text(
                        '+$newCount new',
                        style: FoE.dim(size: 9).copyWith(
                          color: kBoxAccent,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (def != null)
            Expanded(
              child: def.kind == ItemKind.resourcePack
                  ? _redeemBlock(def)
                  : def.kind == ItemKind.heal || def.kind == ItemKind.revive
                  ? _targetsBlock(def)
                  : _whereUsedBlock(def),
            ),
        ],
      ),
    );
  }

  /// Who could take a heal or a revive: the monsters that need it, the most hurt
  /// first, each with its HP and its own "Use".
  Widget _targetsBlock(ItemDef def) {
    final targets = _targetsFor(def);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CreamHeading(
          title: targets.isEmpty ? 'Use' : 'Use · ${targets.length}',
        ),
        const SizedBox(height: 10),
        Expanded(
          child: targets.isEmpty
              ? Align(
                  alignment: Alignment.topLeft,
                  child: Text(
                    def.kind == ItemKind.heal
                        ? 'Nobody is hurt right now.'
                        : 'Nobody is K.O. right now.',
                    style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: targets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (_, i) => _targetRow(def, targets[i]),
                ),
        ),
      ],
    );
  }

  Widget _targetRow(ItemDef def, CreatureInstance c) {
    final frac = c.maxHp <= 0 ? 0.0 : (c.hp / c.maxHp).clamp(0.0, 1.0);
    return Container(
      height: 46,
      padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
      decoration: raisedTile(radius: 12),
      child: Row(
        children: [
          // The monster itself, not a coloured bar (user 2026-09-28).
          CreatureAvatar.of(c, size: 36, showHp: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c.isKo ? '💀 ' : ''}${c.displayName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.value(size: 12.5).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 3),
                RecessBar(
                  value: frac,
                  color: frac < 0.5 ? CreamPalette.warn : CreamPalette.gold,
                  height: 7,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${c.hp}/${c.maxHp}',
            style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
          ),
          const SizedBox(width: 10),
          Pressable(
            onTap: () => _use(def, c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: goldButton(),
              child: Text(
                'Use',
                style: FoE.label(size: 12).copyWith(color: goldButtonInk()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Where an item that can't be spent from the bag actually gets used. Says it
  /// plainly instead of showing a dead button.
  Widget _whereUsedBlock(ItemDef def) => Align(
    alignment: Alignment.topLeft,
    child: Text(
      _whereUsed(def),
      style: FoE.label(size: 13).copyWith(color: kBoxAccent, height: 1.4),
    ),
  );

  String _whereUsed(ItemDef def) => switch (def.kind) {
    ItemKind.buff => '⚔️ Used during a battle (Items menu)',
    ItemKind.catchBoost => '🪤 Used on a hunt encounter',
    ItemKind.expeditionYield => '🎒 Used when sending an expedition',
    ItemKind.breedSpeed => '🥚 Used on a running breeding or hatching job',
    ItemKind.cureStatus ||
    ItemKind.cureDebuffs => '⚔️ Used during a battle (Items menu)',
    _ => '',
  };

  /// A package is spent HERE and on nothing in particular — no monster to pick,
  /// no fight to be in. So it gets a button, and the text says what it costs
  /// (user 2026-07-30): going over the ceiling pauses that resource's production
  /// until the stores drain back under, and that is worth knowing BEFORE the tap.
  Widget _redeemBlock(ItemDef def) {
    final id = def.resourceId ?? '';
    final cap = _ctrl.storageCaps[id];
    final held = _ctrl.resources?.asMap[id] ?? 0;
    final after = held + def.magnitude;
    final over = cap != null && after > cap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CreamHeading(title: 'Opens into'),
        const SizedBox(height: 10),
        Text(
          '${def.magnitude.toStringAsFixed(0)} ${resourceEmoji(id)} ${resourceName(id)}',
          style: FoE.title(size: 20).copyWith(color: kBoxInk),
        ),
        const SizedBox(height: 8),
        Text(
          over
              ? 'That is ${after.toStringAsFixed(0)} — over the '
                    '${cap.toStringAsFixed(0)} ceiling, so no '
                    '${resourceName(id).toLowerCase()} is produced until it '
                    'drains back under.'
              : 'It fits into the store.',
          style: FoE.dim(size: 12).copyWith(
            color: over ? CreamPalette.warn : kBoxInkSoft,
            height: 1.4,
            fontWeight: over ? FontWeight.w400 : null,
          ),
        ),
        const Spacer(),
        Pressable(
          onTap: _using == def.id ? null : () => _redeem(def),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            alignment: Alignment.center,
            decoration: goldButton(active: _using != def.id),
            child: Text(
              over ? 'Open anyway' : 'Open',
              style: FoE.title(
                size: 15,
              ).copyWith(color: goldButtonInk(active: _using != def.id)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _redeem(ItemDef def) async {
    setState(() => _using = def.id);
    final err = await _ctrl.redeemPack(def.id);
    if (!mounted) return;
    setState(() => _using = null);
    if (err != null) {
      Feel.deny();
      context.snack(err, error: true);
      return;
    }
    Feel.collect();
    context.snack('${def.emoji} ${def.name} unpacked.');
  }
}
