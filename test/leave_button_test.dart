import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/core/theme/cream_kit.dart';
import 'package:boddygame/features/common/widgets/parchment_page.dart';

// The kit's ONE leaving button (user 2026-09-22): round gold, at the right end of
// the title row. A cross closes what was opened from the map, an arrow goes back
// from a menu opened over another menu.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> size(WidgetTester t) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
  }

  testWidgets('a menu opened from the map has a cross, one opened over it an '
      'arrow — same place either way', (t) async {
    await size(t);
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => pushMenu(
                context,
                Builder(
                  builder: (inner) => MenuScaffold(
                    title: 'First',
                    child: TextButton(
                      onPressed: () => pushMenu(
                        inner,
                        const MenuScaffold(title: 'Second', child: SizedBox()),
                      ),
                      child: const Text('deeper'),
                    ),
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
    await t.pumpAndSettle();
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    final first = t.getCenter(find.byType(KitCloseButton));

    await t.tap(find.text('deeper'));
    await t.pumpAndSettle();
    // Two menus are mounted now; the top one wears the arrow.
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    final second = t.getCenter(find.byIcon(Icons.arrow_back_rounded));
    expect(second.dx, moreOrLessEquals(first.dx, epsilon: 1));
    expect(second.dy, moreOrLessEquals(first.dy, epsilon: 1));

    // The arrow goes back one step: to the first menu, which still has its cross.
    await t.tap(find.byIcon(Icons.arrow_back_rounded));
    await t.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(find.text('First'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a dialog has the same button at the end of its heading', (
    t,
  ) async {
    await size(t);
    var closed = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => ParchmentDialog(
                  title: 'Anything',
                  onClose: () => closed++,
                  child: const Text('body'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(KitCloseButton), findsOneWidget);
    // No labelled Close button at the foot any more: the cross is the way out.
    expect(find.text('Close'), findsNothing);
    await t.tap(find.byType(KitCloseButton));
    await t.pumpAndSettle();
    expect(closed, 1);
    expect(find.text('body'), findsNothing);
  });
}
