import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/core/theme/cream_kit.dart' show KitCloseButton;
import 'package:boddygame/core/theme/strategy_theme.dart';
import 'package:boddygame/features/common/widgets/monster_tile_grid.dart';
import 'package:boddygame/features/common/widgets/parchment_kit.dart';
import 'package:boddygame/features/common/widgets/parchment_page.dart';
import 'package:boddygame/features/settlement/widgets/parchment_sheet.dart';

/// The shared strategy-HUD chrome at the real landscape phone size (932x430,
/// the long axis [PhoneFrame] allows by the short one it allows).
///
/// Every screen built on [ParchmentPage] / [ParchmentSheet] / [ParchmentDialog]
/// / [ParchmentButton] inherits this look from one place, so the place is what
/// is pinned: it must lay out without an overflow at the size the game is
/// actually played at, and hand back a working page rather than a blank one.
void main() {
  const phone = Size(932, FoE.phoneMaxWidth);

  Future<void> pumpAtPhone(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
  }

  testWidgets('ParchmentDialog fits the short axis with a long body', (
    tester,
  ) async {
    await pumpAtPhone(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => ParchmentDialog(
                title: 'Long one',
                child: ListView(
                  shrinkWrap: true,
                  children: [for (var i = 0; i < 40; i++) Text('row $i')],
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byType(ParchmentDialog));
    expect(rect.height, lessThanOrEqualTo(phone.height));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ParchmentSheet renders its heading and its leave button', (
    tester,
  ) async {
    await pumpAtPhone(
      tester,
      Scaffold(
        body: ParchmentSheet(
          title: 'Wood',
          builder: (_, c) => ListView(controller: c),
        ),
      ),
    );
    await tester.pump();
    // The heading is in capitals, with the kit's one leaving button at its end.
    expect(find.text('WOOD'), findsOneWidget);
    expect(find.byType(KitCloseButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a ChunkyButton lays out inside an unbounded-height Column', (
    tester,
  ) async {
    // Regression: its gloss overlay used a FractionallySizedBox under a
    // Positioned, which got an infinite height from a Column's loose
    // constraints and threw.
    await pumpAtPhone(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              ChunkyButton(onTap: () {}, expand: true, child: const Text('Go')),
              const ParchmentButton(label: 'Also', primary: true),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Go'), findsOneWidget);
  });

  testWidgets(
    'the shared monster tile flows several columns on a wide screen',
    (tester) async {
      await pumpAtPhone(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => GridView.builder(
              gridDelegate: monsterTileGridDelegate(context),
              itemCount: 30,
              itemBuilder: (_, i) => SizedBox(key: ValueKey(i)),
            ),
          ),
        ),
      );
      // Fixed, not a share of the (now long) device width.
      expect(
        monsterTileWidth(tester.element(find.byType(GridView))),
        kMonsterTileWidth,
      );
      // Auto-flow: many tiles on the first row, each a tile-shaped card.
      final firstRowY = tester.getTopLeft(find.byKey(const ValueKey(0))).dy;
      var perRow = 0;
      for (var i = 0; i < 30; i++) {
        final finder = find.byKey(ValueKey(i));
        if (finder.evaluate().isEmpty) break;
        if (tester.getTopLeft(finder).dy == firstRowY) perRow++;
      }
      expect(perRow, greaterThan(5));
      expect(
        tester.getSize(find.byKey(const ValueKey(0))).height,
        closeTo(kMonsterTileWidth / kMonsterTileAspect, 0.01),
      );
    },
  );
}
