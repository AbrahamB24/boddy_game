import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/auth/auth_screens.dart';

// The front door (user 2026-09-20, "Variante 1, Karte rechts, im Holz"): layout
// smoke tests at the landscape size, and the checks that need no server.
void main() {
  Future<void> open(WidgetTester t, Widget screen) async {
    t.view.physicalSize = const Size(932, 430);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: screen));
    await t.pumpAndSettle();
  }

  testWidgets('sign in: the name, the tagline, the fields and the button', (
    t,
  ) async {
    await open(t, const LoginScreen());
    expect(find.text('Bøddy Game'), findsOneWidget);
    expect(find.text(kGameTagline), findsOneWidget);
    expect(find.text('EMAIL'), findsOneWidget);
    expect(find.text('PASSWORD'), findsOneWidget);
    expect(find.text('REPEAT PASSWORD'), findsNothing);
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Sign in'), findsNWidgets(2)); // the switch and the button
  });

  testWidgets('Register adds the repeat field and the Create account button', (
    t,
  ) async {
    await open(t, const LoginScreen());
    await t.tap(find.text('Register'));
    await t.pumpAndSettle();
    expect(find.text('REPEAT PASSWORD'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Forgot password?'), findsNothing);
  });

  testWidgets('registering with two different passwords says so', (t) async {
    await open(t, const LoginScreen());
    await t.tap(find.text('Register'));
    await t.pumpAndSettle();
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'a@b.ch');
    await t.enterText(fields.at(1), 'secret1');
    await t.enterText(fields.at(2), 'secret2');
    await t.tap(find.text('Create account'));
    await t.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('Forgot password opens a small dialog that Cancel closes', (
    t,
  ) async {
    await open(t, const LoginScreen());
    await t.enterText(find.byType(TextField).first, 'me@x.ch');
    await t.tap(find.text('Forgot password?'));
    await t.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    // Pre-filled from the form.
    expect(find.text('me@x.ch'), findsNWidgets(2));
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Reset password'), findsNothing);
  });

  testWidgets('the new-password page checks length and match before asking', (
    t,
  ) async {
    await open(t, ResetPasswordScreen(onDone: () {}));
    expect(find.text('Choose a new password'), findsOneWidget);
    final fields = find.byType(TextField);
    await t.enterText(fields.at(0), 'abc');
    await t.tap(find.text('Save password'));
    await t.pumpAndSettle();
    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
    await t.enterText(fields.at(0), 'abcdef');
    await t.enterText(fields.at(1), 'abcdeg');
    await t.tap(find.text('Save password'));
    await t.pumpAndSettle();
    expect(find.text('Passwords do not match.'), findsOneWidget);
  });
}
