import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/creatures/expeditions_screen.dart';
import 'package:boddygame/features/creatures/models/expedition.dart';
import 'package:boddygame/features/creatures/services/expedition_controller.dart';

// The "Out now" trip card (user report 2026-09-30: crashed live —
// "BoxConstraints forces an infinite height" — the moment a real account had
// an expedition actually running). The bug only shows once `_outNowColumn`'s
// ListView has at least one item; every other expeditions-screen test seeds
// zero running expeditions and never touches this path.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  tearDown(() => ExpeditionController().expeditions = []);

  testWidgets('a running trip card lays out without an infinite-height crash', (
    t,
  ) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);

    ExpeditionController().expeditions = [
      Expedition(
        id: 'e1',
        userId: 'u',
        type: ExpeditionType.gather,
        areaId: 'a1',
        targetId: 'a1_wood',
        startedAt: DateTime.now().toUtc(),
        duration: const Duration(minutes: 30),
        payload: const {'resource': 'wood', 'amount': 40.0},
      ),
    ];

    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExpeditionsBody())),
    );
    await t.pump(const Duration(milliseconds: 200));

    expect(t.takeException(), isNull);
  });
}
