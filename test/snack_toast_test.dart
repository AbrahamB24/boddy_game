import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/core/ui/snack.dart';

// Messages are back (user 2026-11-02: "Meldungen dürfen wieder kommen") —
// context.snack was a no-op from 2026-08-29 until then.
void main() {
  testWidgets('a message shows, and a new one replaces it', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    ctx.snack('Not enough gold');
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Not enough gold'), findsOneWidget);

    ctx.snack('Settlement full', error: true);
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Not enough gold'), findsNothing);
    expect(find.text('Settlement full'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('it shows above an open dialog', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        content: Builder(
          builder: (inner) => TextButton(
            onPressed: () => inner.snack('From the dialog'),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('go'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('From the dialog'), findsOneWidget);
  });
}
