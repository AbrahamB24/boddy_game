import 'package:flutter/material.dart' hide Text;

import '../../../core/theme/cream_kit.dart';
import '../../../core/ui/pressable.dart';
import '../../common/widgets/parchment_page.dart';
import '../../creatures/services/creature_defs_controller.dart';
import '../services/game_defs_controller.dart';
import 'dev_abilities_view.dart';
import 'dev_actions_page.dart';
import 'dev_budgets_view.dart';
import 'dev_lists.dart';
import 'dev_theme.dart';
import 'gather_defs_tab.dart';
import 'path_editor_tab.dart';
import '../../../core/theme/voxel_kit.dart' show vr;
import '../../../core/theme/voxel_icons.dart';
import '../../../core/ui/game_text.dart';

/// The menus, top to bottom on the rail.
enum _Menu {
  monster('🐾', 'Monster'),
  campaign('🗺', 'Kampagne'),
  buildings('🏠', 'Gebäude'),
  items('🎒', 'Items'),
  resources('⛏', 'Ressourcen'),
  actions('🛠', 'Aktionen');

  final String glyph;
  final String label;
  const _Menu(this.glyph, this.label);

  /// The sub-pages a menu has (shown as a switch in the wood band).
  List<String> get subs => switch (this) {
    _Menu.monster => const ['Arten', 'Abilities', 'Budgets & Grenzen'],
    _Menu.campaign => const ['Pfad', 'Gebiete'],
    _ => const [],
  };
}

/// DEV MODE, "Variante 3" (user 2026-09-20): a rail of menus on the left, and per
/// menu either a list with its form beside it (species, buildings, items, areas)
/// or one page (path, resources, actions, the read-only abilities and budgets).
///
/// What is NOT here any more, on purpose (user 2026-09-20: "wirklich nur das
/// Wichtigste übernehmen"): the ability and budget editors (now read-only pages
/// with an explanation — changes go through a request), the combat lab and the
/// balance matrix, the dial pages ("Werte") and the export sheet. Every dev
/// button that used to sit inside a player's screen is on the Actions page.
class DevModeScreen extends StatefulWidget {
  const DevModeScreen({super.key});

  @override
  State<DevModeScreen> createState() => _DevModeScreenState();
}

class _DevModeScreenState extends State<DevModeScreen> {
  _Menu _menu = _Menu.monster;
  int _sub = 0;

  void _pick(_Menu m) {
    if (m == _menu) return;
    setState(() {
      _menu = m;
      _sub = 0;
    });
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildDevModeTheme(),
    child: Scaffold(
      backgroundColor: CreamPalette.groundBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: kMenuGround),
        child: SafeArea(
          child: Column(
            children: [
              _band(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _rail(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
                        // Rebuilt on def edits and realtime, so a saved species
                        // or building shows in its list without reopening.
                        child: AnimatedBuilder(
                          animation: Listenable.merge([
                            CreatureDefsController(),
                            GameDefsController(),
                          ]),
                          builder: (context, _) => _content(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  // ── Frame ─────────────────────────────────────────────────

  Widget _band() => ParchmentHeader.band(
    height: 46,
    fill: CreamPalette.groundTop,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Pressable(
            onTap: () => Navigator.maybePop(context),
            child: Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                shape: BoxShape.rectangle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [CreamPalette.tileTop, CreamPalette.tileBottom],
                ),
                boxShadow: [
                  BoxShadow(
                    color: CreamPalette.tanShadow,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const PixelIcon(
                Icons.chevron_left_rounded,
                size: 22,
                color: kBoxInk,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Dev Mode',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: CreamPalette.paperTop,
            ),
          ),
          const SizedBox(width: 14),
          if (_menu.subs.isNotEmpty) _subSwitch(),
          const Spacer(),
        ],
      ),
    ),
  );

  /// The menu's sub-pages: a sand track in the band, the live one gold.
  Widget _subSwitch() => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.22),
      borderRadius: vr(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _menu.subs.length; i++)
          Pressable(
            onTap: () => setState(() => _sub = i),
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: i == _sub
                  ? BoxDecoration(
                      color: CreamPalette.gold,
                      borderRadius: vr(9),
                      boxShadow: const [
                        BoxShadow(
                          color: CreamPalette.goldDeep,
                          offset: Offset(0, 2),
                        ),
                      ],
                    )
                  : null,
              child: Text(
                _menu.subs[i],
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: i == _sub
                      ? kBoxInk
                      : CreamPalette.paperTop.withValues(alpha: 0.85),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _rail() => Container(
    width: 68,
    padding: const EdgeInsets.fromLTRB(5, 8, 5, 8),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4A3019), Color(0xFF2E1C0D)],
      ),
    ),
    child: SingleChildScrollView(
      child: Column(
        children: [
          for (final m in _Menu.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Pressable(
                onTap: () => _pick(m),
                child: Container(
                  height: 52,
                  alignment: Alignment.center,
                  decoration: m == _menu
                      ? BoxDecoration(
                          color: CreamPalette.gold,
                          borderRadius: vr(11),
                          boxShadow: const [
                            BoxShadow(
                              color: CreamPalette.goldDeep,
                              offset: Offset(0, 3),
                            ),
                          ],
                        )
                      : BoxDecoration(
                          color: CreamPalette.paperTop.withValues(alpha: 0.08),
                          borderRadius: vr(11),
                        ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(m.glyph, style: const TextStyle(fontSize: 17)),
                      const SizedBox(height: 1),
                      Text(
                        m.label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w400,
                          color: m == _menu ? kBoxInk : CreamPalette.paperTop,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  // ── Pages ─────────────────────────────────────────────────

  Widget _content() => switch (_menu) {
    _Menu.monster => switch (_sub) {
      0 => DevMasterDetail(
        key: const ValueKey('species'),
        hint: 'Wähle links eine Art — oder «+ New» für eine neue.',
        list: (context, open, selected) =>
            SpeciesListPane(open: open, selected: selected),
      ),
      1 => const DevAbilitiesView(),
      _ => const DevBudgetsView(),
    },
    _Menu.campaign =>
      _sub == 0
          ? _card(
              // Reorderable battle nodes with enemies + rewards. Rebuilds on def
              // edits/realtime so a saved node shows.
              const PathEditorTab(),
            )
          : DevMasterDetail(
              key: const ValueKey('areas'),
              hint: 'Wähle links ein Gebiet — oder «+ New».',
              list: (context, open, selected) => areasListPane(open, selected),
            ),
    _Menu.buildings => DevMasterDetail(
      key: const ValueKey('buildings'),
      hint: 'Wähle links ein Gebäude — oder «+ New».',
      list: (context, open, selected) =>
          BuildingsListPane(open: open, selected: selected),
    ),
    _Menu.items => DevMasterDetail(
      key: const ValueKey('items'),
      hint: 'Wähle links ein Item — oder «+ New».',
      list: (context, open, selected) => itemsListPane(open, selected),
    ),
    _Menu.resources => _card(const GatherDefsTab()),
    _Menu.actions => const DevActionsPage(),
  };

  /// A full-width page on one cream card (the forms that are not list + pane).
  Widget _card(Widget child) => creamCard(
    child: ClipRRect(
      borderRadius: vr(13),
      child: Material(color: Colors.transparent, child: child),
    ),
  );
}
