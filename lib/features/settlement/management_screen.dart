import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_kit.dart' show ParchmentDivider;
import '../common/widgets/parchment_page.dart';
import '../creatures/expeditions_screen.dart';

/// The settlement's expeditions hub, tabbed by what you'd go looking for
/// (2026-09-11 redesign). Work and Housing moved off this screen entirely —
/// the Castle (and, for Housing, every sheltering building) already opens
/// each of those directly as its own screen, so keeping them here too was a
/// second, redundant door. That freed the tab bar for the three target
/// drawers [ExpeditionsBody] used to bury inside one Trips tab, promoted to
/// tabs in their own right, plus a Trips tab of its own for what is already
/// out.
class ManagementScreen extends StatefulWidget {
  /// Which tab to land on: 0 Resources, 1 Hunt, 2 Trips.
  ///
  /// Luxury folded into Resources (user 2026-09-12) — see
  /// [ExpeditionTargetCategory]'s own doc comment. A caller still passing the
  /// old index 3 (Trips) lands one tab short of where it meant to; there are
  /// no such callers left in this codebase, but [initialTab]'s default is
  /// updated too so a future one reads correctly by default.
  final int initialTab;

  const ManagementScreen({super.key, this.initialTab = 2});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 2),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Management',
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: FoE.gold,
          unselectedLabelColor: FoE.textDim,
          indicatorColor: FoE.gold,
          tabs: const [
            Tab(text: 'Resources'),
            Tab(text: 'Hunt'),
            Tab(text: 'Trips'),
          ],
        ),
        // The app's own section rule (user 2026-08-31) — see
        // [ParchmentDivider] for why it stops short of the bands.
        const ParchmentDivider(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [
              ExpeditionsBody(onlyCategory: ExpeditionTargetCategory.resources),
              ExpeditionsBody(onlyCategory: ExpeditionTargetCategory.hunt),
              ExpeditionsBody(onlyTrips: true),
            ],
          ),
        ),
      ],
    ),
  );
}
