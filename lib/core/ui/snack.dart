import 'package:flutter/material.dart';

import '../theme/foe_theme.dart';

/// THE way to show a one-line message.
///
/// This replaced six hand-copied `_snack` helpers — and only ONE of them
/// guarded `mounted`. That's the real cost of copy-paste: somebody hit a
/// "context used after dispose" crash, fixed it where they found it, and the
/// other five copies kept the bug. Every one of those sites fires after an
/// `await` (a resource spend, a network write), so the widget genuinely can be
/// gone by the time the message lands.
extension SnackX on BuildContext {
  /// Shows [message]. Silently does nothing if this context is no longer
  /// mounted — the guard the copies were missing.
  void snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message, style: FoE.label(size: 13)),
        backgroundColor: error ? FoE.danger : FoE.panelDark,
      ),
    );
  }
}
