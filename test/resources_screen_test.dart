import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/settlement/build_menu_request.dart';
import 'package:boddygame/features/settlement/data/goods_definitions.dart';
import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/resource_detail_screen.dart';
import 'package:boddygame/features/settlement/resources_screen.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// The Resources page ("Epochen-Regale", user 2026-09-22): one shelf per era, gold
// on a shelf of its own because it belongs to no era, and a tile per resource
// that opens the resource's own page (production, consumption and storage on one
// page).
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  void seed() {
    final ctrl = SettlementController();
    ctrl.resources = ResourceModel(
      settlementId: 's',
      wood: 1240,
      stone: 420,
      gold: 4300,
      goods: const {'fish': 312, 'meat': 540},
      lastUpdatedAt: DateTime.now(),
    );
    ctrl.buildings = [];
    ctrl.settlement = null;
    ctrl.energy = null;
  }

  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    seed();
    await t.pumpWidget(const MaterialApp(home: ResourcesScreen()));
    await t.pump(const Duration(milliseconds: 200));
  }

  test('an era lists its build pair and its luxury; region I builds from raw '
      'wood and stone', () {
    expect(resourceIdsOfRegion(1), containsAll(['wood', 'stone', 'fish']));
    expect(resourceIdsOfRegion(1), isNot(contains('gold')));
    for (var r = 1; r <= kMaxRegionOrder; r++) {
      expect(resourceIdsOfRegion(r), isNot(contains('gold')));
    }
  });

  testWidgets('gold stands on its own shelf, before era I', (t) async {
    await open(t);
    expect(find.text('Resources'), findsOneWidget);
    // The gold shelf is labelled and belongs to "any era".
    expect(find.text('any era'), findsOneWidget);
    final goldShelf = t.getTopLeft(find.text('any era')).dy;
    final eraI = t.getTopLeft(find.text('I').first).dy;
    expect(goldShelf, lessThan(eraI));
    // Era I holds wood, stone and fish — not gold.
    expect(find.text('3 kinds'), findsWidgets);
    expect(find.text('🪙'), findsOneWidget);
    expect(find.text('🪵'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a resource page is whole: hero, production and storage, and it '
      'leads somewhere', (t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    seed();
    await t.pumpWidget(
      const MaterialApp(
        home: ResourceDetailScreen(
          resourceId: 'wood',
          emoji: '🪵',
          title: 'Wood',
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 300));
    // Three cards, each with its heading (the hero has none: it is the pile).
    expect(find.text('PRODUCED BY'), findsOneWidget);
    expect(find.text('STORAGE'), findsOneWidget);
    expect(find.text('1,240'), findsOneWidget);
    // Nothing produces wood in this settlement: the card says what to do next.
    final before = BuildMenuRequest.requests.value;
    expect(find.text('Build a producer'), findsOneWidget);
    expect(find.text('Build more storage'), findsOneWidget);
    await t.tap(find.text('Build a producer'));
    await t.pump(const Duration(milliseconds: 300));
    expect(BuildMenuRequest.requests.value, before + 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('a tile opens that resource\'s page', (t) async {
    await open(t);
    await t.tap(find.text('🪵'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(ResourceDetailScreen), findsOneWidget);
    expect(find.text('🪵  Wood'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
