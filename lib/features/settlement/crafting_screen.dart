import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/duration_format.dart';
import '../../core/ui/feel.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/recess_bar.dart';
import '../creatures/services/creatures_controller.dart';
import '../onboarding/intro_flow.dart' show jumpstartTimeScale;
import '../social/widgets/social_kit.dart';
import 'data/building_definitions.dart';
import 'data/item_definitions.dart';
import 'data/resource_icons.dart';
import 'market_screen.dart';
import 'models/settlement.dart' show CraftJob;
import 'services/crafting.dart';
import 'settlement_controller.dart';
import 'work_screen.dart';

/// THE WORKBENCH (user 2026-09-20, "Variante 4, Kategorien + Detail").
///
/// Three cream cards side by side:
///  • a RAIL of recipe groups (Heal, Revive, Cures, Boosts, Packs);
///  • the recipes of the chosen group — each says how many you can make with
///    what is in store, or what is missing;
///  • the chosen recipe in full: its ingredients (need of have), the time one
///    craft takes at the current crafting power, how many you can make, a
///    quantity stepper and Craft — with the benches and the line pinned under
///    it, so what is being made is always in view.
///
/// Costs are paid when an item FINISHES, not when it is queued (see
/// SettlementController._accrueCrafting), so an order the store cannot cover yet
/// is allowed: the bar waits full until the goods exist. Craft therefore asks
/// first when the store falls short — the dialog names what is missing and
/// offers the Market, or to queue it anyway.
class CraftingScreen extends StatefulWidget {
  const CraftingScreen({super.key});

  @override
  State<CraftingScreen> createState() => _CraftingScreenState();
}

/// What the "not enough" dialog was answered with.
enum _Short { queue, market }

/// The most one Craft press may order — the line is short anyway.
const int _kMaxOrder = 99;

class _CraftingScreenState extends State<CraftingScreen> {
  final _ctrl = SettlementController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  CraftGroup? _group;
  String? _sel;
  int _qty = 1;
  bool _busy = false;

  static const _ink = kBoxInk;
  static final _inkSoft = kBoxInkSoft;
  static final _inkFaint = kBoxInkFaint;

