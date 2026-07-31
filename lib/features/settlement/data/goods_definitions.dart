/// Everything the settlement stores besides wood, stone and gold — the luxury
/// supplies, the raw resources later eras unlock, and the building elements
/// they are assembled into.
///
/// ── They belong to an ERA ──
/// A good is introduced by an era and stays available from then on. That is
/// what makes their SINKS scale (user requirement 2026-07-16: "es müsste etwas
/// sein, was skalierbar ist, da in einer neuen Ära auch neue Ressourcen
/// dazukommen"): nothing that spends supplies names `fish` or `fur` literally —
/// it asks for [goodsForEra] and spends whatever that era has. Add a GoodsDef
/// with a later `eraOrder` and every sink picks it up with no further code.
///
/// Storage is a jsonb blob (`resources.goods`, migration 0006), so a new good
/// needs no schema change either — that used to be a hardcoded column per good
/// plus two lines in ResourceModel, which is exactly what made "add a resource
/// next era" expensive.
library;

import 'dart:math' as math;

/// What ROLE a good plays. The three are spent by different systems and must
/// never be confused: a healing bill that could eat your clay would silently
/// stall construction.
enum GoodsKind {
  /// Gathered luxury (fish, fur) — what ACTIONS bill: healing, dungeon entry,
  /// crafting supplies, the ascension toll.
  supply,

  /// A raw resource an era unlocks on the map (clay, lime, ore …). Gathered,
  /// never assembled, and only ever an input to that era's building element.
  raw,

  /// The era's BUILDING ELEMENT: assembled from the previous era's element plus
  /// the PREVIOUS era's raw. Buildings cost it PLUS the era's own fresh raw.
  element,
}

class GoodsDef {
  final String id;
  final String name;
  final String emoji;

  /// Era that introduces this good (matches EraDef.order — 1 = the first).
  final int eraOrder;

  final GoodsKind kind;

  /// How many units one person consumes per hour, settlement-wide (population
  /// × this). All 0 today: goods are spent by ACTIONS (healing, dungeon
  /// entry), not by passive upkeep — a drain that runs while you're away
  /// punishes taking a break, and building upkeep was just removed for the
  /// same reason.
  final double consumptionPerCapitaPerHour;

  /// What one unit is ASSEMBLED from: `{'frame': 2, 'clay': 2}` = two of the
  /// era before's element plus two of the era before's raw. Empty for anything
  /// gathered (supplies and raws).
  ///
  /// Inputs may be the settlement's own fields ('wood'/'stone'/'gold') or
  /// another good. See GameEngine._tickGoods, which throttles production to
  /// what the inputs actually cover.
  final Map<String, double> refinedFrom;

  const GoodsDef({
    required this.id,
    required this.name,
    required this.emoji,
    required this.eraOrder,
    this.kind = GoodsKind.supply,
    this.consumptionPerCapitaPerHour = 0,
    this.refinedFrom = const {},
  });

  bool get isElement => kind == GoodsKind.element;
  bool get isSupply => kind == GoodsKind.supply;
}

