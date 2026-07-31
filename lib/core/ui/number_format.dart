// ── Big numbers, читаемые at a glance (user 2026-07-30) ──────
// This lived as a private `_short` in settlement_screen, so ONLY the resource
// header spoke it: the header said "96k" while the building dialog under it said
// "96000" for the very same store. Two renderings of one number on one screen.
//
// Hoisted here so every surface that shows a game figure — ceilings, upgrade
// rows, breakdown sheets, market prices — reads the same way.

/// A magnitude, short: `840`, `1.2k`, `12k`, `1.4M`.
///
/// Under 1 000 nothing is abbreviated (those digits are a figure you read); from
/// 1 000 up they are a magnitude, and one decimal is kept until the number is
/// long enough that the decimal is noise. Negative values keep their sign.
String shortNumber(num value) {
  final v = value.toDouble();
  final n = v.abs();
  if (n >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (n >= 10000) return '${(v / 1000).toStringAsFixed(0)}k';
  if (n >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

/// [shortNumber] for a number that is only WORTH shortening when it gets big —
/// exact below [from], abbreviated above it.
///
/// Used where the exact figure matters up close (a cost you are about to pay)
/// but the digits stop being informative once they run long.
String shortNumberAbove(num value, {num from = 10000}) =>
    value.abs() >= from ? shortNumber(value) : value.toDouble().toStringAsFixed(0);
