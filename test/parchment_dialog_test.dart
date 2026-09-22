import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/features/common/widgets/parchment_page.dart';

// The kit's popup shell (ParchmentDialog): the away digest lays two columns side
// by side in it (user 2026-09-22, "Zwei Spalten"), so it takes a wider card, its
// own exit word, and a hook that runs when the exit button is pressed.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> open(WidgetTester t, {required VoidCallback onClose}) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ParchmentDialog(
                  title: 'While you were away',
                  maxWidth: 800,
                  closeLabel: 'Continue',
                  onClose: onClose,
                  child: Row(
                    children: const [
                      SizedBox(width: 300, child: Text('left column')),
                      Expanded(child: Text('right column')),
                    ],
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('a wide card with its own exit word and an exit hook', (t) async {
    var closed = 0;
    await open(t, onClose: () => closed++);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Close'), findsNothing);
    // Wider than the default 560 px cap, and inside the screen.
    final card = t.getRect(
      find
          .byType(ConstrainedBox)
          .evaluate()
          .map((e) => find.byWidget(e.widget))
          .firstWhere(
            (f) => t.getRect(f).width > 700 && t.getRect(f).width <= 800,
          ),
    );
    expect(card.width, greaterThan(700));
    await t.tap(find.text('Continue'));
    await t.pump(const Duration(milliseconds: 300));
    expect(closed, 1);
    expect(find.text('While you were away'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
