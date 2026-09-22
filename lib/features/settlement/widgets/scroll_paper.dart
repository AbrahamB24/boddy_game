import 'package:flutter/material.dart';
import '../../../core/theme/foe_theme.dart';

// ── Die Schriftrolle ist weg (user 2026-07-31) ──
// "alles soll im low poly flatdesign sein"
//
// This file used to carry the Build menu's scroll: an SVG banner parsed into
// paths, with a wooden roller shaded by three-stop gradients. Nothing has drawn
// it since the Build menu became a page (2026-07-31), and a lit wooden dowel is
// the exact opposite of flat shading — so the artwork, its parser and its
// painter are gone. What is left is what the rest of the app actually uses: the
// tone ladder and the button.

// ── Die Töne des Papiers ──────────────────────────────────
// DARK since 2026-07-31 (user: "setzte das ganze app in den darkmode"). The
// names are the page's PARTS — the sheet, its shade, the roller, the ink — and
// they keep working because every one of them is a role: the "ink" is whatever
// you write on the sheet with, and on dark stock that is cream.
//
// Kept as one ladder, lightest to deepest, so the scroll's own painter still
// gets a lit sheet and a darker roller without knowing the theme flipped.
//
// ALIASED to FoE's own steps (2026-09-05 blue/warm reskin), rather than a
// second set of literals duplicating them: this file used to hardcode its own
// copy of the exact same graphite ladder, which is exactly why the palette
// swap in foe_theme.dart didn't reach any of these 19 call sites the first
// time (user: "es gibt noch sehr viele Hintergründe, mäanderband und buttons,
// welche nicht übernommen wurden"). ONE PLACE means this file asks FoE for the
// role instead of owning a competing answer.
const Color kParchmentLight = FoE.panelMid; // the sheet
const Color kParchmentMid = FoE.bg; // its shade / the page ground
const Color kParchmentDeep = FoE.panelLight; // the band, the roller
const Color kParchmentShade = Color(
  0xFF0C2841,
); // FoE.bg, shaded — deepest, under an edge
const Color kParchmentInk = FoE.parchment; // what you write with

/// WHAT A RAISED THING CASTS. Its own constant since the theme went dark (user
/// 2026-07-31): every shadow in the app used to be [kParchmentInk] at a low
/// alpha, which was right while the ink was the darkest thing around — and the
/// moment the ink became cream, every one of those shadows would have started
/// painting a pale halo under the card it was meant to ground.
const Color kPageShadow = Color(0xFF000000);

// ── Parchment buttons (user 2026-07-23) ──
// ONE tappable-pill look for both the Build menu and the building dialog, so
// every button matches the scroll. SOLID fill when live (no gradient, no
// border — just the fill), faded parchment when not. Use [parchmentButton] for
// the surface and [parchmentButtonInk] for whatever sits on it.
/// The settlement's action colour — the button fill (was the lawn green of
/// the map, then cyan-blue; green again since 2026-09-22, [FoE.positive]).
const Color kActionGreen = FoE.positive;

ShapeDecoration parchmentButton({bool active = true}) => ShapeDecoration(
  color: active ? kActionGreen : kParchmentInk.withValues(alpha: 0.10),
  shape: FoE.facet(radius: 12),
);

/// Ink on a [parchmentButton]: dark on the fill when live (the fill is
/// bright enough — coral, then this cyan-blue — that the old near-white ink
/// it originally paired with, tuned for a much darker olive green, would
/// read as low-contrast light-on-light), faint brown when not.
Color parchmentButtonInk({bool active = true}) =>
    active ? FoE.bg : kParchmentInk.withValues(alpha: 0.45);

// kNavRollerDrop lived here: how far the nav bar's foot was clipped off the
// bottom edge, shared so the fixed bar and the Build popup's copy of it stayed
// aligned. Both bars are gone (user 2026-07-29), and so is the constant.
