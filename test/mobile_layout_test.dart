import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/theme/foe_theme.dart';
import 'package:boddygame/core/ui/phone_frame.dart';

/// Pins the mobile layout rules the app kept breaking: things overlapping at
/// phone width, and tap targets sized for a mouse.
///
/// Flutter reports an overlap as a RenderFlex overflow *exception*, so
/// rendering a candidate layout at 430px and asserting no exception is a real
/// check, not a proxy — the header used to hold a back button, the settlement
/// name, a resource scroller AND the BP chip in one 52px row.
void main() {
  const phone = Size(FoE.phoneMaxWidth, 932);

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
      expect(frame.width, FoE.phoneMaxWidth);
      expect(dialog.left, greaterThanOrEqualTo(frame.left));
      expect(dialog.right, lessThanOrEqualTo(frame.right));
    });
  });
}
