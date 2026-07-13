import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Forge-of-Empires-inspired design tokens for the settlement feature.
class FoE {
  FoE._();

  // ── Colours ───────────────────────────────────────────────
  static const bg = Color(0xFF0C0804);
  static const panelDark = Color(0xFF19110A);
  static const panelMid = Color(0xFF22180C);
  static const panelLight = Color(0xFF2E2212);
  static const border = Color(0xFF4A3410);
  static const borderGold = Color(0xFF7A5414);
  static const gold = Color(0xFFC49A28);
  static const goldBright = Color(0xFFECC040);
  static const parchment = Color(0xFFD8C088);
  static const textDim = Color(0xFF7A6038);
  static const textMuted = Color(0xFF4A3820);
  static const mapBase = Color(0xFF18260E);
  static const mapAlt = Color(0xFF1C2E12);
  static const mapGrid = Color(0x0AFFFFFF);
  static const danger = Color(0xFF8B2020);
  static const positive = Color(0xFF2A5A18);

  // ── Gradients ─────────────────────────────────────────────
  static const panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [panelMid, panelDark],
  );

  static const topBarGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A1E0C), Color(0xFF180E06)],
  );

  // ── Decorations ───────────────────────────────────────────
  static BoxDecoration panel({
    double radius = 8,
    Color? overrideBorder,
    bool glow = false,
  }) => BoxDecoration(
    gradient: panelGradient,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: overrideBorder ?? borderGold, width: 1.5),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.6),
        blurRadius: 8,
        offset: const Offset(1, 4),
      ),
      if (glow)
        BoxShadow(
          color: gold.withValues(alpha: 0.25),
          blurRadius: 12,
          spreadRadius: 1,
        ),
    ],
  );

  static BoxDecoration btn({bool active = false}) => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: active ? [panelLight, panelMid] : [panelMid, panelDark],
    ),
    borderRadius: BorderRadius.circular(6),
    // Border.all (uniform color) is required to combine with borderRadius
    border: Border.all(color: active ? goldBright : borderGold, width: 1.5),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.5),
        blurRadius: 4,
        offset: const Offset(1, 3),
      ),
    ],
  );

  static const topBarDecor = BoxDecoration(
    gradient: topBarGradient,
    border: Border(bottom: BorderSide(color: border, width: 1)),
  );

  static BoxDecoration sideBarDecor = const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [panelMid, panelDark],
    ),
    border: Border(left: BorderSide(color: border, width: 1)),
  );

  // ── Typography ────────────────────────────────────────────
  static TextStyle title({double size = 14}) => GoogleFonts.cinzel(
    color: goldBright,
    fontSize: size,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.8,
  );

  static TextStyle value({double size = 13}) => GoogleFonts.outfit(
    color: Colors.white,
    fontSize: size,
    fontWeight: FontWeight.w700,
  );

  static TextStyle label({double size = 11}) => GoogleFonts.outfit(
    color: parchment,
    fontSize: size,
    fontWeight: FontWeight.w500,
  );

  static TextStyle dim({double size = 10}) =>
      GoogleFonts.outfit(color: textDim, fontSize: size);

  // ── Divider ───────────────────────────────────────────────
  static Widget divider({double vPad = 4}) => Padding(
    padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 8),
    child: Container(height: 1, color: border),
  );
}
