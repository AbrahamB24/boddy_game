import 'package:flutter/material.dart';

import '../../core/ui/feel.dart';
import 'data/resource_icons.dart';
import '../../core/theme/foe_theme.dart';
import '../creatures/egg_detail_screen.dart';
import '../creatures/models/breeding_job.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/services/breeding_controller.dart';
import '../creatures/widgets/egg_card.dart';
import '../creatures/services/creatures_controller.dart';
import 'data/item_definitions.dart';
import 'settlement_controller.dart';
import '../common/widgets/parchment_page.dart';
import 'widgets/parchment_sheet.dart';
import 'widgets/scroll_paper.dart' show parchmentButton, parchmentButtonInk;

/// The bag: everything the settlement owns that isn't a resource.
///
/// It had no home before (user 2026-07-25: "meine Items sind aktuell nicht
/// sichtbar, ich muss auf diese zugreifen können vom Homescreen aus") — items
/// only surfaced where they happened to be usable: the Workshop's recipe chips,
/// a monster's detail screen, the battle menu. So a potion you owned was
/// invisible until the exact moment you needed it, and there was no way to ask
/// "what have I got?".
///
/// Heals and revives can be used straight from here (pick the item, pick the
/// monster). Everything else says where it is used instead of offering a button
/// that would need a fight or a hunt to mean anything.
///
/// ── A SCREEN, NOT A SHEET (user 2026-07-31: "bag soll ein eigener screen
/// sein") ──
///
/// It was a bottom sheet covering two thirds of the map. A sheet is for a quick
/// answer you dismiss — but the bag has three drawers, opens monster pickers and
/// pushes an egg's own screen on top of itself, and every one of those either
/// fought the drag-to-dismiss or came back to a sheet at a different height. A
/// place you go to and come back from is a page.
Future<void> openBag(BuildContext context) => Navigator.push(
  context,
  MaterialPageRoute(builder: (_) => const BagScreen()),
);

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
  // Nothing produces these yet (user: "kommen noch"). The drawer exists so the
  // shape of the bag is already right when they land, and so an empty one is an
  // answer ("none yet") rather than a missing feature.
  packs('Resource packs');

  final String label;
  const _BagTab(this.label);
}

class BagScreen extends StatefulWidget {
  const BagScreen({super.key});

  @override
  State<BagScreen> createState() => _BagScreenState();
}

class _BagScreenState extends State<BagScreen> {
  final _ctrl = SettlementController();
  final _creatures = CreaturesController();
  final _breeding = BreedingController();

  /// The item whose target picker is open; null = the plain list.
  String? _using;

  _BagTab _tab = _BagTab.items;

  @override
  void initState() {
    super.initState();
    // The eggs drawer reads BreedingController's list, which is loaded lazily.
    // Both halves matter (user 2026-07-27): [load] fetches the rows if no
    // screen has yet, and [refreshEggs] promotes a mating that finished while
    // the bag was being opened — without it a laid egg only appears in the
    // drawer after some other screen ticked.
    _breeding.addListener(_onBreedingChanged);
    _breeding.load().then((_) => _breeding.refreshEggs());
  }

  @override
  void dispose() {
    _breeding.removeListener(_onBreedingChanged);
    super.dispose();
  }

  void _onBreedingChanged() {
    if (mounted) setState(() {});
  }

