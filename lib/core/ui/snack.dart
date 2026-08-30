import 'package:flutter/material.dart';

/// THE call site for a one-line message — deliberately a NO-OP now (user
/// 2026-08-29: "bitte wirklich alle pop up nachrichten, notifications die am
/// unteren rand auftauchen nach gewissen aktionen löschen").
///
/// Kept as a real method, not deleted, so the ~20 call sites across the app
/// (breeding, expeditions, healing, hatchery, evolution, teams…) don't all
/// need touching one by one for what is the SAME request everywhere: stop
/// popping a SnackBar. If a specific one of those messages needs to come
/// back later in some OTHER form (inline error text, a dialog), that is a
/// call-site decision to make then — this file is just off.
extension SnackX on BuildContext {
  void snack(String message, {bool error = false}) {}
}
