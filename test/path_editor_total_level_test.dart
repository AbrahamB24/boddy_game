import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart';
import 'package:boddygame/features/settlement/dev/path_editor_tab.dart';

// ── Gesamtlevel direkt in der Liste (user 2026-07-31) ───────
// "lass mich das Gesamtlevel hier direkt eingeben."
//
// The list is where a difficulty CURVE is read — battle 7 against 6 and 8 — so
// it is where the number that sets it must be editable. What is pinned here is
// that the field shows the node's real total and that adding it did not cost the
// list the things it already did: dragging nodes, and reading which monsters
// stand in them.
/// Two authored nodes + one left to the pool. The BUNDLED path authors no
/// enemies at all (they are rolled from the area pool), so the case this screen
/// is about has to be put on the path deliberately.
void _seed() {
  final before = {...kPathNodes};
  addTearDown(() => kPathNodes
    ..clear()
    ..addAll(before));
  kPathNodes['node_1'] = const PathNode(
    id: 'node_1',
    order: 1,
    name: 'Battle 1',
    enemies: [
      PathEnemy(speciesId: 'umbros', level: 4),
      PathEnemy(speciesId: 'sprout', level: 6),
    ],
  );
  kPathNodes['node_2'] = const PathNode(
    id: 'node_2',
    order: 2,
    name: 'Battle 2',
    enemies: [PathEnemy(speciesId: 'droplet', level: 12)],
  );
  kPathNodes['node_3'] = const PathNode(
    id: 'node_3',
    order: 3,
    name: 'Battle 3',
  );
}

Future<void> _pump(WidgetTester tester) async {
  _seed();
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
    // A Scaffold, because the tab is one — in the app it lives inside the dev
  // screen's, and a TextField needs the Material under it.
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: PathEditorTab())),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every authored node shows its own summed level', (tester) async {
    await _pump(tester);
    final authored = [
      for (final id in ['node_1', 'node_2']) kPathNodes[id]!,
    ];
    for (final n in authored) {
      final total = n.enemies.fold<int>(0, (s, e) => s + e.level);
      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.text('$total'),
        ),
        findsWidgets,
        reason: '${n.id} sums to $total',
      );
    }
  });

  testWidgets('a pool-generated node offers no field to type into',
      (tester) async {
    // There is nothing to spread a total over yet, and conjuring three monsters
    // because someone typed a number is not what typing a number means.
    await _pump(tester);
    final fields = tester.widgetList<TextField>(find.byType(TextField)).length;
    final authored =
        pathNodesInOrder().where((n) => n.enemies.isNotEmpty).length;
    expect(fields, authored,
        reason: 'exactly the nodes that have something to spread a total over');
    // node_3 still SAYS what it would field — it just cannot be typed into.
    expect(find.text('aus dem Pool erzeugt'), findsWidgets);
  });

  testWidgets('the list can still be dragged and still names its monsters',
      (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.drag_handle), findsWidgets,
        reason: 'reordering is what this list was FOR');
    expect(find.byType(ReorderableListView), findsOneWidget);
  });
}
