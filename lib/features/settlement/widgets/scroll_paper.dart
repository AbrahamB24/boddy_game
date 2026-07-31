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
const Color kParchmentLight = Color(0xFF1F262C); // the sheet
const Color kParchmentMid = Color(0xFF161B20); // its shade / the page ground
const Color kParchmentDeep = Color(0xFF2A333A); // the band, the roller
const Color kParchmentShade = Color(0xFF0F1418); // deepest — under an edge
const Color kParchmentInk = Color(0xFFEDE3CB); // what you write with

/// WHAT A RAISED THING CASTS. Its own constant since the theme went dark (user
/// 2026-07-31): every shadow in the app used to be [kParchmentInk] at a low
/// alpha, which was right while the ink was the darkest thing around — and the
/// moment the ink became cream, every one of those shadows would have started
/// painting a pale halo under the card it was meant to ground.
const Color kPageShadow = Color(0xFF000000);

// ── Parchment buttons (user 2026-07-23) ──
// ONE tappable-pill look for both the Build menu and the building dialog, so
// every button matches the scroll. SOLID green when live (no gradient, no
// border — just the fill), faded parchment when not. Use [parchmentButton] for
// the surface and [parchmentButtonInk] for whatever sits on it.
/// The settlement's action green — the button fill (user 2026-07-23: the lawn
/// green of the map, a lighter olive than the old forest green). [Deep] is a
/// shade under it for recesses.
const Color kActionGreen = Color(0xFF8C9A3C);
const Color kActionGreenDeep = Color(0xFF6C7A2C);

ShapeDecoration parchmentButton({bool active = true}) => ShapeDecoration(color: active ? kActionGreen : kParchmentInk.withValues(alpha: 0.10), shape: FoE.facet(radius: 12));

/// Ink on a [parchmentButton]: near-white on the green when live, faint brown
/// when not.
Color parchmentButtonInk({bool active = true}) =>
    active ? const Color(0xFFF3F7EF) : kParchmentInk.withValues(alpha: 0.45);

// kNavRollerDrop lived here: how far the nav bar's foot was clipped off the
// bottom edge, shared so the fixed bar and the Build popup's copy of it stayed
// aligned. Both bars are gone (user 2026-07-29), and so is the constant.
