import '../../creatures/models/creature_enums.dart' show CreatureStat;
import 'goods_definitions.dart';

// ── Craftable / tradeable items ─────────────────────────────
// Things your monsters MAKE (Workshop) or you BUY (Trade Center) rather than
// gather: potions, revives, battle buffs, catch lures, expedition kits.
//
// ── Recipes name CONCRETE luxury ingredients (user 2026-07-25) ──
// A recipe's [ingredients] is a map of specific goods → amount (e.g. {wine: 2,
// herbs: 1}). This gives the 16 luxury goods a real purpose — each is the
// ingredient for particular items — instead of collapsing into one fungible
// "supply" currency. [supplyCost] survives only as the legacy/abstract fallback
// for recipes that don't name ingredients (billed against the era's goods).

/// What an item DOES. [magnitude] is the kind-specific number (see each case).
enum ItemKind {
  /// Restore [magnitude] HP to one creature (out of battle or, if battleUsable,
  /// mid-fight).
  heal,

  /// Revive a K.O.'d creature to [magnitude] fraction of its max HP (0.5 = 50%).
  revive,

  /// Battle buff: +[magnitude] fraction to [buffStat] for
  /// [kSelfBuffDuration] of the user's own turns.
  ///
  /// NOT "for the rest of the fight", which is what this said until 2026-07-30 —
  /// buffs have always ticked down like any other, and the engine has one
  /// duration for them (status_effects.dart). The magnitude is honoured since
  /// the same day; before that it was ignored entirely.
  buff,

  /// Eases the NEXT capture — widens the QTE window by [magnitude] fraction.
  catchBoost,

  /// +[magnitude] fraction to an expedition's haul.
  expeditionYield,

  /// Cuts a breeding/hatching timer by [magnitude] fraction.
  breedSpeed,

  /// A sealed PACKAGE of one resource (user 2026-07-30: "ich brauche noch
  /// Ressourcenpakete für die Belohnung … Die Pakete kommen ins Inventar und
  /// können dann eingelöst werden").
  ///
  /// [ItemDef.resourceId] says which resource and [ItemDef.magnitude] how much.
  /// Redeeming it may push the store OVER its ceiling — that is the point of a
  /// package: a campaign reward keeps its full value however small your stores
  /// are, instead of evaporating against a cap you have not built past yet. The
  /// price is that nothing of that resource is produced while it sits above the
  /// line (SettlementController.redeemPack, ResourceModel.withProductionCapped).
  resourcePack;

  static ItemKind parse(String? s) => ItemKind.values.firstWhere(
    (k) => k.name == s,
    orElse: () => ItemKind.heal,
  );
}

class ItemDef {
  final String id;
  final String name;
  final String emoji;
  final String description;

  final ItemKind kind;

  /// Kind-specific number: HP (heal), revive fraction, buff fraction, catch
  /// window fraction, expedition-yield fraction, breed-time cut fraction.
  final double magnitude;

  /// The stat a [ItemKind.buff] raises. Ignored for other kinds.
  final CreatureStat? buffStat;

  /// The resource a [ItemKind.resourcePack] contains — a ResourceModel key
  /// ('wood', 'stone', 'gold' or any good id). Ignored for other kinds.
  final String? resourceId;

  /// Whether this item can be used DURING a battle (Phase 2 combat hook). Heals,
  /// revives and buffs are the natural battle items; lures/kits are not.
  final bool battleUsable;

  /// Concrete goods this recipe consumes: {goodId: amount}. Empty → billed via
  /// the abstract [supplyCost] fallback instead.
  final Map<String, double> ingredients;

  /// Legacy abstract cost, billed against the era's goods richest-first when
  /// [ingredients] is empty. Kept for backward compatibility.
  final double supplyCost;

  /// Crafting-seconds one craft takes before the Workshop's crafting power
  /// divides it (same shape as BuildingDef.constructionSeconds).
  final double craftSeconds;

