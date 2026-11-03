import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/filter_pills.dart';
import 'build_menu_request.dart';
import 'data/building_definitions.dart';
import 'models/placed_building.dart';
import 'services/game_engine.dart';
import 'settlement_controller.dart';
import 'sheets/building_detail_dialog.dart';
import 'widgets/building_icon.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

/// ONE RESOURCE, WHOLE (user 2026-09-22, "Epochen-Regale"): what is in the store
/// and how full it is, what MAKES it and what EATS it, and where the room to keep
/// it comes from — on one page, three cards. It replaces the two pages this used
/// to be (the production list and, behind its "In store" bar, the storage list).
///
/// LEFT: the hero — the pile, its ceiling, the rate and how long until it is full
/// (or empty). MIDDLE: "Produced by" (one row per building, tap = its dialog,
/// sortable) and "Consumed by" (drains not tied to a building), summed in Total.
/// RIGHT: "Storage" — the store's bar and every building that adds room to it.
/// A resource without a ceiling (gold has none) has no Storage card.
class ResourceDetailScreen extends StatefulWidget {
  final String resourceId;
  final String emoji;
  final String title;

  const ResourceDetailScreen({
    super.key,
    required this.resourceId,
    required this.emoji,
    required this.title,
  });

  @override
  State<ResourceDetailScreen> createState() => _ResourceDetailScreenState();
}

class _ResourceDetailScreenState extends State<ResourceDetailScreen> {
  final _ctrl = SettlementController();

  /// null = by amount (the default), 'level' or 'name' otherwise; the same field
  /// tapped again flips direction — the convention of every sort pill.
  String? _sort;
  bool _descending = true;

