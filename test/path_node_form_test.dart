import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/dev/path_node_form.dart';

// Dev Mode → Path → a node's building rewards (user 2026-07-26: "Knoten 11 gibt
// das Trading center, dies wird mir jedoch nicht angezeigt und dadurch kann ich
// es nicht ändern").
//
// The picker used to stop after 60 chips. With 84 pickable buildings that hid
// the last two dozen — the Trade Center among them — including ones the node
// ALREADY granted, so the reward existed, was invisible, and could not be
// removed. Everything here guards that: an editor may not hide the state it
// edits.

/// Tall and wide: the picker is a Wrap of every building, and a phone-sized
/// surface would simply never lay the late ones out.
Future<void> _pump(WidgetTester tester, PathNode node) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: PathNodeForm(existing: node)));
  await tester.pumpAndSettle();
}

/// Buildings the picker offers, in the order it sorts them.
List<BuildingDef> _pickable() => kBuildingDefs.values
    .where((d) => !d.isRoad && !d.isMainBuilding)
    .toList()
  ..sort((a, b) => a.name.compareTo(b.name));

/// The buildings some OTHER node already unlocks — since 2026-07-31 the picker
/// stops offering them (user: "wenn ich ein Gebäude als Unlock buildings bei
/// einem Knoten angewählt habe, dann soll dies bei den anderen nicht mehr
/// angezeigt werden"). Mirrors _grantedElsewhere in the form.
Map<String, int> _elsewhere(String nodeId) {
  final out = <String, int>{};
  for (final n in kPathNodes.values) {
    if (n.id == nodeId) continue;
    for (final b in n.rewards.buildings) {
      final at = out[b];
      if (at == null || n.order < at) out[b] = n.order;
    }
  }
  return out;
}

/// What the picker really offers on [nodeId]: the roster minus what is already
/// spoken for.
List<BuildingDef> _offerable(String nodeId) {
  final taken = _elsewhere(nodeId);
  return _pickable().where((d) => !taken.containsKey(d.id)).toList();
}

/// The era the form files a building under (empty eraIds = every era).
int? _eraOf(BuildingDef d) => d.eraIds.isEmpty ? null : d.startEraOrder;

List<BuildingDef> _inEra(List<BuildingDef> defs, int era) =>
    defs.where((d) => _eraOf(d) == null || _eraOf(d) == era).toList();

