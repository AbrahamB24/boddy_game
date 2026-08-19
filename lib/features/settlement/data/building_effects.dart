import 'building_definitions.dart'
    show BuildingEffect, WorkshopRole;
import '../../creatures/models/creature_enums.dart' show CreatureStat;

// ── WHICH effects a building has (user 2026-07-29) ─────────────────────────
// "Die Effekte bei den Gebäuden ist viel zu kompliziert aktuell. Bitte schreibe
// die aktuellen Effekte in den Code zu den Gebäuden, ich muss nicht neue
// Effekte hinzufügen können, diese nur einstellen."
//
// So the SHAPE lives here and the NUMBERS live in Dev Mode. A building's set of
// effects — which posts it has, which resources it trickles, whether it grants
// housing or hunt lengths — is a design decision that belongs in the repo,
// where it is reviewable and cannot be half-deleted by a stray tap. What the
// author retunes constantly is the values, and those still come from the
// database and still apply to everyone instantly.
//
// That split is what let the Dev-Mode effects editor lose its type dropdown,
// its "+ Add Effect" and its per-row delete: with the shape fixed, the form is
// a list of numbers, which is all it ever needed to be.
//
// ── Authoring ──
// One entry per building id. Adding an effect to a building means adding a line
// HERE — that is the intended workflow, not a gap. A building missing from this
// map simply has no effects (roads, building plots, the pure housing pens).
//
// Seeded on 2026-07-29 from the author's live database, so code and game agreed
// from the first run. test/building_effects_test.dart pins the shapes that
// carry rules (the Scout Post's grants, the civil-service posts, housing).
//
// ── NO `xp` effect here (user 2026-07-30) ──
// "Jedes Gebäude, welches Monster «anstellt» soll EP geben. Jedes Gebäude gibt
// genau gleich viel EP."
//
// XP is not a per-building number any more, so it is not a shape either: any
// building with a `workshops` entry pays the settlement-wide work rate, and one
// with none pays nothing. See XpConfig.workPerHour and
// CreaturesController.xpRatePerHour — one rule, one dial in Species-Budget → XP.
//
// It WAS a per-building effect, authored on the eleven era-I buildings this
// table was seeded from and on none of the ~40 later ones with work posts. So
// every clay pit, refinery, luxury yard and special building from era II up
// stationed monsters that earned nothing, and adding an `xp` line to each would
// have left fifty numbers to keep equal by hand.

/// One building's authored effects, split the way BuildingDef stores them.
class BuildingEffects {
  /// Work posts — creatures stationed here and what their stat produces.
  final List<WorkshopRole> workshops;

  /// Everything worker-free: production trickles, housing, slot grants, the
  /// per-era palette.
  final List<BuildingEffect> effects;

  const BuildingEffects({this.workshops = const [], this.effects = const []});

  static const none = BuildingEffects();
}

/// The authored SHAPE of [id]'s effects, with each one's numbers taken from
/// [dbWorkshops] / [dbEffects] where the database has a match.
///
/// This is what makes "shape in code, numbers in Dev Mode" actually work at
/// runtime. A Dev-Mode row replaces the whole def on load (see
/// GameDefsController), so without this a shape added or removed HERE would
/// never reach a settlement whose row was saved before the change — the code
/// table would be authoritative only for a fresh database.
///
/// Matching is by identity, not position: a workshop by its `resource`, an
/// effect by its (type, key). So reordering the table is harmless, an effect
/// the database no longer has keeps its code value, and one the database has
/// but the code does not is DROPPED — which is the point of fixing the shape.
///
/// A building the table doesn't know keeps its row untouched: Dev Mode can
/// still create a brand-new building, and it must not come back effect-less.
BuildingEffects reconcileEffects(
  String id, {
  required List<WorkshopRole> dbWorkshops,
  required List<BuildingEffect> dbEffects,
}) {
  final authored = kBuildingEffects[id];
  if (authored == null) {
    return BuildingEffects(workshops: dbWorkshops, effects: dbEffects);
  }
  return BuildingEffects(
    workshops: [
      for (final a in authored.workshops)
        _mergeWorkshop(
          a,
          dbWorkshops.where((w) => w.resource == a.resource).firstOrNull,
        ),
    ],
    effects: [
      for (final a in authored.effects)
        _mergeEffect(
          a,
          dbEffects
              .where((e) => e.type == a.type && e.key == a.key)
              .firstOrNull,
        ),
    ],
  );
}

