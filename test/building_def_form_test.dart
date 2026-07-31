import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/features/creatures/models/creature_enums.dart';
import 'package:boddygame/features/settlement/data/building_definitions.dart';
import 'package:boddygame/features/settlement/dev/building_def_form.dart';

// Dev Mode → Edit Building → Basis.
//
// Two things this tab got wrong on 2026-07-26, both found by the same bug (a
// stone camp that painted roads when tapped in the Build menu):
//
//  1. It PRESERVED isRoad / isBuildPlot / isMainBuilding on every save while
//     showing only isRoad — so a def that had one of the other two set could
//     not be turned back into an ordinary building from here.
//  2. The new Platzierung labels are sentences, and an unconstrained Text in
//     the checkbox row overflowed at phone width.

/// Phone width, because the overflow only happens on a narrow surface — and
/// tall, because the tab is a scrolling list of sections.
Future<void> _pumpBasics(WidgetTester tester, BuildingDef def) async {
  tester.view.physicalSize = const Size(FoE.phoneMaxWidth, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: BuildingDefForm(existing: def)));
  await tester.pumpAndSettle();
}

BuildingDef _camp({
  bool isRoad = false,
  bool isBuildPlot = false,
  bool isMainBuilding = false,
}) => BuildingDef(
  id: 'stone_camp_e1',
  name: 'Primitive Stone Camp',
  color: const Color(0xFF7A8288),
  gridW: 3,
  gridH: 3,
  isRoad: isRoad,
  isBuildPlot: isBuildPlot,
  isMainBuilding: isMainBuilding,
  workshops: const [
    WorkshopRole(stat: CreatureStat.production, resource: 'stone'),
  ],
);

void main() {
  testWidgets('every placement flag is editable, not silently carried',
      (tester) async {
    await _pumpBasics(tester, _camp());
    for (final label in [
      'Road (painted, not placed)',
      'Build plot (expands territory, occupies no space)',
      'Main building (auto-placed, no work posts)',
      'Unique (only one per settlement)',
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the Basis tab fits a phone — no overflow', (tester) async {
    // The Platzierung labels explain what each flag DOES, so they are long.
    await _pumpBasics(tester, _camp());
    expect(tester.takeException(), isNull);
  });

  testWidgets('an ordinary building may choose its category', (tester) async {
    await _pumpBasics(tester, _camp());
    // Automatisch derives Production from the stone workshop — stated, so
    // "Automatisch" is not a blank promise.
    expect(find.text('Automatic → Production'), findsOneWidget);
  });

  testWidgets('a road-flagged building says WHICH flag locks it to Special',
      (tester) async {
    // Without naming the flag, "is Special" on a def the author thinks is an
    // ordinary camp is a dead end.
    await _pumpBasics(tester, _camp(isRoad: true));
    expect(find.textContaining('«Road»'), findsOneWidget);
    expect(find.text('Automatic → Production'), findsNothing);
  });

  testWidgets('…and so does a build plot', (tester) async {
    await _pumpBasics(tester, _camp(isBuildPlot: true));
    expect(find.textContaining('«Build plot»'), findsOneWidget);
  });
}