  /// Trade Center prices in GOLD (Phase 3). buyPrice 0 = not sold; sellPrice
  /// 0 = can't be sold back.
  final int buyPrice;
  final int sellPrice;

  const ItemDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    this.kind = ItemKind.heal,
    this.magnitude = 0,
    this.buffStat,
    this.resourceId,
    this.battleUsable = false,
    this.ingredients = const {},
    this.supplyCost = 0,
    required this.craftSeconds,
    this.buyPrice = 0,
    this.sellPrice = 0,
  });

  bool get isHeal => kind == ItemKind.heal;

  /// HP a heal item restores — the compat shim for the existing heal path
  /// (crafting.dart's healFromItem / canUseOn, creatures_controller.useItemOn).
  double get healHp => kind == ItemKind.heal ? magnitude : 0;

  factory ItemDef.fromDefRow(Map<String, dynamic> row) => ItemDef(
    id: row['id'] as String,
    name: row['name'] as String? ?? '',
    emoji: row['emoji'] as String? ?? '🧪',
    description: row['description'] as String? ?? '',
    // Legacy rows only had heal_hp — read it as a heal item so old content maps
    // cleanly onto the new kind/magnitude model.
    kind: row['kind'] != null
        ? ItemKind.parse(row['kind'] as String?)
        : ItemKind.heal,
    magnitude: (row['magnitude'] as num?)?.toDouble() ??
        (row['heal_hp'] as num?)?.toDouble() ??
        0,
    resourceId: row['resource_id'] as String?,
    buffStat: row['buff_stat'] == null
        ? null
        : CreatureStat.fromName(row['buff_stat'] as String?),
    battleUsable: row['battle_usable'] as bool? ?? false,
    ingredients: {
      for (final e in ((row['ingredients'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    supplyCost: (row['supply_cost'] as num?)?.toDouble() ?? 0,
    craftSeconds: (row['craft_seconds'] as num?)?.toDouble() ?? 0,
    buyPrice: (row['buy_price'] as num?)?.toInt() ?? 0,
    sellPrice: (row['sell_price'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toDefRow() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'description': description,
    'kind': kind.name,
    'magnitude': magnitude,
    'buff_stat': buffStat?.name,
    'resource_id': resourceId,
    'battle_usable': battleUsable,
    'ingredients': ingredients,
    'supply_cost': supplyCost,
    'craft_seconds': craftSeconds,
    'buy_price': buyPrice,
    'sell_price': sellPrice,
  };
}

// Bundled fallback content — the base the DB overrides per id (like
// kFallbackBuildingDefs). Recipes name era-appropriate luxury ingredients:
// era-1 items use fish/fur (the only era-1 luxuries), later ones the later
// goods. craftSeconds are aimed at the Workshop's ~1200 power/h (one crafting-30
// monster) so an item is a steady trickle, not a spam.
/// The hand-written items. Kept apart from [kFallbackItemDefs] only because the
/// packages below are COMPUTED and a const map cannot hold them.
const _kHandWrittenItems = <String, ItemDef>{
  'minor_potion': ItemDef(
    id: 'minor_potion',
    name: 'Minor Potion',
    emoji: '🧪',
    description: 'Restores 40 HP to one monster, instantly.',
    kind: ItemKind.heal,
    magnitude: 40,
    battleUsable: true,
    ingredients: {'fish': 2},
    craftSeconds: 1200,
    buyPrice: 20,
    sellPrice: 6,
  ),
  'potion': ItemDef(
    id: 'potion',
    name: 'Potion',
    emoji: '⚗️',
    description: 'Restores 100 HP to one monster, instantly.',
    kind: ItemKind.heal,
    magnitude: 100,
    battleUsable: true,
    // Deliberately worse per ingredient than the Minor Potion (100 HP for 6
    // goods = 16.7 HP/good vs the small one's 40/2 = 20): you pay a premium for
    // CONCENTRATION — one item, one action. Otherwise the small one is retired.
    ingredients: {'fish': 4, 'fur': 2},
    craftSeconds: 2400,
    buyPrice: 45,
    sellPrice: 14,
  ),
  'revive_charm': ItemDef(
    id: 'revive_charm',
    name: 'Revive Charm',
    emoji: '💗',
    description: 'Revives one K.O.'
        'd monster to 50% of its max HP.',
    kind: ItemKind.revive,
    magnitude: 0.5,
    battleUsable: true,
    ingredients: {'fur': 4},
    craftSeconds: 3000,
    buyPrice: 70,
    sellPrice: 20,
  ),
  'catch_lure': ItemDef(
    id: 'catch_lure',
    name: 'Catch Lure',
    emoji: '🎏',
    description: 'Widens the catch window on your next encounter (+25%).',
    kind: ItemKind.catchBoost,
    magnitude: 0.25,
    ingredients: {'fish': 2, 'fur': 1},
    craftSeconds: 1800,
    buyPrice: 40,
    sellPrice: 12,
  ),
};

// ── Ressourcenpakete (user 2026-07-30) ──────────────────────
// "Mache mir sinnvolle Paketgrössen. Diese können als Rewards bei der Kampagne
// vorkommen. Ich möchte dort immer Pakete geben und nicht direkt Ressourcen."
//
// WHY A PACKAGE AND NOT A HANDFUL OF WOOD. A campaign reward is granted the
// moment a battle is won, whatever your stores look like — so a node worth 800
// wood was worth 300 to a player whose Storehouse tops out at 500, and the
// difference vanished with no message. In a package the value is intact until
// you choose to open it, and opening it is allowed to overfill the store.
//
// THE SIZES are the author's (user 2026-07-30) — see [kPackSizes]. Three
// ladders, because the three kinds of resource are spent at wildly different
// rates: a settlement pays for buildings in thousands of wood by the late eras,
// while a luxury is spent in ones and twos on healing and breeding.
//
// The biggest build package is deliberately far past any early Storehouse (500
// at level 1). That is not an oversight — it is what the overflow rule is FOR.
//
// One package per rung per resource, GENERATED: a later era's goods get theirs
// by existing, and every one is editable in Dev Mode ▸ Items like any other
// item.

/// What KIND of thing a package holds — which decides its sizes.
///
/// Not a new classification: it reads the one the goods table already has
/// (GoodsKind), plus the two resources the settlement keeps in its own fields.
enum PackClass { build, gold, luxury }

/// The size ladder per class (user 2026-07-30, exact figures).
///
/// Build resources span four orders of magnitude because that is what a
/// settlement's wood bill does between era I and era VIII; luxuries stay small
/// because they are spent in ones and twos on healing and breeding; gold sits
/// between them.
const Map<PackClass, List<int>> kPackSizes = {
  PackClass.build: [10, 100, 500, 1000, 5000, 10000],
  PackClass.gold: [10, 50, 100, 500, 1000],
  PackClass.luxury: [10, 50, 100],
};

/// Which ladder [resourceId] uses.
PackClass packClassOf(String resourceId) {
  if (resourceId == 'gold') return PackClass.gold;
  // Wood and stone are the settlement's OWN fields, not goods — and they are
  // exactly what buildings are paid in, so they head the build ladder.
  if (resourceId == 'wood' || resourceId == 'stone') return PackClass.build;
  final good = kGoodsDefs[resourceId];
  if (good == null) return PackClass.luxury;
  // A raw an era unlocks and the element assembled from it are both building
  // materials; `supply` is the luxury half (fish, fur, honey …).
  return good.isSupply ? PackClass.luxury : PackClass.build;
}

/// The amounts [resourceId] is packaged in, smallest first.
List<int> packSizesFor(String resourceId) => kPackSizes[packClassOf(resourceId)]!;

/// The id a package carries — `pack_wood_500`, `pack_fur_50`.
///
/// The AMOUNT is the identity (it used to be a size name): the ladders differ in
/// length per class, so "the medium one" is not a thing that exists across them,
/// and the number is what an author is choosing anyway.
String packId(String resourceId, int amount) => 'pack_${resourceId}_$amount';

/// Reads a package id back into its two parts, or null when [id] is not one.
///
/// Parsed from the END: the last segment is the amount, everything between
/// `pack_` and it is the resource — so a good whose own id contains an
/// underscore stays readable. Used by the Dev-Mode node form to tell a package
/// row from an ordinary item WITHOUT looking the def up: a lookup that misses
/// (a roster that lost them, a Dev-Mode deletion) rendered the row as a mystery
/// item instead of a broken package, which is how this went unnoticed once
/// already (user 2026-07-30).
({String resourceId, int amount})? parsePackId(String id) {
  if (!id.startsWith('pack_')) return null;
  final cut = id.lastIndexOf('_');
  if (cut < 'pack_'.length) return null;
  final amount = int.tryParse(id.substring(cut + 1));
  final resourceId = id.substring('pack_'.length, cut);
  if (amount == null || amount <= 0 || resourceId.isEmpty) return null;
  return (resourceId: resourceId, amount: amount);
}

/// Whether [id] names a resource package.
bool isPackId(String id) => parsePackId(id) != null;

/// The glyph a package of [amount] wears — by the FIGURE, not by its rank in its
/// own ladder, so 100 of anything looks like 100 of anything else.
String packEmoji(int amount) => amount >= 10000
    ? '🚂'
    : amount >= 5000
    ? '🚛'
    : amount >= 1000
    ? '🚚'
    : amount >= 500
    ? '🛒'
    : amount >= 100
    ? '📦'
    : '🧺';

/// One package as an item def.
ItemDef packDef(String resourceId, String resourceName, String emoji, int amount) =>
    ItemDef(
      id: packId(resourceId, amount),
      name: '$resourceName $amount',
      emoji: packEmoji(amount),
      description:
          'Opens into $amount $emoji $resourceName. May take your stores over '
          'their ceiling — nothing of it is produced until they are back under.',
      kind: ItemKind.resourcePack,
      magnitude: amount.toDouble(),
      resourceId: resourceId,
      // Not craftable and not for sale: a package is something the path HANDS
      // you. Letting the Workshop print them, or the market buy them, would make
      // the overflow rule a way around storage rather than a reward for a battle.
      craftSeconds: 0,
      buyPrice: 0,
      sellPrice: 0,
    );

/// Every package the game knows, keyed by id — each resource on its own ladder.
Map<String, ItemDef> buildPackDefs() {
  final out = <String, ItemDef>{};
  void add(String id, String name, String emoji) {
    for (final amount in packSizesFor(id)) {
      final def = packDef(id, name, emoji, amount);
      out[def.id] = def;
    }
  }

  add('wood', 'Wood', '🪵');
  add('stone', 'Stone', '🪨');
  add('gold', 'Gold', '🪙');
  for (final g in kGoodsDefs.values) {
    add(g.id, g.name, g.emoji);
  }
  return out;
}

/// THE bundled roster: the hand-written items plus one package per rung of each
/// resource's ladder.
///
/// The packages belong HERE, not merely in [kItemDefs] (fixed 2026-07-30, user:
/// "wenn ich auf +package drücke, kommen die Items und nicht die Ressourcen").
/// GameDefsController._merge rebuilds the live map on every load as
/// `clear() + fallback + database rows` — so anything that is only in the live
/// map exists until the game first talks to Supabase and then silently does not.
final Map<String, ItemDef> kFallbackItemDefs = {
  ..._kHandWrittenItems,
  ...buildPackDefs(),
};

/// Live, mutable roster (keyed by id) — same in-place pattern as kBuildingDefs,
/// so a Dev-Mode/DB source can override it (Phase 1b) without re-pointing callers.
final Map<String, ItemDef> kItemDefs = Map.of(kFallbackItemDefs);
