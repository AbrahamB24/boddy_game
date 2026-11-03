import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../creatures/expeditions_screen.dart';

/// The settlement's expeditions hub — reachable from the main screen's
/// "Manage" button. Renders the exact same [ExpeditionsBody] the standalone
/// [ExpeditionsScreen] does, under its own title/entry point — see that
/// file's own doc comment for the screen's layout history.
///
/// A MENU over the dimmed map, built from the cream kit like the building
/// dialog (user 2026-09-18) — push it with [pushMenu].
class ManagementScreen extends StatelessWidget {
  const ManagementScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const MenuScaffold(title: 'Expedition', child: ExpeditionsBody());
}