  @override
  void initState() {
    super.initState();
    // The ETA counts down in real time; the controller only ticks when the
    // economy does. Only while something is being crafted.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _ctrl.craftJobs.isNotEmpty) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Map<String, double> get _stock => _ctrl.resources?.asMap ?? const {};
  int get _era => _ctrl.dungeonMaxStage;

  List<ItemDef> _recipes(CraftGroup g) => [
    for (final d in kItemDefs.values)
      if (craftGroupOf(d.kind) == g) d,
  ];

  /// How many more items fit — benches plus line. Effectively unlimited when
  /// no building authors a line.
  int get _room {
    final q = _ctrl.craftQueueCapacity;
    if (q == null) return _kMaxOrder;
    return math.max(0, _ctrl.craftCapacity + q - _ctrl.craftJobs.length);
  }

  /// How many monsters are actually standing at a crafting post right now. The
  /// one number that decides whether anything on this page moves.
  ///
  /// An assignment is (building, stat), not (role) — so the crafting posts have
  /// to be resolved through each building's def, and a monster only counts if
  /// it is actually HERE (an assigned creature away on a trip crafts nothing,
  /// which is the same rule accruePassiveXp uses).
  int get _crafters {
    var n = 0;
    for (final b in _ctrl.buildings) {
      final def = kBuildingDefs[b.buildingTypeId];
      if (def == null) continue;
      final stats = {
        for (final w in def.workshops)
          if (w.resource == WorkshopRole.kCrafting) w.stat,
      };
      if (stats.isEmpty) continue;
      n += _creatures.creatures
          .where(
            (c) =>
                c.assignedBuildingId == b.id &&
                stats.contains(c.assignedStat) &&
                _creatures.isWorkingNow(c),
          )
          .length;
    }
    return n;
  }

  static String _n(double v) => v.round().toString();

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _creatures]),
    builder: (context, _) {
      final groups = [
        for (final g in CraftGroup.values)
          if (_recipes(g).isNotEmpty) g,
      ];
      final group = _group != null && groups.contains(_group)
          ? _group
          : (groups.isEmpty ? null : groups.first);
      final recipes = group == null ? const <ItemDef>[] : _recipes(group);
      final def = recipes.isEmpty
          ? null
          : recipes.firstWhere(
              (d) => d.id == _sel,
              orElse: () => recipes.first,
            );
      final crafters = _crafters;
      return MenuScaffold(
        title: 'Crafting',
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: CreamPalette.tan.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            '⚒️ $crafters ${crafters == 1 ? 'crafter' : 'crafters'}',
            style: FoE.value(
              size: 11,
            ).copyWith(color: crafters == 0 ? CreamPalette.warn : kBoxInk),
          ),
        ),
        child: def == null
            ? Center(
                child: Text(
                  'Nothing can be crafted yet.',
                  style: FoE.dim(size: 12).copyWith(color: Colors.white70),
                ),
              )
            : Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 74,
                      child: creamCard(child: _rail(groups, group!)),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 318,
                      child: creamCard(child: _list(group, recipes, def)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: creamCard(child: _detail(def, crafters))),
                  ],
                ),
              ),
      );
    },
  );

  // ── The rail ──────────────────────────────────────────────────────────
  static const _groupIcons = {
    CraftGroup.heal: Icons.favorite,
    CraftGroup.revive: Icons.restore,
    CraftGroup.cures: Icons.medical_services,
    CraftGroup.boosts: Icons.auto_awesome,
    CraftGroup.packs: Icons.inventory_2,
  };

  Widget _rail(List<CraftGroup> groups, CraftGroup current) =>
      SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final g in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Pressable(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() {
                    _group = g;
                    _sel = null;
                    _qty = 1;
                  }),
                  child: Container(
                    height: 56,
                    decoration: g == current ? goldButton() : raisedTile(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_groupIcons[g], size: 20, color: _ink),
                        const SizedBox(height: 2),
                        Text(
                          g.label,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  // ── The recipes of the chosen group ───────────────────────────────────
  Widget _list(CraftGroup group, List<ItemDef> recipes, ItemDef chosen) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              group.label.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: kBoxAccent,
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
              itemCount: recipes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (_, i) =>
                  _recipeRow(recipes[i], selected: recipes[i].id == chosen.id),
            ),
          ),
        ],
      );

  Widget _recipeRow(ItemDef def, {required bool selected}) {
    final can = craftableCount(def, _era, _stock);
    final short = can < 1 ? craftShortfall(def, _era, _stock) : const {};
    final owned = _ctrl.items[def.id] ?? 0;
    final making = _ctrl.craftJobs.where((j) => j.itemId == def.id).length;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        _sel = def.id;
        _qty = 1;
      }),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: raisedTile().copyWith(
          border: selected
              ? Border.all(color: CreamPalette.gold, width: 3)
              : making > 0
              ? Border.all(
                  color: CreamPalette.gold.withValues(alpha: 0.7),
                  width: 1.5,
                )
              : null,
        ),
        child: Row(
          children: [
            _glyph(def, 24, owned),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    def.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  Text(
                    can >= 1
                        ? (can >= kCraftableCap ? 'free' : 'can make $can')
                        : 'missing ${short.entries.map((e) => '${_n(e.value)} ${resourceEmoji(e.key)}').join(' ')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: can >= 1 ? CreamPalette.better : CreamPalette.warn,
                    ),
                  ),
                ],
              ),
            ),
            if (making > 0)
              Text(
                '×$making',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: CreamPalette.goldDeep,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The item's glyph, with the count you hold as a stack badge on its corner.
  Widget _glyph(ItemDef def, double size, int owned) => SizedBox(
    width: size + 6,
    child: Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Text(def.emoji, style: TextStyle(fontSize: size)),
        if (owned > 0)
          Positioned(
            right: -6,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: CreamPalette.accent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '$owned',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    ),
  );

  // ── The chosen recipe ─────────────────────────────────────────────────
  Widget _detail(ItemDef def, int crafters) {
    final stock = _stock;
    final can = craftableCount(def, _era, stock);
    final room = _room;
    final qty = _qty.clamp(1, math.max(1, math.min(room, _kMaxOrder))).toInt();
    final secs = craftSecondsAt(
      def,
      _ctrl.craftRatePerHour,
      timeScale: jumpstartTimeScale(_ctrl.jumpstartActive),
    );
    final owned = _ctrl.items[def.id] ?? 0;
    final one = craftCostFor(def, _era, stock, 1);
    final total = craftCostFor(def, _era, stock, qty);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: CreamPalette.tan.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          def.emoji,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              def.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: _ink,
                              ),
                            ),
                            Text(
                              '${def.description} · in bag $owned',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: FoE.dim(
                                size: 11,
                              ).copyWith(color: _inkSoft),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _caption('Time'),
                          Text(
                            secs == null ? '—' : fmtDuration(secs),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: secs == null ? _inkFaint : _ink,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _caption('Ingredients'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final e in one.entries)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ingredient(
                              e.key,
                              e.value,
                              stock[e.key] ?? 0,
                            ),
                          ),
                        ),
                      Expanded(child: _canTile(can)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _stepper(qty, room),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          total.isEmpty
                              ? 'free'
                              : '${qty > 1 ? '×$qty ' : ''}costs '
                                    '${total.entries.map((e) => '${resourceEmoji(e.key)} ${_n(e.value)}').join(' · ')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FoE.dim(size: 11).copyWith(color: _inkSoft),
                        ),
                      ),
                      SocialGoldButton(
                        room < 1
                            ? 'Line full'
                            : (qty > 1 ? 'Craft ×$qty' : 'Craft'),
                        height: 38,
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 26),
                        onTap: room < 1 || _busy
                            ? null
                            : () => _craft(def, qty),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 1,
            margin: const EdgeInsets.only(top: 8, bottom: 8),
            color: CreamPalette.tan.withValues(alpha: 0.4),
          ),
          _benchArea(crafters),
        ],
      ),
    );
  }

  Widget _caption(String t) => Text(
    t.toUpperCase(),
    style: const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: kBoxAccent,
    ),
  );

  /// One ingredient: the good, what ONE craft needs and what you hold. Red when
  /// you hold less than it needs.
  Widget _ingredient(String id, double need, double have) {
    final short = have < need;
    final color = short ? CreamPalette.warn : _ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: raisedTile(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(resourceEmoji(id), style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text.rich(
              TextSpan(
                text: _n(need),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
                children: [
                  TextSpan(
                    text: ' of ${_n(have)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: short ? CreamPalette.warn : _inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _canTile(int can) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      color: CreamPalette.tan.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'You can make',
          maxLines: 1,
          style: TextStyle(fontSize: 10.5, color: _inkSoft),
        ),
        Text(
          can >= kCraftableCap ? '∞' : '$can',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: can >= 1 ? CreamPalette.better : CreamPalette.warn,
          ),
        ),
      ],
    ),
  );

  Widget _stepper(int qty, int room) {
    final max = math.max(1, math.min(room, _kMaxOrder));
    Widget btn(IconData icon, VoidCallback? onTap) => Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: Container(
          width: 28,
          height: 28,
          decoration: raisedTile(radius: 9),
          child: Icon(icon, size: 16, color: _ink),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(
          Icons.remove,
          qty > 1 ? () => setState(() => _qty = qty - 1) : null,
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ),
        btn(Icons.add, qty < max ? () => setState(() => _qty = qty + 1) : null),
      ],
    );
  }

  // ── Ordering ──────────────────────────────────────────────────────────

  Future<void> _craft(ItemDef def, int qty) async {
    final short = craftShortfall(def, _era, _stock, n: qty);
    if (short.isNotEmpty) {
      final choice = await _shortDialog(def, qty, short);
      if (!mounted) return;
      if (choice == _Short.market) {
        await pushMenu<void>(context, const MarketScreen());
        return;
      }
      if (choice != _Short.queue) return;
    }
    setState(() => _busy = true);
    var made = 0;
    String? err;
    for (var i = 0; i < qty; i++) {
      err = await _ctrl.queueCraft(def.id);
      if (err != null) break;
      made++;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (made > 0) {
      Feel.success();
    } else {
      Feel.deny();
    }
    if (err != null) context.snack(err);
  }

  /// "Not enough …": names what is missing (need / have per good) and offers the
  /// Market, or to queue it anyway — the cost is only paid when an item is done,
  /// so the bar just waits full until the goods are there.
  Future<_Short?> _shortDialog(
    ItemDef def,
    int qty,
    Map<String, double> short,
  ) {
    final stock = _stock;
    final cost = craftCostFor(def, _era, stock, qty);
    final ids = short.keys.toList();
    final title = ids.length == 1
        ? 'Not enough ${resourceName(ids.first)}'
        : 'Not enough ingredients';
    final body = ids.length == 1
        ? '${def.emoji} ${def.name}${qty > 1 ? ' ×$qty' : ''} needs '
              '${_n(cost[ids.first] ?? 0)} ${resourceEmoji(ids.first)}, you have '
              '${_n(stock[ids.first] ?? 0)} — ${_n(short[ids.first]!)} short.'
        : '${def.emoji} ${def.name}${qty > 1 ? ' ×$qty' : ''} needs more than '
              'the store holds.';
    return showDialog<_Short>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: SizedBox(
          width: 340,
          child: creamCard(
            padding: const EdgeInsets.all(18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: FoE.title(size: 15).copyWith(color: kBoxInk),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in cost.entries)
                        _needChip(e.key, e.value, stock[e.key] ?? 0),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can still put it in the line — the bar waits until the '
                    'goods are there.',
                    textAlign: TextAlign.center,
                    style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
                  ),
                  const SizedBox(height: 14),
                  SocialGoldButton(
                    ids.length == 1
                        ? 'Buy ${resourceName(ids.first)} at the Market'
                        : 'Open the Market',
                    height: 38,
                    onTap: () => Navigator.pop(ctx, _Short.market),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SocialTileButton(
                          'Cancel',
                          height: 36,
                          onTap: () => Navigator.pop(ctx),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SocialTileButton(
                          'Queue it',
                          height: 36,
                          onTap: () => Navigator.pop(ctx, _Short.queue),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _needChip(String id, double need, double have) {
    final ok = have >= need;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: raisedTile(radius: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${resourceEmoji(id)} ${_n(need)} / ${_n(have)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            ok ? Icons.check : Icons.close,
            size: 14,
            color: ok ? CreamPalette.better : CreamPalette.warn,
          ),
        ],
      ),
    );
  }

  // ── The benches and the line, pinned under the recipe ─────────────────
  Widget _benchArea(int crafters) {
    final active = _ctrl.activeCraftJobs;
    final queued = _ctrl.queuedCraftJobs;
    final cap = _ctrl.craftQueueCapacity;
    final benches = _ctrl.craftCapacity;

    final warning = crafters == 0
        ? Container(
            height: 34,
            margin: EdgeInsets.only(bottom: active.isEmpty ? 0 : 8),
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              color: CreamPalette.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: CreamPalette.warn.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    active.isEmpty
                        ? 'Nobody is at the benches — post a monster in the Workshop.'
                        : 'Nobody is at the benches — nothing moves.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: CreamPalette.warn,
                    ),
                  ),
                ),
                SocialTileButton(
                  'Open Work',
                  icon: Icons.groups,
                  height: 26,
                  fontSize: 11,
                  onTap: () => pushMenu<void>(context, const WorkScreen()),
                ),
              ],
            ),
          )
        : null;

    if (active.isEmpty) {
      return warning ??
          Text(
            'The benches are empty. Pick a recipe and your crafters start on it.',
            style: FoE.dim(size: 11.5).copyWith(color: _inkSoft),
          );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (warning != null) warning,
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < active.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(width: 196, child: _benchTile(active[i], i)),
                ),
              if (queued.isNotEmpty)
                SizedBox(
                  width: 170,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        cap == null
                            ? 'IN LINE  ${queued.length}'
                            : 'IN LINE  ${queued.length}/$cap',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.9,
                          color: kBoxAccent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (var i = 0; i < queued.length; i++)
                            _queuedChip(queued[i], benches + i),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// One bench: what is on it, how long it has left, the bar, and the way to
  /// take it off.
  Widget _benchTile(CraftJob job, int index) {
    final def = kItemDefs[job.itemId];
    if (def == null) return const SizedBox.shrink();
    final progress = _ctrl.craftJobProgress(job);
    final total = craftSecondsAt(
      def,
      _ctrl.craftRatePerHour,
      timeScale: jumpstartTimeScale(_ctrl.jumpstartActive),
    );
    // Full but not done: the goods to pay for it are missing.
    final waiting = progress >= 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 6, 4, 7),
      decoration: raisedTile(radius: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(def.emoji, style: const TextStyle(fontSize: 17)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  def.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                waiting
                    ? 'needs goods'
                    : total == null
                    ? '—'
                    : fmtDuration(total * (1 - progress)),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: waiting ? CreamPalette.warn : _inkSoft,
                ),
              ),
              Pressable(
                onTap: () => _ctrl.cancelCraft(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Icon(Icons.close, size: 14, color: _inkFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: RecessBar(
              value: progress,
              color: waiting ? CreamPalette.warn : CreamPalette.gold,
              height: 8,
            ),
          ),
        ],
      ),
    );
  }

  /// One waiting item — no bar, nothing is happening to it yet. Tap takes it
  /// out of the line.
  Widget _queuedChip(CraftJob job, int index) {
    final def = kItemDefs[job.itemId];
    if (def == null) return const SizedBox.shrink();
    return Tooltip(
      message: '${def.name} — tap to take it out of the line',
      child: Pressable(
        onTap: () => _ctrl.cancelCraft(index),
        child: Container(
          width: 30,
          height: 26,
          alignment: Alignment.center,
          decoration: raisedTile(radius: 8),
          child: Text(def.emoji, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }
}