/// The code's post with the database's TUNABLE numbers. `stat` and `resource`
/// are shape and always come from the code — they decide what the post IS.
WorkshopRole _mergeWorkshop(WorkshopRole code, WorkshopRole? db) => db == null
    ? code
    : WorkshopRole(
        stat: code.stat,
        resource: code.resource,
        mult: db.mult,
        slots: db.slots,
        levelFactor: db.levelFactor,
        slotSteps: db.slotSteps,
        mults: db.mults.isEmpty ? code.mults : db.mults,
      );

/// The code's effect with the database's tunable numbers. `type` and `key` are
/// shape — and so is HOW IT GROWS.
///
/// The growth MODE follows the code, the values follow the row. An effect the
/// code authors as a percentage takes its factor from the row; one the code
/// authors as an explicit ladder takes its rungs from the row. What a row may
/// NOT do is bring back a ladder for an effect the code has since moved onto a
/// percentage — because `levelSteps` silently overrides `levelFactor`
/// (BuildingEffect.valueAtLevel), that leftover would make the percentage field
/// inert with nothing on screen saying why.
///
/// That is exactly what happened to the Storehouse (user 2026-07-30: "growth
/// per level (%) bei storehaus funktioniert nicht"): its rows were written
/// while it was authored as a 23-rung ladder, and every percentage typed
/// afterwards was swallowed by rungs nobody could see.
BuildingEffect _mergeEffect(BuildingEffect code, BuildingEffect? db) {
  if (db == null) return code;
  final codeUsesLadder = code.levelSteps.isNotEmpty;
  return BuildingEffect(
    type: code.type,
    key: code.key,
    value: db.value,
    era: db.era,
    levelFactor: db.levelFactor ?? code.levelFactor,
    levelSteps: codeUsesLadder ? db.levelSteps : const {},
  );
}

/// One `storage` effect per resource, all growing the same way — the shorthand
/// the two stores are authored with.
///
/// Per-resource because that is how the ceiling is set (user 2026-07-30: "jede
/// Ressource will ich einzeln pro Level einstellen können"); this only saves
/// repeating the same two numbers five times. Split any one of them out to give
/// it its own — that is the intended edit, not a workaround.
///
/// Growth is a PERCENTAGE (user 2026-07-30: "gold und storehaus will ich auch
/// einen prozentualen anstieg festlegen können"), so levelling compounds and
/// the one knob in Dev Mode really governs the curve. It was an absolute
/// 23-rung ladder, which said the same thing in 23 numbers and — because an
/// authored step overrides the factor — made the percentage field inert.
///
/// Enter per-level steps in Dev Mode to go back to exact rungs for a resource;
/// that still wins, as it does for every other effect.
List<BuildingEffect> _storageFor(
  List<String> resources, {
  required double atLevelOne,
  required double growthPerLevel,
}) => [
  for (final r in resources)
    BuildingEffect(
      type: 'storage',
      key: r,
      value: atLevelOne,
      levelFactor: growthPerLevel,
    ),
];

