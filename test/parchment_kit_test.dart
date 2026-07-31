import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/common/widgets/parchment_kit.dart';

// The pieces the parchment SCREENS are built from (user 2026-07-29: "designe
// den expeditions screen mitsamt hunt und gatherscreens komplett neu. Benutze
// dabei die Element von anderen bereits designten screens").
//
// The expeditions hub used to print dark panels and dark buttons onto a light
// page. The fix was to stop hand-rolling controls per screen, so what matters
// here is that the shared ones behave: a disabled button does not fire, a
// muted card still shows its content, and the confirm box answers honestly.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  group('ParchmentButton', () {
    testWidgets('fires when enabled', (tester) async {
      var taps = 0;
      await pump(tester, ParchmentButton(label: 'Send', onTap: () => taps++));
      await tester.tap(find.text('Send'));
      expect(taps, 1);
    });

    testWidgets('a null onTap makes it inert, not invisible', (tester) async {
      // The send bar shows WHY it can't send in the button's own label, so a
      // disabled button still has to be readable.
      await pump(tester, const ParchmentButton(label: 'Pick who goes'));
      expect(find.text('Pick who goes'), findsOneWidget);
      await tester.tap(find.text('Pick who goes'));
      // Nothing to assert but the absence of a crash — and that it stayed put.
      expect(find.text('Pick who goes'), findsOneWidget);
    });

    testWidgets('the sub-line carries the second fact', (tester) async {
      await pump(
        tester,
        ParchmentButton(label: '🪙 40', sub: 'finish now', onTap: () {}),
      );
      expect(find.text('🪙 40'), findsOneWidget);
      expect(find.text('finish now'), findsOneWidget);
    });
  });

  group('ParchmentCard', () {
    testWidgets('a muted card still shows its content', (tester) async {
      // Blocked targets are dimmed, never hidden: knowing WHICH spot is mined
      // out is what makes the regrow rate meaningful.
      await pump(
        tester,
        const ParchmentCard(muted: true, child: Text('Mined out')),
      );
      expect(find.text('Mined out'), findsOneWidget);
    });

    testWidgets('taps through to onTap', (tester) async {
      var taps = 0;
      await pump(
        tester,
        ParchmentCard(onTap: () => taps++, child: const Text('Gather wood')),
      );
      await tester.tap(find.text('Gather wood'));
      expect(taps, 1);
    });

    testWidgets('without onTap it is not a button', (tester) async {
      await pump(tester, const ParchmentCard(child: Text('x')));
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  testWidgets('the section header shows its title and hint', (tester) async {
    await pump(
      tester,
      const ParchmentSectionHeader(title: 'Out now', hint: '2 on the road'),
    );
    expect(find.text('OUT NOW'), findsOneWidget); // headers are set in caps
    expect(find.text('2 on the road'), findsOneWidget);
  });

  group('ParchmentInfoButton', () {
    // The ⓘ exists so a screen can DROP reference material from the page (user
    // 2026-07-30, on the hunt sheet). Two things have to hold for that trade to
    // be honest: the content is still reachable, and it is built fresh — the
    // hunt's odds shift with the variant chosen a moment ago.
    testWidgets('opens its content and closes again', (tester) async {
      await pump(
        tester,
        ParchmentInfoButton(
          title: 'Find odds',
          content: (_) => const [Text('Rare 20 %')],
        ),
      );
      expect(find.text('Rare 20 %'), findsNothing);
      await tester.tap(find.text('i'));
      await tester.pumpAndSettle();
      expect(find.text('Find odds'), findsOneWidget);
      expect(find.text('Rare 20 %'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Rare 20 %'), findsNothing);
    });

    testWidgets('the content is rebuilt on every open, never captured',
        (tester) async {
      var opens = 0;
      await pump(
        tester,
        ParchmentInfoButton(
          title: 'Find odds',
          content: (_) => [Text('open #${++opens}')],
        ),
      );
      for (final expected in ['open #1', 'open #2']) {
        await tester.tap(find.text('i'));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('it rides in a section header', (tester) async {
      await pump(
        tester,
        ParchmentSectionHeader(
          title: 'Hunt length',
          trailing: ParchmentInfoButton(title: 'x', content: (_) => const []),
        ),
      );
      expect(find.text('HUNT LENGTH'), findsOneWidget);
      expect(find.text('i'), findsOneWidget);
    });
  });

  group('parchmentConfirm', () {
    Future<void> open(WidgetTester tester, void Function(bool) onResult) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => onResult(
                  await parchmentConfirm(
                    context,
                    title: 'Recall expedition?',
                    message: 'Frees them with no reward.',
                    confirmLabel: 'Recall',
                    danger: true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('confirming answers true', (tester) async {
      bool? result;
      await open(tester, (r) => result = r);
      expect(find.text('Recall expedition?'), findsOneWidget);
      await tester.tap(find.text('Recall'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('the default action is to KEEP — recall is destructive',
        (tester) async {
      bool? result;
      await open(tester, (r) => result = r);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });
  });
}