/// ── The era ladder (user 2026-07-24) ──
/// Every era from II on introduces ONE new raw resource AND ONE building
/// element. The element ASSEMBLES the era before's element with the era
/// before's raw; the era's OWN new raw is spent RAW — a separate, visible build
/// ingredient on top of the element — and only NEXT era gets folded in:
///
///     element(N)  = 2 × element(N−1) + 2 × rawForEra(N−1)
///     building(N) costs  element(N) + rawForEra(N)   ← the fresh raw
///
/// So a raw is "fresh" for exactly one era, then disappears into the next
/// element (user 2026-07-24: "in Ära 3 werden die beiden Güter aus Ära 2 zu
/// einem neuen Gut verarbeitet und ein neues kommt dazu"). Era I is the root:
/// wood AND stone are both era-I raws (both ResourceModel fields), and era-II's
/// element (the Timber Frame) is the one rung assembled from two raws instead
/// of element + raw.
///
/// Nothing ever transmutes. A Daub Wall literally contains the Timber Frame it
/// was daubed onto; stone never "becomes" steel. Two properties fall out of the
/// element chain and both are wanted:
///
///  * **Wood and stone stay equal, forever** — 128 each per era-VIII element.
///    They sit together in the first element, so every later doubling hits both
///    ("Stein soll sich gleichermassen weiterentwickeln", for free).
///  * **The older the resource, the more of it you need.** Each newer raw
///    halves down the chain: 128 wood → 2 crystal. The fresh raw of the top era
///    (Aether) is never folded further — it caps the ladder.
///
/// One era-VIII element still costs 382 raw units against an era-II element's 4.
const kGoodsDefs = <String, GoodsDef>{
  // ── Supplies: the luxury line, spent by ACTIONS ──
  // TWO luxuries per era (user 2026-07-24), each with its own producer building.
  // Cumulative and billed richest-first (goodsCost), so an era ADDS comfort
  // goods to the economy rather than replacing the old ones — fish still counts
  // in era VIII. Names/emojis are free to retune in Dev Mode.
  'fish': GoodsDef(id: 'fish', name: 'Fish', emoji: '🐟', eraOrder: 1),
  'fur': GoodsDef(id: 'fur', name: 'Fur', emoji: '🦫', eraOrder: 1),
  'honey': GoodsDef(id: 'honey', name: 'Honey', emoji: '🍯', eraOrder: 2),
  'herbs': GoodsDef(id: 'herbs', name: 'Herbs', emoji: '🌿', eraOrder: 2),
  'wine': GoodsDef(id: 'wine', name: 'Wine', emoji: '🍷', eraOrder: 3),
  'cheese': GoodsDef(id: 'cheese', name: 'Cheese', emoji: '🧀', eraOrder: 3),
  'spices': GoodsDef(id: 'spices', name: 'Spices', emoji: '🌶️', eraOrder: 4),
  'cloth': GoodsDef(id: 'cloth', name: 'Cloth', emoji: '🧵', eraOrder: 4),
  'salt': GoodsDef(id: 'salt', name: 'Salt', emoji: '🧂', eraOrder: 5),
  'silk': GoodsDef(id: 'silk', name: 'Silk', emoji: '🧶', eraOrder: 5),
  'coffee': GoodsDef(id: 'coffee', name: 'Coffee', emoji: '☕', eraOrder: 6),
  'chocolate': GoodsDef(
    id: 'chocolate',
    name: 'Chocolate',
    emoji: '🍫',
    eraOrder: 6,
  ),
  'tea': GoodsDef(id: 'tea', name: 'Tea', emoji: '🍵', eraOrder: 7),
  'porcelain': GoodsDef(
    id: 'porcelain',
    name: 'Porcelain',
    emoji: '🍶',
    eraOrder: 7,
  ),
  'perfume': GoodsDef(id: 'perfume', name: 'Perfume', emoji: '🌸', eraOrder: 8),
  'jewelry': GoodsDef(id: 'jewelry', name: 'Jewelry', emoji: '💍', eraOrder: 8),

  // ── The fresh raw each era unlocks (era II on). Era I's raws are wood AND
  //    stone — both live on ResourceModel's own fields, so they are not listed
  //    here. Each raw is the FRESH build ingredient of its own era and gets
  //    folded into the NEXT era's element (see the era-ladder note above).
  'clay': GoodsDef(
    id: 'clay',
    name: 'Clay',
    emoji: '🟤',
    eraOrder: 2,
    kind: GoodsKind.raw,
  ),
  'lime': GoodsDef(
    id: 'lime',
    name: 'Lime',
    emoji: '⚪',
    eraOrder: 3,
    kind: GoodsKind.raw,
  ),
  'ore': GoodsDef(
    id: 'ore',
    name: 'Ore',
    emoji: '⛏️',
    eraOrder: 4,
    kind: GoodsKind.raw,
  ),
  'coal': GoodsDef(
    id: 'coal',
    name: 'Coal',
    emoji: '⬛',
    eraOrder: 5,
    kind: GoodsKind.raw,
  ),
  'sand': GoodsDef(
    id: 'sand',
    name: 'Sand',
    emoji: '🟡',
    eraOrder: 6,
    kind: GoodsKind.raw,
  ),
  'crystal': GoodsDef(
    id: 'crystal',
    name: 'Crystal',
    emoji: '💎',
    eraOrder: 7,
    kind: GoodsKind.raw,
  ),
  // Era VIII's fresh raw — the capstone. It is the one raw NEVER folded into an
  // element (there is no era-IX element), so it stays a pure build ingredient
  // at the very top of the ladder.
  'aether': GoodsDef(
    id: 'aether',
    name: 'Aether',
    emoji: '✨',
    eraOrder: 8,
    kind: GoodsKind.raw,
  ),

  // ── The building elements, one per era from II on ──
  'frame': GoodsDef(
    id: 'frame',
    name: 'Timber Frame',
    emoji: '🪚',
    eraOrder: 2,
    kind: GoodsKind.element,
    refinedFrom: {'wood': 2, 'stone': 2},
  ),
  'daub': GoodsDef(
    id: 'daub',
    name: 'Daub Wall',
    emoji: '🧱',
    eraOrder: 3,
    kind: GoodsKind.element,
    refinedFrom: {'frame': 2, 'clay': 2},
  ),
  'plaster': GoodsDef(
    id: 'plaster',
    name: 'Plastered Wall',
    emoji: '🏛️',
    eraOrder: 4,
    kind: GoodsKind.element,
    refinedFrom: {'daub': 2, 'lime': 2},
  ),
  'truss': GoodsDef(
    id: 'truss',
    name: 'Iron Truss',
    emoji: '🔩',
    eraOrder: 5,
    kind: GoodsKind.element,
    refinedFrom: {'plaster': 2, 'ore': 2},
  ),
  'clinker': GoodsDef(
    id: 'clinker',
    name: 'Fired Clinker',
    emoji: '🔥',
    eraOrder: 6,
    kind: GoodsKind.element,
    refinedFrom: {'truss': 2, 'coal': 2},
  ),
  'glasswork': GoodsDef(
    id: 'glasswork',
    name: 'Glass Front',
    emoji: '🔷',
    eraOrder: 7,
    kind: GoodsKind.element,
    refinedFrom: {'clinker': 2, 'sand': 2},
  ),
  'vault': GoodsDef(
    id: 'vault',
    name: 'Crystal Vault',
    emoji: '💠',
    eraOrder: 8,
    kind: GoodsKind.element,
    refinedFrom: {'glasswork': 2, 'crystal': 2},
  ),
};

