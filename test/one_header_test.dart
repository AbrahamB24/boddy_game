import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:boddygame/core/theme/parchment_theme.dart';
import 'package:boddygame/features/common/widgets/parchment_page.dart';
import 'package:boddygame/features/settlement/widgets/parchment_sheet.dart';

// ── Ein Header, überall (user 2026-07-31) ───────────────────
// "überall wo es einen header hat, soll dieser immer genau gleich aussehen"
//
// Five screens had grown their own bar — a flat box here, a 48-px container
// there, each with its own padding, title size and back button. They all use
// [ParchmentHeader] now, and Dev Mode's plain Material AppBars are dressed as
// the same band by the THEME. What is pinned here is that second half: a theme
// value that drifts from the band is exactly how a "shared" look comes apart
// again, and nothing else would catch it.
//
// A SHEET WEARS IT TOO (user 2026-08-01: "Das Header Band wollte ich
// behalten"). What a sheet does NOT wear is the grab handle that used to sit
// above it — a bar hinting at a gesture the whole surface already answers.
void main() {
  // The theme builds Google-font text styles, so it has to be built INSIDE a
  // test — at main() level google_fonts fires an HTTP fetch outside the test
  // zone and the whole file fails to load.
  TestWidgetsFlutterBinding.ensureInitialized();
  // No network in a test: google_fonts otherwise fires an HTTP fetch for the
  // app's typeface and fails whichever test happens to be running when it lands.
  GoogleFonts.config.allowRuntimeFetching = false;


  testWidgets('the Material app bar IS the app band', (tester) async {
    // A widget test, not a plain one: building the theme touches the app's
    // Google font, and outside a widget test's zone that fetch takes the whole
    // FILE down rather than the assertion it belongs to.
    late AppBarThemeData bar;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildParchmentTheme(),
        home: Builder(
          builder: (context) {
            bar = Theme.of(context).appBarTheme;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(bar.backgroundColor, ParchmentHeader.bandFill);
    expect(bar.foregroundColor, ParchmentHeader.engravedInk);
    expect(bar.iconTheme?.color, ParchmentHeader.engravedInk);
    // Same lettering, down to the engraving.
    final title = bar.titleTextStyle!;
    final band = ParchmentHeader.titleStyle();
    expect(title.color, band.color);
    expect(title.fontSize, band.fontSize);
    expect(title.shadows?.length, band.shadows?.length);
  });

  test('the band is FLAT — no gradient anywhere on it', () {
    // User 2026-07-31: "alle header sollen keine Farbverlauf haben".
    expect(ParchmentHeader.bandFill, isA<Color>());
    final bar = ParchmentHeader.band(child: const SizedBox(), height: 52);
    final decoration = (bar as Container).decoration as BoxDecoration;
    expect(decoration.gradient, isNull);
    expect(decoration.color, ParchmentHeader.bandFill);
  });

  testWidgets('a page and a bar built by hand cannot differ', (tester) async {
    // The header is one widget, so "the same" is a property of the code rather
    // than of six screens agreeing — this just proves the page uses it.
    await tester.pumpWidget(
      const MaterialApp(
        home: ParchmentPage(title: 'Anything', child: SizedBox.expand()),
      ),
    );
    expect(find.byType(ParchmentHeader), findsOneWidget);
    final header = tester.widget<ParchmentHeader>(find.byType(ParchmentHeader));
    expect(header.title, 'Anything');
    expect(header.showBack, isTrue);
  });

  // ── Low poly (user 2026-07-31) ──
  // "alles soll im low poly flatdesign sein, so wie dieses Monster"
  //
  // The Material widgets nobody restyled by hand — dialogs, menus, cards,
  // snackbars, buttons — are faceted by the THEME. That is the same lever the
  // dark flip used, and the same failure mode: one shape left rounded in here
  // and the app has a single soft corner nobody can find.
  testWidgets('every themed surface is cut, not curved', (tester) async {
    late ThemeData t;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildParchmentTheme(),
        home: Builder(
          builder: (context) {
            t = Theme.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(t.cardTheme.shape, isA<BeveledRectangleBorder>());
    expect(t.dialogTheme.shape, isA<BeveledRectangleBorder>());
    expect(t.popupMenuTheme.shape, isA<BeveledRectangleBorder>());
    expect(t.snackBarTheme.shape, isA<BeveledRectangleBorder>());
  });

  testWidgets('a sheet wears the band, but no grab handle', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ParchmentSheet(
            title: 'Wood',
            builder: (_, c) => ListView(controller: c),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Wood'), findsOneWidget);
    // The band names it, exactly as a page's does.
    expect(find.byType(ParchmentHeader), findsNothing,
        reason: 'a sheet uses the BAND, not the whole header widget');
    // …and nothing sits above that band: the handle was a bar spending a row
    // to hint at a drag the entire sheet accepts.
    final column = tester.widget<Column>(
      find.descendant(
        of: find.byType(ParchmentSheet),
        matching: find.byType(Column),
      ).first,
    );
    expect(column.children.first, isA<Container>(),
        reason: 'the band is the first thing on the sheet');
  });
}