/// THE table. Keyed by building id; see [BuildingEffects].
final Map<String, BuildingEffects> kBuildingEffects = {
  // ── The stores (user 2026-07-30) ──
  // The Storehouse takes the era-I production resources and luxury goods; the
  // Vault takes coin. Later eras' goods have no entry yet, so they sit at the
  // base dial until one is added here — one line each.
  // Both stores are STAFFED since 2026-07-30 (user: "Die Lagerhäuser können wie
  // die Produktionsgebäude Monster beherbergen, wobei ihre Punkte in Logistics
  // die Lagerkapazität definieren"): the authored `storage` effects are the
  // empty building's room, and every posted logistician adds their own.
  //
  // The post's per-level factor is the SAME +25 %/level the ceilings use, so a
  // levelled store's staff keeps pace with the store instead of becoming a
  // rounding error against a 96k ceiling.
  'storehouse': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.logistics,
        resource: WorkshopRole.kStorageRoom,
        // ONE DIAL PER RESOURCE (user 2026-07-30: "Ich muss den output pro
        // worker für jede Ressource einzeln einstellen können") — a store holds
        // several goods and a point of logistics need not be worth the same room
        // in each. Keyed by resource id; see WorkshopRole.mults.
        //
        // Seeded EQUAL at 10, which is exactly what the single flat dial did
        // before, so splitting the dial changed no number in the game — it only
        // made four numbers out of one. Room per point: a default species rolls
        // ~10 base +1/level, so a Lv-10 worker carries ~19 points ≈ +190 room
        // per resource against this store's own 500 at L1.
        mults: {'wood': 10, 'stone': 10, 'fish': 10, 'fur': 10},
        // The fallback for a resource with no dial of its own — a later era's
        // goods added to the ceilings above but not here.
        mult: 10,
        slots: 1,
        levelFactor: 1.25,
        slotSteps: {3: 1, 6: 1, 9: 1, 12: 1, 15: 1, 18: 1, 21: 1, 24: 1},
      ),
    ],
    effects: [
      // +25 %/level, compounding: L1 500, L5 ≈ 1220, L10 ≈ 3725, L24 ≈ 96k —
      // room that keeps pace with a settlement whose production is itself on
      // a per-level curve.
      ..._storageFor(
        const ['wood', 'stone', 'fish', 'fur'],
        atLevelOne: 500,
        growthPerLevel: 1.25,
      ),
    ],
  ),
  'gold_vault': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.logistics,
        resource: WorkshopRole.kStorageRoom,
        // ×4 the Storehouse's dial, because the Vault holds ONE resource and the
        // Storehouse's four each get the full amount — the same worker is worth
        // four times as much over there otherwise. Its own ceiling is 4× too.
        //
        // One resource, so one dial — but it is still keyed, so the Vault reads
        // the same way as the Storehouse and a second coin-like good would get
        // its own number rather than inheriting this one.
        mults: {'gold': 40},
        mult: 40,
        slots: 1,
        levelFactor: 1.25,
        slotSteps: {4: 1, 8: 1, 12: 1, 16: 1, 20: 1, 24: 1},
      ),
    ],
    effects: [
      ..._storageFor(
        const ['gold'],
        atLevelOne: 2000,
        growthPerLevel: 1.25,
      ),
    ],
  ),
  'castle': BuildingEffects(
    effects: [
      BuildingEffect(
        type: 'production',
        key: 'wood',
        value: 20,
        levelFactor: 1.5,
      ),
      BuildingEffect(
        type: 'production',
        key: 'stone',
        value: 20,
        levelFactor: 1.5,
      ),
      BuildingEffect(
        type: 'housing',
        value: 5,
        levelSteps: {2: 5, 3: 5, 4: 5, 5: 5, 6: 5, 7: 5, 8: 5},
      ),
      BuildingEffect(
        type: 'production',
        key: 'gold',
        value: 1,
        levelFactor: 1.5,
      ),
    ],
  ),
  'small_wood_camp': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'wood',
        mult: 2,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1},
      ),
    ],
  ),
  'large_wood_camp': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'wood',
        mult: 2,
        slots: 2,
        levelFactor: 1,
        slotSteps: {2: 2, 3: 2, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2, 9: 2, 10: 2},
      ),
    ],
  ),
  'small_stone_camp': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'stone',
        mult: 2,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1},
      ),
    ],
  ),
  'large_stone_camp': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'stone',
        mult: 2,
        slots: 2,
        levelFactor: 1,
        slotSteps: {2: 2, 3: 2, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2, 9: 2, 10: 2},
      ),
    ],
  ),
  'small_house': BuildingEffects(
    effects: [
      BuildingEffect(type: 'housing', value: 2, levelSteps: {5: 1, 10: 1}),
      BuildingEffect(
        type: 'production',
        key: 'gold',
        value: 1,
        levelFactor: 1.12,
      ),
    ],
  ),
  'large_house': BuildingEffects(
    effects: [
      BuildingEffect(
        type: 'housing',
        value: 5,
        levelSteps: {4: 7, 7: 9, 10: 11},
      ),
      BuildingEffect(
        type: 'production',
        key: 'gold',
        value: 1,
        levelFactor: 1.1,
      ),
    ],
  ),
  'lux_fish': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'fish',
        mult: 0.5,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1},
      ),
    ],
  ),
  'lux_fur': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'fur',
        mult: 0.5,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1},
      ),
    ],
  ),
  'church': BuildingEffects(
    effects: [
      BuildingEffect(
        type: 'production',
        key: 'wood',
        value: 100,
        levelFactor: 1.1,
      ),
      BuildingEffect(
        type: 'production',
        key: 'fish',
        value: 3,
        levelFactor: 1.1,
      ),
      BuildingEffect(
        type: 'production',
        key: 'gold',
        value: 1,
        levelFactor: 1.1,
      ),
    ],
  ),
  'marketplace': BuildingEffects(
    effects: [
      BuildingEffect(
        type: 'production',
        key: 'stone',
        value: 100,
        levelFactor: 1.1,
      ),
      BuildingEffect(
        type: 'production',
        key: 'fur',
        value: 3,
        levelFactor: 1.1,
      ),
      BuildingEffect(
        type: 'production',
        key: 'gold',
        value: 1,
        levelFactor: 1.1,
      ),
    ],
  ),
  'builder_camp': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.construction,
        resource: WorkshopRole.kConstruction,
        mult: 0.5,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 4: 1, 5: 1, 6: 1, 7: 1, 9: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 16: 1, 17: 1, 19: 1, 20: 1, 21: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(type: 'queueSlots', value: 0, levelSteps: {8: 1, 18: 1}),
      BuildingEffect(type: 'buildSlots', value: 0, levelSteps: {3: 1, 15: 1}),
    ],
  ),
  'healing_hut': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.medicine,
        resource: WorkshopRole.kHealSpeed,
        mult: 0.00053,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(
        type: 'healSlots',
        value: 1,
        levelSteps: {3: 1, 6: 1, 9: 1, 12: 1, 15: 1, 18: 1, 21: 1, 24: 1},
      ),
      BuildingEffect(
        type: 'healQueue',
        value: 0,
        levelSteps: {2: 1, 5: 1, 8: 1, 11: 1, 14: 1, 17: 1, 20: 1, 23: 1},
      ),
    ],
  ),
  'trading_post': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.trade,
        resource: WorkshopRole.kTradeRate,
        mult: 0.002,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(type: 'trade', value: 5),
    ],
  ),
  'breeding_hut': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kBreeding,
        mult: 1,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 1, 23: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(
        type: 'breeding',
        value: 1,
        levelSteps: {4: 1, 10: 1, 16: 1, 22: 1},
      ),
    ],
  ),
  'hatchery': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kHatching,
        mult: 1,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 18: 1, 19: 1, 20: 1, 21: 1, 22: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(
        type: 'breeding',
        value: 1,
        levelSteps: {5: 1, 11: 1, 17: 1, 23: 1},
      ),
    ],
  ),
  // ONE post for the whole trip (user 2026-07-29: "travel time speed, carrying
  // capacity sind im gleichen effekt. D.h ich will einmal die Monster slots
  // eingeben und für beide effekte den wert angeben, welche sich auf die
  // gleichen Monster beziehen").
  //
  // It was two posts, each with its own seat count, so the same scout had to be
  // hired twice to be worth anything on both counts. Now: one seat count, and
  // one dial per part. Each part still reads the stat it amplifies — a fast
  // scout shortens the trip, a strong-backed one widens the load — so who you
  // post still matters, it just isn't two decisions any more.
  //
  // The two mults are the ones the old posts carried. `goods` is 0: gathering
  // yield is the Smokehouse's job. Turn it up in Dev Mode if the Scout Post
  // should help there too — the dial is there, it is simply off.
  'scout_post': BuildingEffects(
    workshops: [
      WorkshopRole(
        // The SLOT key and the hire ranking. Travel is what a scout post is
        // chiefly for, so the list is ordered by speed.
        stat: CreatureStat.speed,
        resource: WorkshopRole.kExpedition,
        slots: 1,
        levelFactor: 1,
        mults: {'travel': 0.0015, 'carry': 0.01, 'goods': 0},
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
    effects: [
      BuildingEffect(
        type: 'huntOptions',
        value: 1,
        levelFactor: 1,
        levelSteps: {3: 1, 7: 1, 11: 1, 15: 1, 19: 1, 23: 1},
      ),
      BuildingEffect(
        type: 'expeditionSlots',
        value: 1,
        levelFactor: 1,
        levelSteps: {3: 1, 9: 1, 15: 1, 21: 1},
      ),
    ],
  ),
  // ⚠ The caravanSlots effect below was NOT in the exported config, and with
  // the base pool set to 0 that meant no caravan could ever leave — the whole
  // trade road was unreachable. Restored to the ladder the code shipped
  // (1 at L1, +1 at L4 and L8). Set it to 0 in Dev Mode if trade really is
  // meant to be off; deleting the shape is a code change now.
  'caravanserai': BuildingEffects(
    effects: [
      BuildingEffect(type: 'caravanSlots', value: 1, levelSteps: {4: 1, 8: 1}),
    ],
    // ONE post, exactly like the Scout Post (user 2026-07-30: "karawansarei
    // gleich wie scout post. Geschwindigkeit, carry etc. in einen Effekt packen
    // mit den gleichen Monster").
    //
    // It was two posts with two seat counts, so a drover who was both quick and
    // strong-backed had to be hired twice to be worth either. Now one seat, one
    // ladder, and a dial per part — cargo still reads `carry`, road time still
    // reads `speed`, so who you post still decides which half improves.
    //
    // No `goods` part: a caravan's return is PRICED at send, so a yield
    // multiplier would have nothing to multiply (see caravanBonuses).
    workshops: [
      WorkshopRole(
        // The seat key and the hire ranking. Cargo is what a caravan is for,
        // so the list leads with carry — the twin of the Scout Post's speed.
        stat: CreatureStat.carry,
        resource: WorkshopRole.kCaravan,
        slots: 1,
        levelFactor: 1,
        mults: {'carry': 0.003, 'travel': 0.002},
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
  ),
  'clay_camp_e2': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'clay',
        mult: 0.8,
        slots: 6,
      ),
    ],
  ),
  'clay_works_e2': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'clay',
        mult: 1.3,
        slots: 10,
      ),
    ],
  ),
  'refinery_e2': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'frame',
        mult: 0.3,
        slots: 8,
      ),
    ],
  ),
  'lux_herbs': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'herbs',
        mult: 0.2,
        slots: 3,
      ),
    ],
  ),
  'lux_honey': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'honey',
        mult: 0.2,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e2': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 4.8, era: 2),
      BuildingEffect(type: 'production', key: 'stone', value: 4.8, era: 2),
      BuildingEffect(type: 'production', key: 'clay', value: 3.2, era: 2),
      BuildingEffect(type: 'production', key: 'frame', value: 2.4, era: 2),
    ],
  ),
  'special_treasury_e2': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 6.4, era: 2),
      BuildingEffect(type: 'production', key: 'herbs', value: 2.4, era: 2),
      BuildingEffect(type: 'production', key: 'honey', value: 2.4, era: 2),
    ],
  ),
  'thinker_circle': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: WorkshopRole.kCrafting,
        mult: 40,
        slots: 1,
        levelFactor: 1,
        slotSteps: {2: 1, 3: 1, 4: 1, 5: 1, 6: 1, 7: 1, 8: 1, 9: 1, 10: 1, 11: 1, 12: 1, 13: 1, 14: 1, 15: 1, 16: 1, 17: 1, 18: 1, 19: 1, 20: 1, 21: 1, 22: 1, 23: 1, 24: 1},
      ),
    ],
    // THE BENCHES AND THE LINE (user 2026-07-30). Each bench runs at the full
    // crafting rate, so a second one really doubles the Workshop's output —
    // hence a slower ladder for benches than for the queue behind them.
    effects: [
      BuildingEffect(
        type: 'craftSlots',
        value: 1,
        levelSteps: {4: 1, 9: 1, 14: 1, 19: 1, 24: 1},
      ),
      BuildingEffect(
        type: 'craftQueue',
        value: 2,
        levelSteps: {3: 1, 6: 1, 9: 1, 12: 1, 15: 1, 18: 1, 21: 1, 24: 1},
      ),
    ],
  ),
  'lime_camp_e3': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'lime',
        mult: 1.3,
        slots: 6,
      ),
    ],
  ),
  'lime_works_e3': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'lime',
        mult: 2,
        slots: 10,
      ),
    ],
  ),
  'refinery_e3': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'daub',
        mult: 0.5,
        slots: 8,
      ),
    ],
  ),
  'lux_cheese': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'cheese',
        mult: 0.3,
        slots: 3,
      ),
    ],
  ),
  'lux_wine': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'wine',
        mult: 0.3,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e3': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 7.7, era: 3),
      BuildingEffect(type: 'production', key: 'stone', value: 7.7, era: 3),
      BuildingEffect(type: 'production', key: 'clay', value: 5.1, era: 3),
      BuildingEffect(type: 'production', key: 'lime', value: 5.1, era: 3),
      BuildingEffect(type: 'production', key: 'daub', value: 3.8, era: 3),
    ],
  ),
  'special_treasury_e3': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 10.2, era: 3),
      BuildingEffect(type: 'production', key: 'cheese', value: 3.8, era: 3),
      BuildingEffect(type: 'production', key: 'wine', value: 3.8, era: 3),
    ],
  ),
  'training_grounds': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.construction,
        resource: WorkshopRole.kTraining,
        mult: 0,
        slots: 4,
      ),
    ],
  ),
  'warehouse': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.carry,
        resource: WorkshopRole.kExpCarry,
        mult: 0.003,
        slots: 3,
      ),
    ],
  ),
  'smokehouse': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.gathering,
        resource: WorkshopRole.kExpGoods,
        mult: 0.003,
        slots: 3,
      ),
    ],
  ),
  'ore_camp_e4': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'ore',
        mult: 2,
        slots: 6,
      ),
    ],
  ),
  'ore_works_e4': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'ore',
        mult: 3.3,
        slots: 10,
      ),
    ],
  ),
  'refinery_e4': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'plaster',
        mult: 0.8,
        slots: 8,
      ),
    ],
  ),
  'lux_cloth': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'cloth',
        mult: 0.5,
        slots: 3,
      ),
    ],
  ),
  'lux_spices': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'spices',
        mult: 0.5,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e4': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 12.3, era: 4),
      BuildingEffect(type: 'production', key: 'stone', value: 12.3, era: 4),
      BuildingEffect(type: 'production', key: 'clay', value: 8.2, era: 4),
      BuildingEffect(type: 'production', key: 'lime', value: 8.2, era: 4),
      BuildingEffect(type: 'production', key: 'ore', value: 8.2, era: 4),
      BuildingEffect(type: 'production', key: 'plaster', value: 6.1, era: 4),
    ],
  ),
  'special_treasury_e4': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 16.4, era: 4),
      BuildingEffect(type: 'production', key: 'cloth', value: 6.1, era: 4),
      BuildingEffect(type: 'production', key: 'spices', value: 6.1, era: 4),
    ],
  ),
  'coal_camp_e5': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'coal',
        mult: 3.3,
        slots: 6,
      ),
    ],
  ),
  'coal_works_e5': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'coal',
        mult: 5.2,
        slots: 10,
      ),
    ],
  ),
  'refinery_e5': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'truss',
        mult: 1.3,
        slots: 8,
      ),
    ],
  ),
  'lux_salt': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'salt',
        mult: 0.8,
        slots: 3,
      ),
    ],
  ),
  'lux_silk': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'silk',
        mult: 0.8,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e5': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 19.7, era: 5),
      BuildingEffect(type: 'production', key: 'stone', value: 19.7, era: 5),
      BuildingEffect(type: 'production', key: 'clay', value: 13.1, era: 5),
      BuildingEffect(type: 'production', key: 'lime', value: 13.1, era: 5),
      BuildingEffect(type: 'production', key: 'ore', value: 13.1, era: 5),
      BuildingEffect(type: 'production', key: 'coal', value: 13.1, era: 5),
      BuildingEffect(type: 'production', key: 'truss', value: 9.8, era: 5),
    ],
  ),
  'special_treasury_e5': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 26.2, era: 5),
      BuildingEffect(type: 'production', key: 'salt', value: 9.8, era: 5),
      BuildingEffect(type: 'production', key: 'silk', value: 9.8, era: 5),
    ],
  ),
  'sand_camp_e6': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'sand',
        mult: 5.2,
        slots: 6,
      ),
    ],
  ),
  'sand_works_e6': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'sand',
        mult: 8.4,
        slots: 10,
      ),
    ],
  ),
  'refinery_e6': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'clinker',
        mult: 2.1,
        slots: 8,
      ),
    ],
  ),
  'lux_chocolate': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'chocolate',
        mult: 1.3,
        slots: 3,
      ),
    ],
  ),
  'lux_coffee': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'coffee',
        mult: 1.3,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e6': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 31.5, era: 6),
      BuildingEffect(type: 'production', key: 'stone', value: 31.5, era: 6),
      BuildingEffect(type: 'production', key: 'clay', value: 21, era: 6),
      BuildingEffect(type: 'production', key: 'lime', value: 21, era: 6),
      BuildingEffect(type: 'production', key: 'ore', value: 21, era: 6),
      BuildingEffect(type: 'production', key: 'coal', value: 21, era: 6),
      BuildingEffect(type: 'production', key: 'sand', value: 21, era: 6),
      BuildingEffect(type: 'production', key: 'clinker', value: 15.7, era: 6),
    ],
  ),
  'special_treasury_e6': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 41.9, era: 6),
      BuildingEffect(
        type: 'production',
        key: 'chocolate',
        value: 15.7,
        era: 6,
      ),
      BuildingEffect(type: 'production', key: 'coffee', value: 15.7, era: 6),
    ],
  ),
  'crystal_camp_e7': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'crystal',
        mult: 8.4,
        slots: 6,
      ),
    ],
  ),
  'crystal_works_e7': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'crystal',
        mult: 13.4,
        slots: 10,
      ),
    ],
  ),
  'refinery_e7': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'glasswork',
        mult: 3.4,
        slots: 8,
      ),
    ],
  ),
  'lux_porcelain': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'porcelain',
        mult: 2,
        slots: 3,
      ),
    ],
  ),
  'lux_tea': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'tea',
        mult: 2,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e7': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 50.3, era: 7),
      BuildingEffect(type: 'production', key: 'stone', value: 50.3, era: 7),
      BuildingEffect(type: 'production', key: 'clay', value: 33.6, era: 7),
      BuildingEffect(type: 'production', key: 'lime', value: 33.6, era: 7),
      BuildingEffect(type: 'production', key: 'ore', value: 33.6, era: 7),
      BuildingEffect(type: 'production', key: 'coal', value: 33.6, era: 7),
      BuildingEffect(type: 'production', key: 'sand', value: 33.6, era: 7),
      BuildingEffect(type: 'production', key: 'crystal', value: 33.6, era: 7),
      BuildingEffect(
        type: 'production',
        key: 'glasswork',
        value: 25.2,
        era: 7,
      ),
    ],
  ),
  'special_treasury_e7': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 67.1, era: 7),
      BuildingEffect(
        type: 'production',
        key: 'porcelain',
        value: 25.2,
        era: 7,
      ),
      BuildingEffect(type: 'production', key: 'tea', value: 25.2, era: 7),
    ],
  ),
  'aether_camp_e8': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'aether',
        mult: 13.4,
        slots: 6,
      ),
    ],
  ),
  'aether_works_e8': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'aether',
        mult: 21.5,
        slots: 10,
      ),
    ],
  ),
  'refinery_e8': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.crafting,
        resource: 'vault',
        mult: 5.4,
        slots: 8,
      ),
    ],
  ),
  'lux_jewelry': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'jewelry',
        mult: 3.2,
        slots: 3,
      ),
    ],
  ),
  'lux_perfume': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.production,
        resource: 'perfume',
        mult: 3.2,
        slots: 3,
      ),
    ],
  ),
  'special_materials_e8': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'wood', value: 80.5, era: 8),
      BuildingEffect(type: 'production', key: 'stone', value: 80.5, era: 8),
      BuildingEffect(type: 'production', key: 'clay', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'lime', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'ore', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'coal', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'sand', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'crystal', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'aether', value: 53.7, era: 8),
      BuildingEffect(type: 'production', key: 'vault', value: 40.3, era: 8),
    ],
  ),
  'special_treasury_e8': BuildingEffects(
    workshops: [
      WorkshopRole(
        stat: CreatureStat.breeding,
        resource: WorkshopRole.kLegendaryBoost,
        mult: 1,
        slots: 1,
      ),
    ],
    effects: [
      BuildingEffect(type: 'production', key: 'gold', value: 107.4, era: 8),
      BuildingEffect(type: 'production', key: 'jewelry', value: 40.3, era: 8),
      BuildingEffect(type: 'production', key: 'perfume', value: 40.3, era: 8),
    ],
  ),
};