/// The building element era [eraOrder] introduces, or null for era I — which
/// builds from raw wood and stone alone. THE one place the "what does this era
/// build with" rule lives; price a new era's buildings against this PLUS
/// rawForEra(eraOrder) (the fresh raw), never against a hardcoded id.
GoodsDef? elementForEra(int eraOrder) {
  for (final g in kGoodsDefs.values) {
    if (g.isElement && g.eraOrder == eraOrder) return g;
  }
  return null;
}

/// The fresh raw resource era [eraOrder] unlocks on its map spots, or null for
/// era I — whose two raws (wood AND stone) are the settlement's own fields.
GoodsDef? rawForEra(int eraOrder) {
  for (final g in kGoodsDefs.values) {
    if (g.kind == GoodsKind.raw && g.eraOrder == eraOrder) return g;
  }
  return null;
}

/// Everything a settlement in era [eraOrder] holds that is NOT a supply — the
/// raws it has unlocked plus the elements it can assemble. Cumulative: an older
/// element stays the input of the newer one, and an older raw keeps being mined.
/// What the header strip shows next to the luxuries.
List<GoodsDef> materialsForEra(int eraOrder) =>
    kGoodsDefs.values.where((g) => !g.isSupply && g.eraOrder <= eraOrder).toList()
      ..sort((a, b) {
        final byEra = a.eraOrder.compareTo(b.eraOrder);
        return byEra != 0 ? byEra : a.id.compareTo(b.id);
      });

/// THE TWO THINGS ERA [eraOrder]'S BUILDINGS ARE PAID IN: its element and its
/// fresh raw (`building(N) = element(N) + rawForEra(N)`). NOT cumulative, on
/// purpose — unlike [materialsForEra], which lists everything ever unlocked.
///
/// Era I returns empty: its two build resources are wood and stone, which are
/// ResourceModel's own fields rather than goods, so the caller pairs them in.
///
/// The header strip's build half (user 2026-07-29: "Bauressourcen des aktuellen
/// Zeitalters"). An older element is still held and still consumed by the
/// workshop that assembles the current one — but it is the workshop's business,
/// not something you watch while deciding what to build, and by era VIII the
/// cumulative list was fourteen cells of strip.
List<GoodsDef> buildGoodsOfEra(int eraOrder) {
  final element = elementForEra(eraOrder);
  final raw = rawForEra(eraOrder);
  return [if (element != null) element, if (raw != null) raw];
}

/// The two luxuries era [eraOrder] itself introduces — again NOT cumulative
/// (that is [goodsForEra], which sinks still bill against).
List<GoodsDef> luxuriesOfEra(int eraOrder) =>
    kGoodsDefs.values
        .where((g) => g.isSupply && g.eraOrder == eraOrder)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));

/// What one unit of [goodId] costs in RAW resources, all the way down the
/// ladder. The economy's headline number — 1 Crystal Vault = 128 wood +
/// 128 stone + 64 clay + 32 lime + 16 ore + 8 coal + 4 sand + 2 crystal — and
/// the honest way to price a late-era building.
Map<String, double> rawCostOf(String goodId, {double units = 1}) {
  final def = kGoodsDefs[goodId];
  if (def == null || def.refinedFrom.isEmpty) return {goodId: units};
  final out = <String, double>{};
  def.refinedFrom.forEach((input, per) {
    rawCostOf(input, units: units * per).forEach(
      (raw, n) => out[raw] = (out[raw] ?? 0) + n,
    );
  });
  return out;
}

// ── Was eine Raffinerie verbrennt (user 2026-07-31) ─────────
// "clay rafinery soll anzeigen, welche Ressourcen verbraucht werden, um die
// neue herzustellen"
//
// The recipe was in the data and enforced by the tick, and said nowhere: the
// Clay Refinery's card announced "+7/h 🪚" and never mentioned the 14 wood and
// 14 stone an hour that pays for it. A building whose whole nature is a TRADE
// has to state both halves, or its output reads as free.

