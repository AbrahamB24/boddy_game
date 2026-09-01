import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/settlement/models/resource_model.dart';
import 'package:boddygame/features/settlement/resource_detail_screen.dart';
import 'package:boddygame/features/settlement/settlement_controller.dart';

// Reproducing a reported bug (user 2026-08-31): "wenn ich hier auf eine
// Ressource drücke, dann komme ich in die Übersicht. Wenn ich dann auf
// zurück drücke, bleibt das Spiel bei einem black screen hängen." — tap a
// resource cell in the settlement header, land on ResourceDetailScreen,
// press back, and the app is supposed to hang on black instead of
// returning to the map.
void main() {
  testWidgets('pushing and popping ResourceDetailScreen does not throw',
      (tester) async {
    final ctrl = SettlementController();
    ctrl.resources = ResourceModel(
      settlementId: 's',
      wood: 122,
      stone: 422,
      gold: 0,
      goods: const {'fish': 7},
      lastUpdatedAt: DateTime.now(),
    );
    ctrl.buildings = [];
    ctrl.settlement = null;
    ctrl.energy = null;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ResourceDetailScreen(
                    resourceId: 'wood',
                    emoji: '🪵',
                    title: 'Wood',
                  ),
                ),
              ),
              child: const Text('open resource'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open resource'));
    await tester.pumpAndSettle();
    expect(find.text('🪵  Wood'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The app's own back icon now (2026-08-31 audit), not the bespoke
    // chevron_left the header used to draw by hand.
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
    // Step through the pop transition frame by frame instead of
    // pumpAndSettle's single jump to the end — if a rebuild mid-transition
    // is what throws, jumping past it would hide the very frame that fails.
    // Also fire a notifyListeners() partway through, the way the real 5s
    // game tick could land mid-transition — ResourceDetailScreen wraps its
    // WHOLE page (Scaffold included) in AnimatedBuilder(animation: ctrl),
    // unlike every other pushed screen, so a tick here rebuilds the entire
    // outgoing page while it's mid pop-transition.
    for (var i = 0; i < 30; i++) {
      if (i == 8) ctrl.notifyListeners();
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('open resource'), findsOneWidget);
    expect(find.text('🪵  Wood'), findsNothing);
  });
}
