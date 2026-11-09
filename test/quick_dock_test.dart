import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/ui/pressable.dart';
import 'package:boddygame/features/settlement/widgets/quick_pad.dart';

// The dock at the bottom left (user 2026-09-28): opening the drawer must not
// move the buttons that are already there — the row grows to the RIGHT only, and
// what hangs outside a button (its badge, its shadow) is not cut off.
void main() {
  testWidgets('the main button stays put when the drawer opens', (t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: QuickDock(
                main: QuickPadItem(Icons.tune, 'Manage', () {}),
                more: [
                  QuickPadItem(Icons.group, 'Social', () {}, badge: 1),
                  QuickPadItem(Icons.person, 'Profile', () {}),
                  QuickPadItem(Icons.backpack, 'Bag', () {}),
                  QuickPadItem(Icons.flag, 'Daily tasks', () {}, badge: 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();

    final before = t.getCenter(find.byTooltip('Manage'));
    final dockBefore = t.getSize(find.byType(QuickDock));

    await t.tap(find.byIcon(Icons.chevron_right));
    await t.pump(Pressable.duration + const Duration(milliseconds: 50));
    await t.pumpAndSettle();

    // Opened: the drawer's buttons are there …
    // (found by tooltip: these tiles wear rendered 3D glyphs, not flat icons)
    expect(find.byTooltip('Daily tasks'), findsOneWidget);
    // … the main button did not move by a pixel …
    expect(t.getCenter(find.byTooltip('Manage')), before);
    // … the dock got wider, never taller …
    final dockAfter = t.getSize(find.byType(QuickDock));
    expect(dockAfter.height, dockBefore.height);
    expect(dockAfter.width, greaterThan(dockBefore.width));
    // … and every button of the drawer sits on the SAME line as the main one.
    for (final tip in ['Social', 'Profile', 'Bag', 'Daily tasks']) {
      expect(t.getCenter(find.byTooltip(tip)).dy, before.dy);
    }
    // … and the same plate closes it again, back to the original width (user
    // 2026-11-04: "ich kann es nicht schliessen").
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.pump(Pressable.duration + const Duration(milliseconds: 50));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(QuickDock)).width, dockBefore.width);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    expect(t.getCenter(find.byTooltip('Manage')), before);
    expect(t.takeException(), isNull);
  });
}