/// The recipes among [goodIds] that are assembled rather than gathered, keyed by
/// the good. One step down the ladder only — what this building actually burns,
/// not what the good is worth in raw wood ([rawCostOf] answers that).
Map<String, Map<String, double>> refiningRecipes(Iterable<String> goodIds) {
  final out = <String, Map<String, double>>{};
  for (final id in goodIds) {
    final def = kGoodsDefs[id];
    if (def == null || def.refinedFrom.isEmpty) continue;
    out[id] = def.refinedFrom;
  }
  return out;
}

/// What producing [ratesPerHour] (units/h, keyed by good) burns per hour, keyed
/// by input. Rates for goods that are gathered rather than refined contribute
/// nothing — a Fur Lodge consumes no inputs.
Map<String, double> refiningInputsPerHour(Map<String, double> ratesPerHour) {
  final out = <String, double>{};
  ratesPerHour.forEach((good, rate) {
    if (rate <= 0) return;
    kGoodsDefs[good]?.refinedFrom.forEach((input, per) {
      out[input] = (out[input] ?? 0) + rate * per;
    });
  });
  return out;
}

/// The supplies a settlement in era [eraOrder] deals in: everything introduced
/// up to and including that era. Cumulative on purpose — an era adds to your
/// economy rather than replacing it, so fish still matter in era III.
///
/// THE one place sinks ask about goods. Raws and elements are excluded: they
/// are construction currency, and a healing bill must never eat them.
List<GoodsDef> goodsForEra(int eraOrder) {
  final supplies = kGoodsDefs.values.where((g) => g.isSupply);
  final list = supplies.where((g) => g.eraOrder <= eraOrder).toList()
    ..sort((a, b) {
      final byEra = a.eraOrder.compareTo(b.eraOrder);
      return byEra != 0 ? byEra : a.id.compareTo(b.id);
    });
  // Defensive: a settlement whose era predates every supply would otherwise
  // have no currency for its sinks at all. Fall back to the earliest ones.
  if (list.isEmpty && supplies.isNotEmpty) {
    final earliest = supplies
        .map((g) => g.eraOrder)
        .reduce((a, b) => a < b ? a : b);
    return supplies.where((g) => g.eraOrder == earliest).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }
  return list;
}

/// Bills [total] units of "supplies" against era [eraOrder]'s goods, paying
/// from what the settlement ACTUALLY HAS ([stock]) — richest good first.
///
/// ── Why not an even split ──
/// It used to divide the total evenly across the era's goods and round each up,
/// so **every** cost demanded at least one of EVERY good. That deadlocked the
/// game: era I's goods are fish AND fur, region 1 has no fur spot, and fur
/// first appears in region 2 — behind a boss you need to heal to beat. Run out
/// of fur and healing stops entirely, which is exactly the trap the Healing
/// Hut was ungated to avoid (docs/balancing.md §4b). The old rule made *any*
/// era good that lacks an early source a soft-lock waiting to happen.
///
/// Paying from stock removes the whole class: as long as you have SOME of the
/// era's goods, you can pay. Supplies are supplies.
///
/// Richest-first on purpose: it spends the surplus you're sitting on and
/// protects the scarce good, which is what a player would do by hand.
///
/// When [stock] can't cover it the shortfall is still demanded (from the
/// richest good), so the caller's affordability check fails with a real number
/// instead of the cost silently shrinking to what you can afford.
Map<String, double> goodsCost(
  double total,
  int eraOrder,
  Map<String, double> stock,
) {
  final goods = goodsForEra(eraOrder);
  if (goods.isEmpty || total <= 0) return const {};

  // Whole units only — a cost of "0.4 fish" can't be paid or displayed.
  var remaining = math.max(1, total.ceil());

  final byStock = goods.map((g) => g.id).toList()
    ..sort((a, b) {
      final byHave = (stock[b] ?? 0).compareTo(stock[a] ?? 0);
      // Id as the tie-break so an untouched settlement (all zero) still gets a
      // deterministic bill rather than one that depends on map order.
      return byHave != 0 ? byHave : a.compareTo(b);
    });

  final cost = <String, double>{};
  for (final id in byStock) {
    if (remaining <= 0) break;
    final take = math.min((stock[id] ?? 0).floor(), remaining);
    if (take <= 0) continue;
    cost[id] = take.toDouble();
    remaining -= take;
  }
  if (remaining > 0) {
    // Unaffordable: name the shortfall so the refusal can say what's missing.
    final id = byStock.first;
    cost[id] = (cost[id] ?? 0) + remaining;
  }
  return cost;
}
