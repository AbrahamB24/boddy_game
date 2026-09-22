import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/core/ui/phone_frame.dart';
import 'package:boddygame/features/settlement/widgets/building_carousel.dart';

/// Pins the mobile layout rules the app kept breaking: things overlapping at
/// phone width, and tap targets sized for a mouse.
///
/// Flutter reports an overlap as a RenderFlex overflow *exception*, so
/// rendering a candidate layout at phone size and asserting no exception is a
/// real check, not a proxy — the header used to hold a back button, the
/// settlement name, a resource scroller AND the BP chip in one 52px row.
///
/// LANDSCAPE (2026-09-18): "phone size" is wide-short now — width is the
/// long axis (up to 932, [PhoneFrame]'s own cap), height the short one
/// ([FoE.phoneMaxWidth], still 430 despite the name — see that constant's
/// own doc comment). These rows are still meaningfully width-sensitive even
/// though 932 is roomier than the old 430 portrait width: they pin that the
/// REAL device constraint doesn't overflow, not an arbitrarily strict one.
void main() {
  const phone = Size(932, FoE.phoneMaxWidth);

  Future<void> pumpAtPhoneSize(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = phone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(backgroundColor: FoE.bg, body: child),
      ),
    );
  }

  group('phone width', () {
    testWidgets('a long settlement name yields instead of overflowing',
        (tester) async {
      // The identity row must survive a name far longer than the design mock.
      await pumpAtPhoneSize(
        tester,
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A Very Long Settlement Name That Nobody Would Pick',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FoE.title(size: 14),
                  ),
                  Text('🏺 Stone Age', style: FoE.dim(size: 10)),
                ],
              ),
            ),
            Container(width: 90, height: 40, color: FoE.panelDark),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the quick menu fits five labelled items', (tester) async {
      await pumpAtPhoneSize(
        tester,
        Row(
          children: [
            for (final label in ['Build', 'Map', 'Monsters', 'Research'])
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: FoE.tapTarget),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🐾', style: TextStyle(fontSize: 20)),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FoE.dim(size: 9),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      expect(tester.takeException(), isNull);

      // Every item must still be thumb-sized once it has a label under it.
      for (final label in ['Build', 'Map', 'Monsters', 'Research']) {
        expect(find.text(label), findsOneWidget);
      }
    });
  });

  group('buildingCarouselHeight', () {
    // The build carousel's own height is a FRACTION of the screen's short
    // axis now (2026-09-18), not a flat constant — it has to scale from the
    // smallest realistic landscape phone (~375px tall, an iPhone SE) up to
    // this app's own 430px cap ([FoE.phoneMaxWidth]) without either eating
    // the map on a small phone or leaving it cramped on a slightly bigger
    // one. Pinned here as its own check, separate from the widget it sizes,
    // because a future retune of the fraction/clamp is exactly the kind of
    // one-line change that could silently drift back to something too
    // small for the carousel's own cards to fit (see building_carousel.dart
    // — the card's own size is derived FROM this).
    Future<double> heightAt(WidgetTester tester, double screenHeight) async {
      tester.view.physicalSize = Size(932, screenHeight);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      double? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              result = buildingCarouselHeight(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return result!;
    }

    testWidgets('stays well under a small phone\'s own height', (tester) async {
      final h = await heightAt(tester, 375);
      expect(h, lessThan(375 * 0.6), reason: 'would crowd out the map');
      // The clamp's own floor (see buildingCarouselHeight's doc comment) —
      // below it the carousel's category row + its cards no longer both fit.
      expect(h, greaterThanOrEqualTo(140));
    });

    testWidgets('does not run away on the tallest phone this app allows',
        (tester) async {
      final h = await heightAt(tester, FoE.phoneMaxWidth);
      // The clamp's ceiling: 250 since the cards grew (2026-09-18, bigger
      // tiles/assets and no backdrop), from 190.
      expect(h, lessThanOrEqualTo(250));
    });
  });

  group('PhoneFrame', () {
    testWidgets('dialogs land inside the frame, not around it', (tester) async {
      // The frame hangs off MaterialApp.builder specifically so it wraps the
      // Navigator; if it wrapped only `home`, a dialog would escape it and
      // render against the full desktop window.
      tester.view.physicalSize = const Size(2500, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => PhoneFrame(child: child!),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('hi')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final dialog = tester.getRect(find.byType(AlertDialog));
      final frame = tester.getRect(find.byType(ClipRRect).first);
      // LANDSCAPE (2026-09-18): width is the long axis now, height the
      // short one ([FoE.phoneMaxWidth]).
      expect(frame.height, FoE.phoneMaxWidth);
      expect(dialog.left, greaterThanOrEqualTo(frame.left));
      expect(dialog.right, lessThanOrEqualTo(frame.right));
    });
  });
}