  void _say(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: FoE.label(size: 12)),
      backgroundColor: FoE.panelDark,
    ),
  );

  /// Monsters an out-of-battle item can actually be spent on: hurt ones for a
  /// heal, K.O.'d ones for a revive. Listing the rest would only offer taps
  /// that get refused.
  List<CreatureInstance> _targetsFor(ItemDef def) => switch (def.kind) {
    ItemKind.heal =>
      _creatures.creatures.where((c) => !c.isKo && c.hp < c.maxHp).toList(),
    ItemKind.revive => _creatures.creatures.where((c) => c.isKo).toList(),
    _ => const [],
  };

  Future<void> _use(ItemDef def, CreatureInstance c) async {
    final err = await _creatures.useItemOn(def.id, c);
    if (!mounted) return;
    setState(() => _using = null);
    _say(err ?? '${def.emoji} ${def.name} used on ${c.displayName}.');
  }

  @override
  Widget build(BuildContext context) {
    final bag = _ctrl.items;
    // Unknown ids (an item deleted in Dev Mode while still in a bag) are shown
    // raw rather than dropped — silently swallowing a possession is worse.
    // A pack IS an item (see item_definitions), so the two drawers split one
    // bag rather than reading two: without this, every pack you own would sit in
    // both, and "Items 12" would count things the Items drawer cannot use.
    final packs = bag.entries.where((e) => e.value > 0 && isPackId(e.key)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final entries = bag.entries
        .where((e) => e.value > 0 && !isPackId(e.key))
        .toList()
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
    final total = entries.fold<int>(0, (s, e) => s + e.value) + eggs.length;

    return ParchmentPage(
      // No icon (user 2026-07-27) — the newer menus name themselves in words.
      title: 'Bag',
      trailing: Text(
        total == 0 ? 'empty' : '$total item${total > 1 ? 's' : ''}',
        style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkFaint),
      ),
      child: Column(
        children: [
          _tabBar({
            _BagTab.items: entries.fold<int>(0, (s, e) => s + e.value),
            _BagTab.eggs: eggs.length,
            _BagTab.packs: packs.fold<int>(0, (s, e) => s + e.value),
          }),
          Expanded(
            child: ListView(
              // The page's own side padding, so the drawers line up with every
              // other page's content and clear the meander bordure.
              padding: EdgeInsets.fromLTRB(
                ParchmentPage.kParchmentPagePad,
                8,
                ParchmentPage.kParchmentPagePad,
                20 + MediaQuery.of(context).viewPadding.bottom,
              ),
              children: switch (_tab) {
                _BagTab.items =>
                  entries.isEmpty
                      ? [
                          _emptyDrawer(
                            'No items.\n\nCraft them in the Workshop, buy '
                            'them at the Trade Center, or win them on the map.',
                          ),
                        ]
                      : [for (final e in entries) _itemCard(e.key, e.value)],
                _BagTab.eggs =>
                  eggs.isEmpty
                      ? [
                          _emptyDrawer(
                            'No eggs.\n\nPair two monsters in the Breeding '
                            'Hut — the egg they lay lands here.',
                          ),
                        ]
                      : [_eggGrid(eggs)],
                // PACKS EXIST NOW (2026-07-30, with the campaign rewards). The
                // drawer still said they were coming — it was written before
                // them, and a bag that denies holding what it holds is worse
                // than no drawer at all.
                _BagTab.packs =>
                  packs.isEmpty
                      ? [
                          _emptyDrawer(
                            'No resource packs.\n\nThey are won on the map — '
                            'every battle pays one — and open into your stores '
                            'from here.',
                          ),
                        ]
                      : [for (final e in packs) _itemCard(e.key, e.value)],
              },
            ),
          ),
        ],
      ),
    );
  }

  /// THE EGGS, AS THE HATCHERY SHOWS THEM (user 2026-07-27: "Nimm das Design
  /// von den Eggs der Hatchery fuer den Bag. Es muessen nur die Eier, Power und
  /// name angezeigt werden").
  ///
  /// They were list ROWS: an egg glyph, the species name plus `Egg`, a line
  /// about the Hatchery's slots, and a button. Four things per row, and not one
  /// of them told two eggs of a species apart - which is the only question a
  /// bag of eggs raises, because the child inside each was frozen when it was
  /// laid (migration 0027).
  ///
  /// [EggCard] is the tile the Hatchery's slot and its picker already use: the
  /// shell in its type's colour with the hatchling's silhouette showing
  /// through, the child's gene sum as its power, and the species name. Three to
  /// a row, the Monsters grid's own cell shape.
  Widget _eggGrid(List<BreedingJob> eggs) => GridView.builder(
    padding: const EdgeInsets.only(top: 4, bottom: 8),
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 0.70,
    ),
    itemCount: eggs.length,
    itemBuilder: (_, i) => EggCard(
      job: eggs[i],
      // A TAP OPENS THE EGG (user 2026-07-27); it no longer jumps straight to
      // the Hatchery. The stats are what you came to look at, and the trip to
      // the Hatchery is one button further on - where the slot count and the
      // incubation time are already on screen.
      //
      // The bag closes first. It is a sheet over the settlement, and leaving it
      // open behind a route means backing out of the egg lands on a stale list
      // - this one changes the moment an egg is placed.
      onTap: () {
        final id = eggs[i].id;
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => EggDetailScreen(eggId: id)),
        );
      },
    ),
  );

  /// The drawers, with what each one holds. A count on the tab means you never
  /// have to open an empty one to find that out.
  Widget _tabBar(Map<_BagTab, int> counts) => Padding(
    padding: const EdgeInsets.fromLTRB(30, 4, 30, 6),
    // Scrolls: "Resource packs" alone is wide, and a fourth drawer would push
    // the row off a narrow phone.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final t in _BagTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() {
                  _tab = t;
                  // A picker left open in another drawer would keep listing
                  // targets for an item this one does not show.
                  _using = null;
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: parchmentButton(active: _tab == t),
                  child: Text(
                    counts[t]! > 0 ? '${t.label} ${counts[t]}' : t.label,
                    style: FoE.label(
                      size: 12,
                    ).copyWith(color: parchmentButtonInk(active: _tab == t)),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _emptyDrawer(String message) => Padding(
    padding: const EdgeInsets.all(28),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: FoE.dim(size: 12).copyWith(color: ParchmentSheet.inkSoft),
    ),
  );

  Widget _itemCard(String id, int count) {
    final def = kItemDefs[id];
    if (def == null) {
      return _card([
        Row(
          children: [
            const Text('❔', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                id,
                style: FoE.title(size: 13).copyWith(color: ParchmentSheet.ink),
              ),
            ),
            Text(
              '×$count',
              style: FoE.value(size: 13).copyWith(color: ParchmentSheet.ink),
            ),
          ],
        ),
        Text(
          'This item no longer exists in the content — it can\'t be used.',
          style: FoE.dim(size: 10).copyWith(color: FoE.danger),
        ),
      ]);
    }

    final picking = _using == id;
    final targets = _targetsFor(def);

    return _card([
      Row(
        children: [
          Text(def.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.name,
                  style: FoE.title(
                    size: 13,
                  ).copyWith(color: ParchmentSheet.ink),
                ),
                Text(
                  def.description,
                  style: FoE.dim(
                    size: 10,
                  ).copyWith(color: ParchmentSheet.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '×$count',
            style: FoE.value(size: 14).copyWith(color: ParchmentSheet.accent),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (def.kind == ItemKind.resourcePack)
        _redeemRow(def)
      else if (def.kind == ItemKind.heal || def.kind == ItemKind.revive)
        _useRow(def, targets, picking)
      else
        Text(
          _whereUsed(def),
          style: FoE.dim(size: 10).copyWith(color: ParchmentSheet.accent),
        ),
      if (picking) ...[
        const SizedBox(height: 6),
        for (final c in targets) _targetTile(def, c),
      ],
    ]);
  }

  Widget _useRow(
    ItemDef def,
    List<CreatureInstance> targets,
    bool picking,
  ) => Row(
    children: [
      Expanded(
        child: Text(
          targets.isEmpty
              ? def.kind == ItemKind.heal
                    ? 'Nobody is hurt right now'
                    : 'Nobody is K.O. right now'
              : '${targets.length} monster${targets.length > 1 ? 's' : ''} '
                    'could take it',
          style: FoE.dim(size: 10).copyWith(color: ParchmentSheet.inkSoft),
        ),
      ),
      GestureDetector(
        onTap: targets.isEmpty
            ? null
            : () => setState(() => _using = picking ? null : def.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: parchmentButton(active: targets.isNotEmpty && !picking),
          child: Text(
            picking ? 'Cancel' : 'Use',
            style: FoE.label(size: 12).copyWith(
              color: parchmentButtonInk(active: targets.isNotEmpty && !picking),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _targetTile(ItemDef def, CreatureInstance c) => GestureDetector(
    onTap: () => _use(def, c),
    child: Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: ParchmentSheet.card,
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${c.isKo ? '💀 ' : ''}${c.displayName}',
              style: FoE.value(size: 12).copyWith(color: ParchmentSheet.ink),
            ),
          ),
          Text(
            '${c.hp}/${c.maxHp} HP',
            style: FoE.dim(size: 10).copyWith(color: ParchmentSheet.inkSoft),
          ),
        ],
      ),
    ),
  );

  /// Where an item that can't be spent from the bag actually gets used. Says it
  /// plainly instead of showing a dead button.
  String _whereUsed(ItemDef def) => switch (def.kind) {
    ItemKind.buff => '⚔️ Used during a battle (Items menu)',
    ItemKind.catchBoost => '🪤 Used on a hunt encounter',
    ItemKind.expeditionYield => '🎒 Used when sending an expedition',
    ItemKind.breedSpeed => '🥚 Used on a running breeding or hatching job',
    _ => '',
  };

  /// A package is spent HERE and on nothing in particular — no monster to pick,
  /// no fight to be in. So it gets a button, and the button says what it costs
  /// (user 2026-07-30): going over the ceiling pauses that resource's production
  /// until the stores drain back under, and that is worth knowing BEFORE the tap.
  Widget _redeemRow(ItemDef def) {
    final id = def.resourceId ?? '';
    final cap = _ctrl.storageCaps[id];
    final held = _ctrl.resources?.asMap[id] ?? 0;
    final after = held + def.magnitude;
    final over = cap != null && after > cap;
    return Row(
      children: [
        Expanded(
          child: Text(
            over
                ? 'Opens to ${after.toStringAsFixed(0)} — over the '
                      '${cap.toStringAsFixed(0)} ceiling, so no '
                      '${resourceName(id).toLowerCase()} is produced until it '
                      'drains back under'
                : 'Opens into ${def.magnitude.toStringAsFixed(0)} '
                      '${resourceEmoji(id)} ${resourceName(id)}',
            style: FoE.dim(size: 10).copyWith(
              color: over ? FoE.danger : ParchmentSheet.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _using == def.id ? null : () => _redeem(def),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: parchmentButton(active: true),
            child: Text(
              'Open',
              style: FoE.label(size: 12)
                  .copyWith(color: parchmentButtonInk(active: true)),
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
      _say(err);
      return;
    }
    Feel.collect();
    _say('${def.emoji} ${def.name} opened — '
        '+${def.magnitude.toStringAsFixed(0)} '
        '${resourceEmoji(def.resourceId ?? '')}');
  }

  Widget _card(List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: ParchmentSheet.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}