  // The PAGE is built once; only its NUMBERS listen (user report 2026-08-31:
  // backing out could hang on a black screen). [_ctrl] ticks every 5 s on its own
  // passive-economy timer, and rebuilding the scaffold and its close button on
  // that timer while the pop transition plays is what did it.
  @override
  Widget build(BuildContext context) => MenuScaffold(
    title: '${widget.emoji}  ${widget.title}',
    trailing: AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final total = _ctrl.hourlyRates[widget.resourceId] ?? 0;
        return Text(
          _perHour(total),
          // A net loss is red, the rule the header's own cell follows (user
          // 2026-08-01).
          style: FoE.value(
            size: 14,
          ).copyWith(color: total < 0 ? CreamPalette.warn : kBoxInk),
        );
      },
    ),
    child: AnimatedBuilder(animation: _ctrl, builder: (context, _) => _body()),
  );

  Widget _body() {
    final id = widget.resourceId;
    final made = _ctrl.productionSourcesByBuilding(id)
      ..sort((a, b) {
        final cmp = switch (_sort) {
          'level' => a.$1.level.compareTo(b.$1.level),
          'name' => a.$2.name.compareTo(b.$2.name),
          _ => a.$3.compareTo(b.$3),
        };
        return _descending ? -cmp : cmp;
      });
    // The synthetic drains (refining, upkeep) — never tied to one building.
    final eaten = _ctrl
        .productionSources(id)
        .where((s) => s.amount < 0)
        .toList();
    final stored = _ctrl.resources?.amountOf(id) ?? 0;
    final capacity = _ctrl.storageCapacity(id);
    final hasCap = capacity > 0;
    final rate = _ctrl.hourlyRates[id] ?? 0;
    // ENERGY IS A FACTOR ON THE PRODUCTION (user 2026-09-22: "oben rechts 92
    // total, Mitte nur 77 — die Prozente durch die Energie auch als Bonus oder
    // Malus auflisten"): the rows list what the buildings make at 100 %, the
    // header's rate is that times the energy multiplier. So the multiplier is a
    // row of its own, and the Total under the list is the header's figure. (The
    // refining drains below are already priced at the energy-scaled rate, the way
    // the header subtracts them.)
    final madeSum = made.fold<double>(0, (a, s) => a + s.$3);
    final energy = _ctrl.energy;
    final mult = energy?.multiplier ?? 1.0;
    final energyDelta = madeSum > 0 ? madeSum * (mult - 1) : 0.0;
    final net =
        madeSum + energyDelta + eaten.fold<double>(0, (a, s) => a + s.amount);

    // The hero pile is a different KIND of thing from the two lists beside
    // it — a big readout, not a row list (user 2026-09-29, "Trennlinien und
    // Zonen gemischt", app-wide) — so it gets its own [zoneBox]; Produced by
    // and Storage are both building lists, so they stay just a [vHairline]
    // apart. (MenuScaffold is the one card now — no [pageCard] here, or this
    // would nest a card inside its card.)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 210,
          child: zoneBox(
            padding: const EdgeInsets.all(6),
            child: _hero(stored, capacity, rate),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionLabel(
                'Produced by',
                // Flexible, not bare (the 2026-08-31 crash: "RenderFlex
                // children have non-zero flex but incoming width
                // constraints are unbounded"): [MenuPill] has an Expanded
                // label inside it, so it needs a bounded width from the Row
                // it sits in.
                trailing: made.isEmpty ? null : Flexible(child: _sortPill()),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _productionBody(
                  made,
                  eaten,
                  net,
                  energyDelta: energyDelta,
                  energyPercent: energy?.percent,
                  energyMult: mult,
                ),
              ),
            ],
          ),
        ),
        if (hasCap) ...[
          vHairline(),
          SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionLabel(
                  'Storage',
                  trailing: Text(
                    '${_group(stored)} / ${_group(capacity)}',
                    style: FoE.value(size: 13).copyWith(
                      color: stored >= capacity ? CreamPalette.warn : kBoxInk,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(child: _storageBody(stored, capacity)),
              ],
              ),
            ),
        ],
      ],
    );
  }

  // ── The hero ──────────────────────────────────────────────
  Widget _hero(double stored, double capacity, double rate) {
    final hasCap = capacity > 0;
    final full = hasCap && stored >= capacity;
    final frac = hasCap ? (stored / capacity).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(widget.emoji, style: const TextStyle(fontSize: 54)),
          const SizedBox(height: 4),
          Text(
            _group(stored),
            style: FoE.value(size: 26).copyWith(color: kBoxInk),
          ),
          if (hasCap)
            Text(
              'of ${_group(capacity)}',
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
          if (hasCap) ...[
            const SizedBox(height: 8),
            _bar(frac, full ? CreamPalette.warn : CreamPalette.gold, 12),
          ],
          const SizedBox(height: 10),
          Text(
            _perHour(rate),
            style: FoE.value(size: 18).copyWith(
              color: rate < 0
                  ? CreamPalette.warn
                  : rate > 0
                  ? CreamPalette.better
                  : kBoxInkFaint,
            ),
          ),
          Text(
            _outlook(stored, capacity, rate),
            textAlign: TextAlign.center,
            style: FoE.dim(size: 11.5).copyWith(
              color: full ? CreamPalette.warn : kBoxInkSoft,
              fontWeight: full ? FontWeight.w800 : null,
            ),
          ),
        ],
      ),
    );
  }

  /// When the pile is full or empty at this rate.
  static String _outlook(double stored, double capacity, double rate) {
    if (capacity > 0 && stored >= capacity) return 'Full — production stops';
    if (rate > 0 && capacity > 0) {
      return 'full in ${_hours((capacity - stored) / rate)}';
    }
    if (rate < 0 && stored > 0) return 'empty in ${_hours(stored / -rate)}';
    if (stored <= 0 && rate <= 0) return 'nothing here yet';
    return '';
  }

  // ── Production ────────────────────────────────────────────
  // The heading (with its sort pill) now lives in [_body] — the surface is
  // the shared [pageCard], not a card of this function's own.
  Widget _productionBody(
    List<(PlacedBuilding, BuildingDef, double)> made,
    List<ProductionSource> eaten,
    double net, {
    required double energyDelta,
    required double? energyPercent,
    required double energyMult,
  }) => made.isEmpty && eaten.isEmpty
      ? Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Nothing is producing this yet.',
              style: FoE.dim(size: 12).copyWith(color: kBoxInkSoft),
            ),
            const SizedBox(height: 12),
            // A way forward, not a dead end (user 2026-09-22): the build strip,
            // on the category that makes things.
            _actionButton(
              'Build a producer',
              () => BuildMenuRequest.open(
                context,
                category: BuildingCategory.production,
              ),
            ),
          ],
        )
      : ListView(
          padding: EdgeInsets.zero,
          children: [
            for (final s in made)
              !s.$1.isComplete
                  ? _builtRow(
                      s.$1,
                      s.$2,
                      '0/h',
                      sub: 'Lv ${s.$1.level} · Under construction',
                      color: kBoxInkFaint,
                    )
                  : s.$1.isPaused
                  ? _builtRow(
                      s.$1,
                      s.$2,
                      '0/h',
                      sub: 'Lv ${s.$1.level} · Paused',
                      color: kBoxInkFaint,
                    )
                  : _builtRow(s.$1, s.$2, '+${_amt(s.$3)}/h'),
            // A MODIFIER on the buildings above, not a producer — the same
            // row, but bare (no tile) so it reads as a different kind of
            // line (user 2026-09-28).
            if (energyDelta.abs() >= 0.05)
              _row(
                tile: false,
                icon: const Text('⚡', style: TextStyle(fontSize: 24)),
                name: 'Energy ${(energyPercent ?? 0).round()} %',
                sub: energyDelta > 0
                    ? 'bonus: +${((energyMult - 1) * 100).round()} % on production'
                    : 'malus: ${((energyMult - 1) * 100).round()} % on production',
                value:
                    '${energyDelta > 0 ? '+' : '−'}${_amt(energyDelta.abs())}/h',
                color: energyDelta > 0
                    ? CreamPalette.better
                    : CreamPalette.warn,
              ),
            if (eaten.isNotEmpty) ...[
              const SizedBox(height: 8),
              _subheading('Consumed by'),
              const SizedBox(height: 6),
              for (final s in eaten) _drainRow(s),
            ],
            _totalRow(net),
          ],
        );

  Widget _subheading(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
      color: kBoxAccent,
    ),
  );

  /// Order "Produced by" by amount, by level, or by name — the field-picks-then-
  /// flips control the Housing/Work tabs use.
  Widget _sortPill() => MenuPill<String>(
    palette: PillPalette.cream,
    icon: Icons.swap_vert,
    label: switch (_sort) {
      'level' => 'Level',
      'name' => 'Name',
      _ => 'Amount',
    },
    engaged: _sort != null || !_descending,
    value: _sort ?? '',
    entries: const [
      MapEntry('', 'Amount'),
      MapEntry('level', 'Level'),
      MapEntry('name', 'Name'),
    ],
    trailing: PixelIcon(
      _descending ? Icons.arrow_downward : Icons.arrow_upward,
      size: 14,
      color: kBoxAccent,
    ),
    selectedTrailing: _descending ? '↓' : '↑',
    onSelected: (v) {
      final picked = v.isEmpty ? null : v;
      setState(() {
        if (picked == _sort) {
          _descending = !_descending;
        } else {
          _sort = picked;
          _descending = true;
        }
      });
    },
  );

  /// WHAT IS ACTUALLY PRODUCED — the sum of every row above it, arrived at rather
  /// than asserted (if it ever disagrees with the header rate, a row is missing).
  Widget _totalRow(double net) => Container(
    margin: const EdgeInsets.only(top: 6),
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: kBoxInk.withValues(alpha: 0.3), width: 2),
      ),
    ),
    child: Row(
      children: [
        // "Total", not "Net gain"/"Net loss" (user 2026-08-31) — one label
        // regardless of sign; the number and its colour already say which.
        Expanded(
          child: Text(
            'Total',
            style: FoE.label(
              size: 13,
            ).copyWith(color: kBoxInk, fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          _perHour(net),
          style: FoE.value(
            size: 14,
          ).copyWith(color: net < 0 ? CreamPalette.warn : CreamPalette.better),
        ),
      ],
    ),
  );

  // ── Storage ───────────────────────────────────────────────
  // The heading (with its "stored / capacity" trailing) now lives in
  // [_body] — the surface is the shared [pageCard], not a card of this
  // function's own.
  Widget _storageBody(double stored, double capacity) {
    final full = stored >= capacity;
    final frac = (stored / capacity).clamp(0.0, 1.0);
    final sources = _ctrl.storageSourcesByBuilding(widget.resourceId)
      ..sort((a, b) => b.$3.compareTo(a.$3));
    // The settlement's own base — never tied to a building, so it is a fixed line
    // above the sortable ones.
    final baseCap = capacity - sources.fold<double>(0, (a, s) => a + s.$3);
    final rate = _ctrl.hourlyRates[widget.resourceId] ?? 0;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        _bar(frac, full ? CreamPalette.warn : CreamPalette.gold, 12),
        const SizedBox(height: 4),
        Text(
          _outlook(stored, capacity, rate).isEmpty
              ? ' '
              : _outlook(stored, capacity, rate),
          style: FoE.dim(size: 11).copyWith(color: kBoxInkSoft),
        ),
        const SizedBox(height: 8),
        if (baseCap > 0)
          _row(
            icon: const Text('🏛', style: TextStyle(fontSize: 24)),
            name: 'The settlement itself',
            sub: 'base room',
            value: '+${baseCap.toStringAsFixed(0)}',
            color: kBoxInk,
          ),
        for (final s in sources)
          _builtRow(s.$1, s.$2, '+${s.$3.toStringAsFixed(0)}', color: kBoxInk),
        const SizedBox(height: 6),
        // More room is one tap away: the build strip, on the category of a
        // building that stores this. Amber when the store is already full.
        _actionButton(
          'Build more storage',
          () => BuildMenuRequest.open(context, category: _storageCategory()),
          primary: full,
        ),
      ],
    );
  }

  // ── Ways forward ──────────────────────────────────────────
  /// The build-strip category of a building that adds room to this resource
  /// (Production if none is found).
  BuildingCategory _storageCategory() {
    final era = _ctrl.dungeonMaxStage;
    for (final def in kBuildingDefs.values) {
      final category = def.category;
      if (category == null || category == BuildingCategory.special) continue;
      if (def.effectEntry('storage', widget.resourceId, era) != null) {
        return category;
      }
    }
    return BuildingCategory.production;
  }

  /// A full-width button on a card: amber when it is the thing to do, a light
  /// tile otherwise.
  Widget _actionButton(
    String label,
    VoidCallback onTap, {
    bool primary = true,
  }) => Pressable(
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      decoration: primary ? goldButton() : raisedTile(radius: 12),
      child: Text(
        label,
        style: FoE.label(size: 13).copyWith(
          color: primary ? goldButtonInk() : kBoxInk,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );

  // ── Rows ──────────────────────────────────────────────────
  /// A building's row: its art, name and level, the figure — tapping it opens the
  /// same building dialog the Work and Housing pages open.
  Widget _builtRow(
    PlacedBuilding b,
    BuildingDef def,
    String value, {
    String? sub,
    Color color = CreamPalette.better,
  }) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: () => showBuildingDetailDialog(context, _ctrl, b),
    child: _row(
      icon: BuildingIcon(imageUrl: def.imageUrl, defId: def.id, size: 38),
      name: def.name,
      sub: sub ?? 'Lv ${b.level}',
      value: value,
      color: color,
    ),
  );

  /// A drain not tied to any one building (refining, creature upkeep) — the same
  /// row, minus the tap and the level line it has nothing to show for.
  Widget _drainRow(ProductionSource s) => _row(
    icon: BuildingIcon(
      imageUrl: s.imageUrl,
      defId: s.defId,
      emoji: s.emoji,
      size: 38,
    ),
    name: s.count > 1 ? '${s.label} ×${s.count}' : s.label,
    value: '−${_amt(s.amount.abs())}/h',
    color: CreamPalette.warn,
  );

  Widget _row({
    required Widget icon,
    required String name,
    String? sub,
    required String value,
    required Color color,
    bool tile = true,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 5),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: tile ? raisedTile(radius: 10) : null,
    child: Row(
      children: [
        SizedBox(width: 44, child: Center(child: icon)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.label(
                  size: 12.5,
                ).copyWith(color: kBoxInk, fontWeight: FontWeight.w700),
              ),
              if (sub != null)
                Text(
                  sub,
                  style: FoE.dim(size: 10.5).copyWith(color: kBoxInkSoft),
                ),
            ],
          ),
        ),
        Text(value, style: FoE.value(size: 12.5).copyWith(color: color)),
      ],
    ),
  );

  Widget _bar(double frac, Color color, double height) => ClipRRect(
    borderRadius: vr(height / 2),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: kBoxInk.withValues(alpha: 0.16)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: frac,
              child: ColoredBox(color: color),
            ),
          ),
        ],
      ),
    ),
  );

  // ── Formatting ────────────────────────────────────────────
  /// "1,240" — a whole number with thousands separators.
  static String _group(double v) {
    final s = v.round().abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _amt(double v) => v.toStringAsFixed(v.abs() >= 100 ? 0 : 1);

  static String _perHour(double v) =>
      '${v > 0
          ? '+'
          : v < 0
          ? '−'
          : ''}${_amt(v.abs())}/h';

  static String _hours(double h) =>
      h >= 48 ? '${(h / 24).round()} d' : '${h.ceil()} h';
}