/// Opens the era-filter dropdown and picks "Alle Ären".
Future<void> _selectAllEras(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<int?>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('All eras').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a reward far down the roster is still shown', (tester) async {
    final node = kPathNodes['node_11']!;
    expect(node.rewards.buildings, contains('trading_post'),
        reason: 'the seed this test is about');
    await _pump(tester, node);
    expect(find.text(kBuildingDefs['trading_post']!.name), findsOneWidget);
  });

  testWidgets('on «All eras» every FREE building is offered, none dropped',
      (tester) async {
    await _pump(tester, kPathNodes['node_11']!);
    await _selectAllEras(tester);
    final free = _offerable('node_11');
    // The one that used to fall off the end, and the very last by name.
    expect(free.length, greaterThan(60), reason: 'otherwise nothing was hidden');
    for (final d in [free[60], free.last, free.first]) {
      expect(find.text(d.name), findsWidgets, reason: '${d.id} must be pickable');
    }
  });

  testWidgets('the search box counts what is offered vs the whole roster',
      (tester) async {
    await _pump(tester, kPathNodes['node_11']!);
    final all = _pickable();
    final free = _offerable('node_11');
    final eraI = _inEra(free, 1).length;
    // Node 11 is an era-I node, so the form opens filtered to era I. The
    // denominator stays the WHOLE roster — it is the "of how many" a reader
    // measures the offer against.
    expect(eraI, lessThan(all.length), reason: 'nothing would be filtered');
    expect(
      find.text('Search buildings… ($eraI of ${all.length})'),
      findsOneWidget,
    );
    await _selectAllEras(tester);
    expect(
      find.text('Search buildings… (${free.length} of ${all.length})'),
      findsOneWidget,
    );
  });

  group('the era filter (user 2026-07-26)', () {
    testWidgets('it opens on the NODE\'s own era, not on "all"', (tester) async {
      await _pump(tester, kPathNodes['node_11']!);
      // Era I is what battle 11 is, and the dropdown says so up front.
      expect(find.textContaining('Era 1'), findsWidgets);
      // A later era's building is not in the way.
      final later = _offerable('node_11').firstWhere((d) => _eraOf(d) == 3);
      expect(find.text(later.name), findsNothing, reason: later.id);
    });

    testWidgets('era-I buildings ARE offered on an era-I node', (tester) async {
      await _pump(tester, kPathNodes['node_11']!);
      final eraI = _inEra(_offerable('node_11'), 1);
      expect(eraI, isNotEmpty);
      expect(find.text(eraI.first.name), findsWidgets);
    });

    testWidgets('a granted building survives the filter — else it could not '
        'be removed', (tester) async {
      // trading_post is era I here, so pick something the filter WOULD hide
      // and put it on the node: it must still show as a ticked chip.
      final later = _offerable('node_11').firstWhere((d) => _eraOf(d) == 3);
      final n = kPathNodes['node_11']!;
      await _pump(
        tester,
        PathNode(
          id: n.id,
          order: n.order,
          name: n.name,
          areaId: n.areaId,
          rewards: PathRewards(buildings: [later.id]),
        ),
      );
      expect(find.text(later.name), findsOneWidget, reason: later.id);
    });
  });

  testWidgets('a reward whose def is gone is shown so it can be removed',
      (tester) async {
    // Otherwise it is invisible AND unremovable: the node keeps granting an id
    // nothing can build.
    const node = PathNode(
      id: 'node_ghost',
      order: 3,
      name: 'Ghost',
      rewards: PathRewards(buildings: ['no_such_building']),
    );
    await _pump(tester, node);
    expect(find.text('⚠ no_such_building'), findsOneWidget);
  });

  // ── Schon woanders vergeben (user 2026-07-31) ───────────────
  // "wenn ich ein Gebäude als Unlock buildings bei einem Knoten angewählt habe,
  // dann soll dies bei den anderen nicht mehr angezeigt werden, da es bereits
  // freigeschalten wurde oder wird."
  //
  // A building unlocks at the FIRST node granting it, so a second grant pays
  // nothing. The risk in hiding things from a picker is the bug this file was
  // opened for — a reward you cannot see is a reward you cannot remove — so what
  // is pinned here is the exact boundary: gone from the offer, never gone from
  // the node it is on.
  group('a building already granted elsewhere', () {
    testWidgets('is not offered on another node', (tester) async {
      final taken = _elsewhere('node_12');
      expect(taken, contains('trading_post'),
          reason: 'node 11 grants it — the seed this test is about');
      await _pump(tester, kPathNodes['node_12']!);
      await _selectAllEras(tester);
      expect(find.text(kBuildingDefs['trading_post']!.name), findsNothing);
    });

    testWidgets('says WHERE it went when you search for it', (tester) async {
      await _pump(tester, kPathNodes['node_12']!);
      // BY ITS HINT — every TextFormField on the form wraps a TextField, so
      // `.first` is the node's id, not the search box.
      await tester.enterText(
        find.ancestor(
          of: find.textContaining('Search buildings…'),
          matching: find.byType(TextField),
        ),
        'Trade',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Knoten 11'), findsWidgets,
          reason: '"not here" is a worse answer than "node 11 has it"');
    });

    testWidgets('is still shown on the node that GRANTS it', (tester) async {
      // The rule must never eat the state it edits: node 11's own chip stays,
      // ticked and removable.
      await _pump(tester, kPathNodes['node_11']!);
      expect(find.text(kBuildingDefs['trading_post']!.name), findsOneWidget);
    });
  });

  // ── Gesamtlevel UND Einzellevel (user 2026-07-30 / 2026-07-31) ──
  // "nicht die level der Monster einzeln eingeben, sondern den Gesamtlevel" —
  // then "bei edit node, will ich die einzlnen Level trotzdem bearbeiten
  // können". Both, and they must agree: the total spreads DOWN, a hand-set level
  // sums back UP. Two fields showing contradicting numbers would be worse than
  // either one alone.
  group('the node difficulty, from both ends', () {
    PathNode threeFoes() => const PathNode(
      id: 'node_5',
      order: 5,
      name: 'Battle 5',
      enemies: [
        PathEnemy(speciesId: 'umbros', level: 4),
        PathEnemy(speciesId: 'sprout', level: 5),
        PathEnemy(speciesId: 'droplet', level: 6),
      ],
    );

    Finder totalField() => find.ancestor(
      of: find.textContaining('Gesamtlevel'),
      matching: find.byType(TextFormField),
    );

    /// The Lv fields, in row order.
    List<TextEditingController> levelFields(WidgetTester tester) => [
      for (final f in tester.widgetList<TextField>(find.descendant(
        of: find.ancestor(
          of: find.text('Lv'),
          matching: find.byType(TextFormField),
        ),
        matching: find.byType(TextField),
      )))
        f.controller!,
    ];

    testWidgets('opens on the sum the node already has', (tester) async {
      await _pump(tester, threeFoes());
      expect(
        tester.widget<TextFormField>(totalField()).controller?.text,
        '15',
        reason: '4 + 5 + 6',
      );
    });

    testWidgets('typing a TOTAL spreads it over the monsters', (tester) async {
      await _pump(tester, threeFoes());
      await tester.enterText(totalField(), '90');
      await tester.pumpAndSettle();
      final levels = [
        for (final c in levelFields(tester)) int.parse(c.text),
      ];
      expect(levels.length, 3);
      expect(levels.reduce((a, b) => a + b), 90, reason: 'the sum is exact');
      for (final l in levels) {
        expect(l, inInclusiveRange(24, 36), reason: '30 ±20 %: $levels');
      }
    });

    testWidgets('typing ONE level sums back into the total', (tester) async {
      await _pump(tester, threeFoes());
      final fields = levelFields(tester);
      expect(fields, hasLength(3), reason: 'the levels are editable again');
      await tester.enterText(
        find
            .ancestor(
              of: find.text('Lv'),
              matching: find.byType(TextFormField),
            )
            .first,
        '20',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(totalField()).controller?.text,
        '31',
        reason: '20 + 5 + 6 — the total follows the hand',
      );
    });
  });
}
