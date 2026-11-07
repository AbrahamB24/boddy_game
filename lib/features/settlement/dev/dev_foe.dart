import 'package:flutter/material.dart';

import '../../../core/theme/cream_kit.dart';
import '../../../core/theme/voxel_kit.dart' show vr;

/// THE DEV FORMS' PALETTE, in the cream kit (user 2026-09-20, "Dev Mode
/// Variante 3").
///
/// Every dev file used to `import foe_theme.dart` and reach for `FoE.label`,
/// `FoE.parchment`, `FoE.panel()` … — light text and dark panels for a dark app.
/// The dev screens now sit on the Holz kit's cream cards, so instead of editing
/// four hundred call sites they import THIS file: same class name, same
/// members, cream values. A form that still says `FoE.parchment` gets ink, one
/// that says `FoE.panelMid` gets a light tile.
///
/// Only the members the dev files use are here; add one when a form needs it.
abstract final class FoE {
  // ── Surfaces ──
  /// The page under a form (the cream card).
  static const Color bg = CreamPalette.paperTop;

  /// A sunken well: tags, a dialog's own ground, a dropdown's menu.
  static const Color panelDark = CreamPalette.paperBottom;

  /// A raised tile.
  static const Color panelMid = CreamPalette.tileTop;

  /// A quiet button's fill.
  static const Color panelLight = CreamPalette.tileBottom;

  // ── Ink ──
  /// The main text colour (it was the parchment on the dark theme).
  static const Color parchment = kBoxInk;

  /// Secondary text.
  static const Color textDim = Color(0xC72A1A0C);

  /// Faint text and disabled things.
  static const Color textMuted = Color(0x802A1A0C);

  /// The accent as TEXT and as a line: a warm brown, legible on cream.
  static const Color gold = CreamPalette.accent;
  static const Color goldBright = Color(0xFF7C532C);
  static const Color accentBlue = CreamPalette.accent;

  static const Color danger = CreamPalette.warn;
  static const Color positive = CreamPalette.better;

  /// Ink for a label sitting on a GOLD fill (it was white on the lawn green).
  static const Color onGold = kBoxInk;

  // ── Lines ──
  static const Color border = Color(0x8C9C6B3E);
  static const Color borderGold = CreamPalette.goldDeep;

  // ── Shapes ──
  static const double radius = 12;

  static RoundedRectangleBorder facet({
    double radius = FoE.radius,
    BorderSide side = BorderSide.none,
  }) => RoundedRectangleBorder(
    borderRadius: vr(radius),
    side: side,
  );

  /// A raised light tile with a hairline and a hard tan shadow.
  static ShapeDecoration panel({
    double radius = FoE.radius,
    Color? overrideBorder,
    bool glow = false,
  }) => ShapeDecoration(
    color: panelMid,
    shape: facet(
      radius: radius,
      side: BorderSide(color: overrideBorder ?? border, width: 1),
    ),
    shadows: const [
      BoxShadow(color: CreamPalette.tanShadow, offset: Offset(0, 2)),
    ],
  );

  /// A button: gold when [active], a light tile otherwise.
  static ShapeDecoration btn({bool active = false}) => ShapeDecoration(
    color: active ? CreamPalette.gold : panelLight,
    shape: facet(radius: 11),
    shadows: [
      BoxShadow(
        color: active ? CreamPalette.goldDeep : CreamPalette.tanShadow,
        offset: const Offset(0, 2),
      ),
    ],
  );

  // ── Text ──
  static TextStyle title({double size = 14}) => TextStyle(
    color: kBoxInk,
    fontSize: size + 2,
    fontWeight: FontWeight.w400,
    height: 1.2,
    decoration: TextDecoration.none,
  );

  static TextStyle value({double size = 13}) => TextStyle(
    color: kBoxInk,
    fontSize: size + 1,
    fontWeight: FontWeight.w400,
    height: 1.25,
    decoration: TextDecoration.none,
  );

  static TextStyle label({double size = 11}) => TextStyle(
    color: kBoxInk,
    fontSize: size + 1,
    fontWeight: FontWeight.w400,
    height: 1.4,
    decoration: TextDecoration.none,
  );

  static TextStyle dim({double size = 10}) => TextStyle(
    color: textDim,
    fontSize: size + 1,
    fontWeight: FontWeight.w400,
    height: 1.35,
    decoration: TextDecoration.none,
  );
}
