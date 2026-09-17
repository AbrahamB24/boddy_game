import 'package:flutter/material.dart';

import '../../core/theme/foe_theme.dart';
import '../common/widgets/parchment_kit.dart' show ParchmentDivider;
import '../common/widgets/parchment_page.dart';
import 'friends_tab.dart';
import 'messages_tab.dart';
import 'pvp_tab.dart';
import 'ranking_feed_tab.dart';

/// The Social hub: Friends / Messages / PvP / Ranking & Feed, tabbed like
/// [ManagementScreen] (settlement/management_screen.dart) — the same shape
/// used everywhere else in the app for "one screen, several drawers".
class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: 'Social',
    child: Column(
      children: [
        TabBar(
          controller: _tabs,
          labelColor: FoE.gold,
          unselectedLabelColor: FoE.textDim,
          indicatorColor: FoE.gold,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Messages'),
            Tab(text: 'PvP'),
            Tab(text: 'Ranking'),
          ],
        ),
        const ParchmentDivider(),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: const [FriendsTab(), MessagesTab(), PvpTab(), RankingFeedTab()],
          ),
        ),
      ],
    ),
  );
}
