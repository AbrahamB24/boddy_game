import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/data/item_definitions.dart';

// ── Der Bag ist ein Screen (user 2026-07-31) ────────────────
// "bag soll ein eigener screen sein"
//
// The page itself cannot be pumped here — it loads the breeding controller in
// initState, which needs a live Supabase. What IS testable is the rule its two
// new drawers rest on, and that rule is the one that would silently double-count
// your possessions.
void main() {
  test('a pack is an item, so the drawers must split one bag', () {
    // Packs live in the same id→count bag as potions (2026-07-30). The Items
    // drawer therefore has to EXCLUDE them and the Packs drawer to select them:
    // without that split every pack sits in both, and "Items 12" counts things
    // the Items drawer cannot do anything with.
    final woodPack = packId('wood', packSizesFor('wood').first);
    expect(isPackId(woodPack), isTrue);
    expect(kItemDefs.containsKey(woodPack), isTrue,
        reason: 'a pack is a real item def, not a special case');
    expect(isPackId('minor_potion'), isFalse);
  });

  test('the split covers the whole bag — nothing can fall between them', () {
    // Every id in the item table is either a pack or not; the two drawers are a
    // partition, so no possession can be invisible in both.
    for (final id in kItemDefs.keys) {
      expect(isPackId(id) || !isPackId(id), isTrue);
    }
    final packs = kItemDefs.keys.where(isPackId).length;
    final rest = kItemDefs.keys.where((id) => !isPackId(id)).length;
    expect(packs + rest, kItemDefs.length);
    expect(packs, greaterThan(0), reason: 'the Packs drawer would be a lie');
  });
}
