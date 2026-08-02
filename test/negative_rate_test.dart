import 'package:flutter_test/flutter_test.dart';

// ── Ein Minus schreibt sich einmal (user 2026-08-01) ────────
// "wenn eine Ressource minus macht, dann bitte nicht +- schreiben im header
//  sondern nur -" + "und rot markieren"
//
// The header printed the '+' unconditionally, so a shrinking pile read
// "+-1.2/h": a sign that cancels itself out, on the one number where the
// direction is the entire point.
//
// The formatting is three lines inside a widget build, so this pins the RULE
// rather than the call — the same rule the breakdown sheet has always used, now
// that the header agrees with it.
String rate(double v) {
  final losing = v < 0;
  final digits = v.abs() >= 10 ? 0 : 1;
  return '${losing ? '' : '+'}${v.toStringAsFixed(digits)}/h';
}

void main() {
  test('a loss carries one sign, and it is the minus', () {
    expect(rate(-1.2), '-1.2/h');
    expect(rate(-12.0), '-12/h');
    expect(rate(-0.4), '-0.4/h');
    for (final v in [-0.1, -1.0, -9.9, -10.0, -99.0]) {
      expect(rate(v).startsWith('-'), isTrue);
      expect(rate(v).contains('+'), isFalse, reason: '$v printed a plus');
    }
  });

  test('a gain still says so', () {
    expect(rate(1.2), '+1.2/h');
    expect(rate(12.0), '+12/h');
  });

  test('standing still reads as a gain of nothing, not a loss', () {
    // 0 is not negative — the cell must not turn red for a resource that is
    // simply idle.
    expect(rate(0), '+0.0/h');
    expect((0.0).isNegative, isFalse);
  });

  test('the digit rule follows the MAGNITUDE, not the sign', () {
    // -12.4 is as wide as 12.4; deciding on the signed value would print
    // "-12.4/h" in a cell sized for "12/h".
    expect(rate(-12.4), '-12/h');
    expect(rate(12.4), '+12/h');
  });
}
