import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/cream_kit.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/recess_bar.dart';
import '../creatures/models/creature_instance.dart';
import '../creatures/models/expedition.dart';
import '../creatures/models/saved_team.dart';
import '../creatures/services/creatures_controller.dart';
import '../creatures/services/expedition_controller.dart';
import '../creatures/widgets/creature_family.dart' show CreatureAvatar;
import '../social/social_actions.dart' show confirmDialog;
import '../social/widgets/social_kit.dart';
import 'caravan_picker_screen.dart';
import 'data/goods_definitions.dart';
import 'data/item_definitions.dart';
import 'data/resource_icons.dart';
import 'services/gold_economy.dart';
import 'services/trade_caravan.dart';
import 'services/trade_center.dart';
import 'settlement_controller.dart';
import '../../core/theme/voxel_kit.dart' show vr;
import '../../core/theme/voxel_icons.dart';

/// The Market (user 2026-09-20, "Variante 3, Handelskacheln", with every
/// resource of an ERA side by side and a tappable amount field).
///
/// One cream card, three parts from top to bottom:
///  • THREE TRADE TILES — Sell, Exchange, Shop — one line of content each;
///  • the trade itself: the tradeable resources grouped BY ERA (newest first —
///    the era you are in is the one you trade), the three of an era side by side
///    in one row. Each card shows what is in store, the AMOUNT as a field you tap
///    to type the exact quantity (with the slider kept for a quick drag) and the
///    commit button carrying the price. Exchange adds "Get" (what you want
///    back) and a "Buy with gold" mode; the Shop is a grid of items;
///  • THE CARAVAN BAR, always on screen: haulers (tap + to add, tap one to take
///    it out), what they carry and how long the round trip takes, the saved
///    caravans, and the caravans on the road with their progress.
///
/// Every rate still comes from services/trade_center.dart with the building's
/// [SettlementController.tradeDiscount] applied — nothing here invents a price.
///
/// **Goods travel** (user 2026-07-26). Sell, barter and buy-with-gold each load a
/// CARAVAN and send it out as an expedition, so with no hauler there is no trade.
/// The Shop stays instant: an item you buy for the fight you are in right now is
/// worth nothing in two hours.
class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

enum _MarketTab { sell, exchange, shop }

class _MarketScreenState extends State<MarketScreen> {
  static const Color _ink = kBoxInk;
  static final Color _inkSoft = kBoxInkSoft;
  static final Color _inkFaint = kBoxInkFaint;

  static const _romans = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII'];

  final _ctrl = SettlementController();
  final _exp = ExpeditionController();
  final _creatures = CreaturesController();
  Timer? _ticker;

  /// The key of the card whose send is in flight, or null.
  String? _busy;

  _MarketTab _tab = _MarketTab.sell;

  /// Exchange: swapping goods for goods (true) or buying goods with gold.
  bool _swap = true;

  /// Exchange, swap mode: the good you want back.
  String _to = 'fish';

  /// The creatures loaded onto the next caravan. Empty until you pick one —
  /// every goods trade is gated on it.
  final List<CreatureInstance> _caravan = [];

  /// How much each card is set to trade, by card key — IN UNITS. Unset means
  /// "the whole load": the caravan's capacity is the real limit.
  ///
  /// Kept as the RAW value and clamped on read, so swapping to a smaller
  /// caravan pulls the offer down without forgetting what you had asked for.
  final Map<String, double> _amount = {};

  @override
  void initState() {
    super.initState();
    // Drop anyone who became unavailable (sent out, K.O.) while the page sat
    // open — the send would only bounce off startTrade's own check.
    _exp.addListener(_pruneCaravan);
    _creatures.addListener(_pruneCaravan);
    // Live countdowns, and it pays out a caravan that lands while you are
    // standing here.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _trips.isEmpty) return;
      if (_exp.expeditions.any((e) => e.isReadyToCollect(DateTime.now()))) {
        _exp.collectFinished();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _exp.removeListener(_pruneCaravan);
    _creatures.removeListener(_pruneCaravan);
    super.dispose();
  }

  void _pruneCaravan() {
    if (!mounted) return;
    final ready = _creatures.availableForExpedition().map((c) => c.id).toSet();
    setState(() => _caravan.removeWhere((c) => !ready.contains(c.id)));
  }

  /// The caravans on the road.
  List<Expedition> get _trips => [
    for (final e in _exp.expeditions)
      if (e.type == ExpeditionType.trade) e,
  ];

  // ── Sending ───────────────────────────────────────────────────────────
  Future<void> _run(String key, Future<String?> Function() action) async {
    setState(() => _busy = key);
    final err = await action();
    if (!mounted) return;
    setState(() => _busy = null);
    if (err != null) context.snack(err, error: true);
  }

  /// Sends [amountFrom] of [from] out and books [amountTo] of [to] for the
  /// return. Every goods trade on this page goes through here, so the cargo
  /// rules and the capacity check can't differ between the modes.
  Future<String?> _send({
    required String from,
    required double amountFrom,
    required String to,
    required double amountTo,
  }) => _exp.startTrade(
    members: _caravan,
    from: from,
    amountFrom: amountFrom,
    to: to,
    amountTo: amountTo,
  );

  /// How much of [resource] this caravan may take on, ignoring stock. 0 with no
  /// caravan, which is what disables every send button.
  double _capacity(String resource) => _caravan.isEmpty
      ? 0
      : tradeCapacity(
          resource,
          _caravan,
          carryMult: _ctrl.caravanBonuses.carryMult,
        );

  /// The most of [resource] a caravan can take given the [stock] on hand — the
  /// number every offer sizes itself against.
  double _haulable(String resource, double stock) => _caravan.isEmpty
      ? 0
      : maxTradeAmount(
          resource,
          _caravan,
          stock,
          carryMult: _ctrl.caravanBonuses.carryMult,
        );

  Duration get _tripTime =>
      tradeTripDuration(_caravan, travelMult: _ctrl.caravanBonuses.travelMult);

  static String _fmtTrip(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m ${s}s';
  }

  /// How many units it takes to fetch one gold when SELLING ("10 000") — a sale
  /// pays a thousandth of the trade value (see [kSellPayoutFactor]).
  static String _perGold(String resource) {
    final n = minSellable(resource).round().toString();
    final b = StringBuffer();
    for (var i = 0; i < n.length; i++) {
      if (i > 0 && (n.length - i) % 3 == 0) b.write(' ');
      b.write(n[i]);
    }
    return b.toString();
  }

  /// "0.5", "1.25", "3" — a unit price without trailing zeros.
  static String _each(double v) {
    final s = v.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  String _name(String resource) => resource == 'gold'
      ? 'gold'
      : kGoodsDefs[resource]?.name ?? _titleCase(resource);

  String _emoji(String resource) =>
      resource == 'gold' ? '🪙' : resourceEmoji(resource);

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── The page ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_ctrl, _exp, _creatures]),
    builder: (context, _) => MenuScaffold(
      title: 'Market',
      // The purse: every price on the page is in gold.
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: CreamPalette.tan.withValues(alpha: 0.18),
          borderRadius: vr(9),
        ),
        child: Text(
          '🪙 ${_ctrl.gold.toInt()}',
          style: FoE.value(size: 12).copyWith(color: _ink),
        ),
      ),
      // No card of its own any more (user 2026-09-30, "hier und andernorts
      // sind noch die alten Kästchen vorhanden") — MenuScaffold is already
      // the one card on screen.
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          children: [_tiles(), Expanded(child: _body()), _caravanBar()],
        ),
      ),
    ),
  );

  // ── The three trade tiles ─────────────────────────────────────────────
  Widget _tiles() {
    final stock = _ctrl.resources?.asMap ?? const <String, double>{};
    final tradeable = tradeableResources(_ctrl.dungeonMaxStage);
    final worth = tradeable.fold<int>(
      0,
      (s, r) => s + sellValue(r, stock[r] ?? 0),
    );
    final fee = (barterFee(_ctrl.tradeDiscount) * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          _tile(_MarketTab.sell, '🪙', 'Sell', 'all in store: 🪙 $worth'),
          const SizedBox(width: 10),
          _tile(
            _MarketTab.exchange,
            '🔁',
            'Exchange',
            'swap goods · $fee % fee',
          ),
          const SizedBox(width: 10),
          _tile(
            _MarketTab.shop,
            '🛒',
            'Shop',
            '${shopStock().length} items · instant',
          ),
        ],
      ),
    );
  }

  Widget _tile(_MarketTab tab, String glyph, String title, String sub) {
    final on = _tab == tab;
    return Expanded(
      child: Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = tab),
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: on ? goldButton() : raisedTile(),
          child: Row(
            children: [
              Text(glyph, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: on ? _ink.withValues(alpha: 0.75) : _inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── The body of each tab ──────────────────────────────────────────────
  Widget _body() {
    final res = _ctrl.resources;
    if (res == null) {
      return Center(
        child: Text(
          'Loading…',
          style: FoE.dim(size: 12).copyWith(color: _inkFaint),
        ),
      );
    }
    final stock = res.asMap;
    return switch (_tab) {
      _MarketTab.sell => _eraList((r) => _sellCard(r, stock[r] ?? 0)),
      _MarketTab.exchange => _exchangeBody(stock),
      _MarketTab.shop => _shopBody(),
    };
  }

  /// The tradeable resources by era, newest first, THREE side by side in a row
  /// — an era is a row. [cardOf] builds one resource's card for the tab.
  Widget _eraList(Widget Function(String resource) cardOf) {
    final eras = tradeableByEra(_ctrl.dungeonMaxStage);
    final discount = _ctrl.tradeDiscount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      children: [
        for (var i = 0; i < eras.length; i++) ...[
          _eraLabel(eras[i].era, first: i == 0, discount: discount),
          for (var j = 0; j < eras[i].resources.length; j += 3) ...[
            if (j > 0) const SizedBox(height: 10),
            _eraRow(eras[i].resources.skip(j).take(3).toList(), cardOf),
          ],
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _eraRow(List<String> resources, Widget Function(String) cardOf) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: i < resources.length
              ? cardOf(resources[i])
              : const SizedBox.shrink(),
        ),
      ],
    ],
  );

  Widget _eraLabel(int era, {required bool first, required double discount}) {
    final label = era >= 1 && era <= _romans.length ? _romans[era - 1] : '$era';
    final String? note = _caravan.isEmpty
        ? 'Add a hauler below to start trading'
        : discount > 0
        ? 'Trade Center: ${(discount * 100).round()}% better rates'
        : null;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(
        children: [
          Text(
            'ERA $label',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: kBoxAccent,
            ),
          ),
          if (first) ...[
            const SizedBox(width: 8),
            Text(
              'your era',
              style: FoE.dim(size: 10).copyWith(color: _inkFaint),
            ),
          ],
          const Spacer(),
          if (first && note != null)
            Flexible(
              child: Text(
                note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _caravan.isEmpty
                      ? CreamPalette.warn
                      : CreamPalette.better,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Sell ──────────────────────────────────────────────────────────────
  Widget _sellCard(String resource, double stock) {
    final key = 'sell_$resource';
    // The slider runs to what the CARAVAN can take, not to what the storehouse
    // holds: a slider reaching 8 000 logs that then bounces off the capacity
    // check is a trap.
    final haulable = _haulable(resource, stock);
    final amount = _amountFor(key, haulable);
    final earns = sellValue(resource, amount);
    return _tradeCard(
      resource: resource,
      stock: stock,
      note: '${_perGold(resource)} → 🪙 1',
      amountKey: key,
      max: haulable,
      amount: amount,
      actionLabel: 'Sell  🪙 $earns',
      blocked: _blockedReason(amount, earns > 0, 'Too little to sell'),
      onTap: () => _run(
        key,
        () => _send(
          from: resource,
          amountFrom: amount,
          to: 'gold',
          amountTo: earns.toDouble(),
        ),
      ),
    );
  }

  // ── Exchange ──────────────────────────────────────────────────────────
  Widget _exchangeBody(Map<String, double> stock) {
    final discount = _ctrl.tradeDiscount;
    final all = tradeableResources(_ctrl.dungeonMaxStage);
    // Keep "Get" on a resource this era actually knows.
    if (!all.contains(_to)) _to = all.first;
    final fee = barterFee(discount);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Row(
            children: [
              _seg(
                const ['Swap for goods', 'Buy with gold'],
                _swap ? 0 : 1,
                (i) => setState(() => _swap = i == 0),
              ),
              const SizedBox(width: 12),
              if (_swap) ...[
                Text(
                  'Get',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _inkSoft,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 168, child: _getPill(all)),
              ],
              const Spacer(),
              Flexible(
                child: Text(
                  _swap
                      ? 'A swap keeps ${((1 - fee) * 100).round()}% of the value.'
                      : 'Gold buys at ${goodsBuyMarkup(discount).toStringAsFixed(1)}× '
                            'what selling pays.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FoE.dim(size: 10.5).copyWith(color: _inkSoft),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _eraList(
            (r) => _swap
                ? _swapCard(r, stock[r] ?? 0, discount)
                : _buyCard(r, stock[r] ?? 0, discount),
          ),
        ),
      ],
    );
  }

  Widget _getPill(List<String> options) => MenuPill<String>(
    palette: PillPalette.cream,
    icon: Icons.inventory_2_outlined,
    label: '${_emoji(_to)} ${_name(_to)}',
    // Never "engaged": it always holds a good, so an accent would say nothing.
    engaged: false,
    value: _to,
    entries: [for (final r in options) MapEntry(r, '${_emoji(r)} ${_name(r)}')],
    onSelected: (v) => setState(() => _to = v),
  );

  /// A small two-or-three-way switch: a tan track with the live segment gold.
  Widget _seg(List<String> labels, int index, ValueChanged<int> onPick) =>
      Container(
        height: 34,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: CreamPalette.tan.withValues(alpha: 0.2),
          borderRadius: vr(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < labels.length; i++)
              Pressable(
                behavior: HitTestBehavior.opaque,
                onTap: () => onPick(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? CreamPalette.gold : Colors.transparent,
                    borderRadius: vr(9),
                    border: i == index
                        ? Border.all(color: CreamPalette.goldDeep)
                        : null,
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: i == index ? _ink : _inkSoft,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _swapCard(String from, double stock, double discount) {
    final key = 'swap_$from';
    if (from == _to) {
      // You cannot swap a good for itself; the card says so instead of hiding,
      // so the row keeps its three.
      return _tradeCard(
        resource: from,
        stock: stock,
        amountKey: key,
        max: 0,
        amount: 0,
        actionLabel: 'You want this',
        blocked: 'That is what you get',
        onTap: () {},
        muted: true,
      );
    }
    // Bounded by BOTH legs: what goes out and what comes back have to fit in
    // the same cargo hold.
    final maxIn = _caravan.isEmpty
        ? 0.0
        : maxBarterInput(
            from: from,
            to: _to,
            available: stock,
            yieldPerUnit:
                barterYield(from, _to, 1000, discount: discount) / 1000,
            members: _caravan,
            carryMult: _ctrl.caravanBonuses.carryMult,
          );
    final amount = _amountFor(key, maxIn);
    final gain = barterYield(from, _to, amount, discount: discount);
    return _tradeCard(
      resource: from,
      stock: stock,
      amountKey: key,
      max: maxIn,
      amount: amount,
      actionLabel: 'Swap → ${gain.toInt()} ${_emoji(_to)}',
      blocked: _blockedReason(amount, gain > 0, 'Too little to swap'),
      onTap: () => _run(
        key,
        () => _send(from: from, amountFrom: amount, to: _to, amountTo: gain),
      ),
    );
  }

  Widget _buyCard(String resource, double stock, double discount) {
    final key = 'buy_$resource';
    // Buying runs the caravan the other way round: gold is the cargo going out,
    // the goods are what comes home — so the CAPACITY that binds is the one for
    // the goods, not for the gold.
    final cap = _capacity(resource);
    // THREE CEILINGS, and the amount stops at the lowest: what fits in the hold
    // on the way home, what the purse covers — and what fits in the hold on the
    // way OUT, because gold is cargo too.
    final affordable = goodsForGold(
      resource,
      _ctrl.gold.toInt(),
      discount: discount,
    );
    final payable = goodsForGold(
      resource,
      _capacity('gold').floor(),
      discount: discount,
    );
    final max = [
      cap,
      affordable,
      payable,
    ].reduce((a, b) => a < b ? a : b).floorToDouble();
    final n = _amountFor(key, max);
    final cost = goodsBuyCost(resource, n, discount: discount);
    final unit = goodsBuyCost(resource, 100, discount: discount) / 100;

    return _tradeCard(
      resource: resource,
      stock: stock,
      note: '🪙 ${_each(unit)} each',
      amountKey: key,
      max: max,
      amount: n,
      actionLabel: 'Buy  🪙 $cost',
      blocked: _caravan.isEmpty
          ? 'Prepare a caravan'
          : _exp.caravansFull
          ? 'Every caravan is out'
          : affordable < 1
          ? 'Not enough gold'
          : cap < 1 || payable < 1
          ? 'Caravan cannot haul this'
          : n < 1
          ? 'Nothing to buy'
          : null,
      onTap: () => _run(
        key,
        () => _send(
          from: 'gold',
          amountFrom: cost.toDouble(),
          to: resource,
          amountTo: n.toDouble(),
        ),
      ),
    );
  }

  /// Why a goods send is off, in the order the player can fix it. Null when it
  /// is live — a greyed button that repeats its own label says it is off but
  /// not WHY.
  String? _blockedReason(double amount, bool pays, String tooLittle) {
    if (_caravan.isEmpty) return 'Prepare a caravan';
    // The caravan pool, checked HERE rather than at send: a full pool is a
    // state you can see coming, and learning about it from a bounced trade
    // after picking a load is the thing this file keeps trying not to do.
    if (_exp.caravansFull) return 'Every caravan is out';
    if (amount <= 0) return 'Nothing to send';
    if (!pays) return tooLittle;
    return null;
  }

  /// What a card is set to trade, in whole units, bounded by [max]. Unset means
  /// the whole load; a stored value that no longer fits is clamped rather than
  /// forgotten, so shrinking the caravan and growing it again gives your number
  /// back.
  double _amountFor(String key, double max) {
    if (max <= 0) return 0;
    return (_amount[key] ?? max).clamp(0, max).floorToDouble();
  }

  // ── One resource's card ───────────────────────────────────────────────

  /// The card all three modes share: the good and what is in store, the AMOUNT
  /// FIELD (tap → type the exact quantity), the commit button carrying the
  /// price, and a slider for a quick drag. The button shows WHY it is off when
  /// it is.
  Widget _tradeCard({
    required String resource,
    required double stock,
    required String amountKey,
    required double max,
    required double amount,
    required String actionLabel,
    required String? blocked,
    required VoidCallback onTap,
    String? note,
    bool muted = false,
  }) {
    final live = blocked == null && _busy == null;
    return Opacity(
      opacity: muted ? 0.55 : 1,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 4),
        decoration: raisedTile(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(_emoji(resource), style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _name(resource),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      Text(
                        '${stock.toInt()} in store${note == null ? '' : ' · $note'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                _amountField(
                  resource: resource,
                  amountKey: amountKey,
                  max: max,
                  amount: amount,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _actionButton(
                    live ? actionLabel : (blocked ?? actionLabel),
                    live ? onTap : null,
                  ),
                ),
              ],
            ),
            _slider(amountKey, max),
          ],
        ),
      ),
    );
  }

  /// THE AMOUNT FIELD: the quantity in big figures, "/ ceiling" beside it and a
  /// pencil — tap it to type the exact number.
  Widget _amountField({
    required String resource,
    required String amountKey,
    required double max,
    required double amount,
  }) {
    final live = max >= 1;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: live
          ? () => _editAmount(
              resource: resource,
              amountKey: amountKey,
              max: max,
              current: amount,
            )
          : null,
      child: Container(
        width: 112,
        height: 36,
        padding: const EdgeInsets.only(left: 9, right: 7),
        decoration: BoxDecoration(
          color: _ink.withValues(alpha: live ? 0.07 : 0.04),
          borderRadius: vr(10),
          border: Border.all(
            color: CreamPalette.tan.withValues(alpha: live ? 1 : 0.35),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    text: '${amount.toInt()}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: live ? _ink : _inkFaint,
                    ),
                    children: [
                      if (live)
                        TextSpan(
                          text: ' /${max.toInt()}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _inkFaint,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (live)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: PixelIcon(Icons.edit, size: 13, color: CreamPalette.tan),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(String label, VoidCallback? onTap) => Pressable(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: goldButton(active: onTap != null),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: goldButtonInk(active: onTap != null),
          ),
        ),
      ),
    ),
  );

  /// A quick drag for the same amount. Full interactive height (a slider's
  /// gesture area IS its render box), thin only in how the track looks.
  Widget _slider(String key, double max) {
    final live = max >= 1;
    final value = _amountFor(key, max);
    return SizedBox(
      height: 26,
      child: SliderTheme(
        data: SliderThemeData(
          trackHeight: 5,
          activeTrackColor: CreamPalette.goldDeep,
          inactiveTrackColor: CreamPalette.tan.withValues(alpha: 0.28),
          disabledActiveTrackColor: CreamPalette.tan.withValues(alpha: 0.28),
          disabledInactiveTrackColor: CreamPalette.tan.withValues(alpha: 0.28),
          thumbColor: CreamPalette.goldDeep,
          disabledThumbColor: CreamPalette.tan.withValues(alpha: 0.6),
          overlayColor: CreamPalette.gold.withValues(alpha: 0.2),
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
        ),
        child: Slider(
          // A dead card still draws its track — greyed rather than absent, so
          // the cards keep the same height whether or not a caravan is loaded.
          value: live ? value : 0,
          max: live ? max : 1,
          onChanged: live
              ? (v) => setState(() => _amount[key] = v.floorToDouble())
              : null,
        ),
      ),
    );
  }

  Future<void> _editAmount({
    required String resource,
    required String amountKey,
    required double max,
    required double current,
  }) async {
    final v = await showDialog<double>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (_) => _AmountDialog(
        title: '${_emoji(resource)} ${_name(resource)}',
        max: max.toInt(),
        current: current.toInt(),
      ),
    );
    if (v == null || !mounted) return;
    setState(() => _amount[amountKey] = v);
  }

  // ── Shop ──────────────────────────────────────────────────────────────
  Widget _shopBody() {
    final stock = shopStock();
    if (stock.isEmpty) {
      return Center(
        child: Text(
          'Nothing is stocked yet — give an item a buy price in Dev Mode → '
          'Items.',
          style: FoE.dim(size: 11).copyWith(color: CreamPalette.warn),
        ),
      );
    }
    final bag = _ctrl.items;
    final discount = _ctrl.tradeDiscount;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 232,
        mainAxisExtent: 118,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: stock.length,
      itemBuilder: (_, i) =>
          _shopCard(stock[i], bag[stock[i].id] ?? 0, discount),
    );
  }

  /// One item: what it is and does, the owned count as a stack badge on its
  /// glyph, Buy at the price on the button, and Sell back when you hold any.
  /// Selling back always pays less than buying (see itemSellValue), so it is
  /// the quiet tile beside the commit — never a way to make money.
  Widget _shopCard(ItemDef def, int owned, double discount) {
    final key = 'shop_${def.id}';
    final cost = itemBuyCost(def, discount: discount);
    final back = itemSellValue(def, discount: discount);
    final busy = _busy == key;
    final affordable = _ctrl.gold >= cost;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: raisedTile(),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      Text(def.emoji, style: const TextStyle(fontSize: 24)),
                      if (owned > 0)
                        Positioned(
                          right: -2,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: CreamPalette.accent,
                              borderRadius: vr(7),
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
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        def.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        def.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (back > 0 && owned > 0) ...[
                SocialTileButton(
                  'Sell 🪙 $back',
                  height: 34,
                  fontSize: 11,
                  onTap: busy
                      ? null
                      : () => _run(key, () => _ctrl.sellItem(def.id)),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: _actionButton(
                  'Buy  🪙 $cost',
                  busy || !affordable
                      ? null
                      : () => _run(key, () => _ctrl.buyItem(def.id)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── The caravan bar ───────────────────────────────────────────────────

  /// Always on screen: who hauls, what they carry and for how long, the saved
  /// caravans, and what is on the road. Every trade above rides this one
  /// caravan, so the facts are stated ONCE here rather than on every button.
  Widget _caravanBar() {
    final cap = _creatures.teamSizeCap;
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: CreamPalette.tan.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'CARAVAN',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: kBoxAccent,
                ),
              ),
              Text(
                '${_caravan.length}/$cap',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 232),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < cap; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: _slot(i),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _facts(),
          const SizedBox(width: 10),
          SocialTileButton(
            'Saved',
            icon: Icons.bookmark_border,
            height: 34,
            fontSize: 11.5,
            badge: _creatures.caravans.length,
            onTap: _savedDialog,
          ),
          Container(
            width: 1,
            height: 40,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: CreamPalette.tan.withValues(alpha: 0.35),
          ),
          Expanded(child: _tripStrip()),
        ],
      ),
    );
  }

  /// One place of the caravan: a filled face (tap takes it back out) or a `+`.
  /// The places are the picture — [teamSizeCap] of them, each filled on its own,
  /// so the row answers "how big is my caravan and how much is loaded" at a
  /// glance.
  Widget _slot(int i) {
    const size = 36.0;
    if (i < _caravan.length) {
      final c = _caravan[i];
      return Pressable(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _caravan.removeAt(i)),
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _face(c, size),
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: const BoxDecoration(
                    color: CreamPalette.accent,
                    shape: BoxShape.rectangle,
                  ),
                  child: const PixelIcon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }
    final next = i == _caravan.length;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: _addHauler,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.rectangle,
          color: next
              ? CreamPalette.gold.withValues(alpha: 0.28)
              : CreamPalette.tan.withValues(alpha: 0.1),
          border: Border.all(
            color: next
                ? CreamPalette.goldDeep
                : CreamPalette.tan.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: PixelIcon(
          Icons.add,
          size: 20,
          color: next ? kBoxAccent : CreamPalette.tan.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  // A hauler is the family's small tile too (user 2026-09-20); its health is
  // beside the point on a caravan, so no HP bar.
  Widget _face(CreatureInstance c, double size) =>
      CreatureAvatar.of(c, size: size, showHp: false);

  /// The three numbers the caravan decides, stated once: carry, speed, and the
  /// round trip. With nobody loaded, what to do instead.
  Widget _facts() => SizedBox(
    width: 138,
    child: _caravan.isEmpty
        ? Text(
            'Tap + to add a hauler',
            maxLines: 2,
            style: FoE.dim(size: 10.5).copyWith(color: _inkSoft),
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🏋 ${caravanCarry(_caravan)}   🥾 ${caravanSpeed(_caravan)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '⏱ ${_fmtTrip(_tripTime)} round trip',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _inkSoft,
                ),
              ),
            ],
          ),
  );

  /// Fills ONE place from the picker's single-pick mode. Appends rather than
  /// writing to a fixed index: the places are a rank, not numbered seats, so a
  /// caravan is always the first N of them with no holes in the middle.
  Future<void> _addHauler() async {
    if (_caravan.length >= _creatures.teamSizeCap) return;
    final picked = await pushMenu<List<CreatureInstance>>(
      context,
      CaravanPickerScreen(selected: _caravan),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() {
      // Guard against a double-tap racing two routes onto the same place.
      if (_caravan.any((c) => c.id == picked.first.id)) return;
      if (_caravan.length < _creatures.teamSizeCap) _caravan.add(picked.first);
    });
  }

  // ── On the road ───────────────────────────────────────────────────────

  /// The caravan pool (the market's own — the Caravanserai fills it) and the
  /// caravans out, each with its cargo, countdown and progress bar. A trade pays
  /// itself out the moment it lands (the ticker collects it), so there is no
  /// button on them.
  Widget _tripStrip() {
    final trips = _trips;
    return Row(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ON THE ROAD',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.9,
                color: kBoxAccent,
              ),
            ),
            Text(
              '🐫 ${_exp.caravanCount}/${_exp.maxCaravanSlots}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _exp.caravansFull ? CreamPalette.warn : _ink,
              ),
            ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: trips.isEmpty
              ? Text(
                  'No caravan out.',
                  style: FoE.dim(size: 11).copyWith(color: _inkFaint),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: trips.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Center(child: _tripCell(trips[i])),
                ),
        ),
      ],
    );
  }

  Widget _tripCell(Expedition e) {
    final now = DateTime.now();
    final from = e.payload['from'] as String? ?? '';
    final to = e.payload['to'] as String? ?? '';
    final amountFrom = (e.payload['amountFrom'] as num?)?.toInt() ?? 0;
    final amountTo = (e.payload['amountTo'] as num?)?.toInt() ?? 0;
    final ready = e.isReadyToCollect(now);
    return Container(
      width: 200,
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
      decoration: raisedTile(lit: ready, radius: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$amountFrom ${_emoji(from)} → $amountTo ${_emoji(to)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Text(
                ready ? 'arrived' : _fmt(e.remaining(now)),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: _inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          RecessBar(
            value: e.progress(now),
            color: ExpeditionType.trade.color,
            height: 8,
          ),
        ],
      ),
    );
  }

  // ── Saved caravans (user 2026-07-27) ──────────────────────────────────
  // Picking haulers is the slowest step of a trade and the one you repeat
  // unchanged, so a party can be saved and loaded again in one tap. A saved
  // caravan is the same object a saved BATTLE TEAM is — a name and a list of
  // ids — stored in the same table under a `kind` (migration 0028).

  /// The saved caravan whose members are exactly the loaded ones, or null.
  /// Order does not matter — a caravan is a set of haulers, not a batting
  /// order, so the same monsters picked in another sequence is the same caravan
  /// and must not offer to be saved twice.
  SavedTeam? _matchingSaved() {
    final mine = {for (final c in _caravan) c.id};
    for (final t in _creatures.caravans) {
      if (t.memberIds.length == mine.length && mine.containsAll(t.memberIds)) {
        return t;
      }
    }
    return null;
  }

  Future<void> _savedDialog() => showDialog<void>(
    context: context,
    barrierColor: CreamPalette.dim,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SizedBox(
        width: 350,
        child: creamCard(
          padding: const EdgeInsets.all(16),
          corner: const KitCloseButton(),
          child: ListenableBuilder(
            listenable: _creatures,
            builder: (ctx, _) {
              final saved = _creatures.caravans;
              final loaded = _matchingSaved();
              final canSave = _caravan.isNotEmpty && loaded == null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Saved caravans',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (saved.isEmpty)
                    socialHint(
                      'Save the party you just built and it lands here — one '
                      'tap to send the same haulers again.',
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in saved)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: socialRow(
                                height: 42,
                                lit: loaded?.id == t.id,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _loadSaved(t);
                                },
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: _ink,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${t.memberIds.length} haulers',
                                      style: FoE.dim(
                                        size: 10.5,
                                      ).copyWith(color: _inkSoft),
                                    ),
                                    const SizedBox(width: 8),
                                    SocialGlyphButton(
                                      Icons.close,
                                      size: 26,
                                      tooltip: 'Forget',
                                      onTap: () => _forgetSaved(ctx, t),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: SocialGoldButton(
                          'Save this caravan',
                          height: 36,
                          onTap: canSave
                              ? () {
                                  Navigator.pop(ctx);
                                  _saveCaravan();
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  /// Quick-load: the saved ids, resolved to whoever is actually free right now.
  ///
  /// A roster is INTENT, not a live claim (the same rule battleTeam() follows),
  /// so a member who is K.O. or already out is skipped rather than blocking the
  /// load — but it is said out loud, because a caravan that quietly comes back
  /// two monsters short would just look like a broken button.
  void _loadSaved(SavedTeam team) {
    final free = {for (final c in _creatures.availableForExpedition()) c.id: c};
    final members = [
      for (final id in team.memberIds)
        if (free[id] != null) free[id]!,
    ];
    if (members.isEmpty) {
      context.snack('Nobody from "${team.name}" is free to travel.');
      return;
    }
    setState(() {
      _caravan
        ..clear()
        ..addAll(members.take(_creatures.teamSizeCap));
    });
    final missing = team.memberIds.length - members.length;
    if (missing > 0) {
      context.snack(
        '${team.name} loaded — $missing member${missing > 1 ? 's are' : ' is'} '
        'not free right now.',
      );
    }
  }

  Future<void> _saveCaravan() async {
    final name = await showDialog<String>(
      context: context,
      barrierColor: CreamPalette.dim,
      builder: (_) =>
          _NameDialog(initial: 'Caravan ${_creatures.caravans.length + 1}'),
    );
    if (name == null || !mounted) return;
    final err = await _creatures.saveCaravan(name, [
      for (final c in _caravan) c.id,
    ]);
    if (!mounted) return;
    if (err != null) context.snack(err, error: true);
  }

  Future<void> _forgetSaved(BuildContext dialogContext, SavedTeam team) async {
    final ok = await confirmDialog(
      dialogContext,
      title: 'Forget "${team.name}"?',
      body:
          'Only the saved party is dropped — the monsters in it are untouched.',
      confirmLabel: 'Forget',
      cancelLabel: 'Keep',
    );
    if (!ok || !mounted) return;
    await _creatures.deleteTeam(team);
  }
}

/// Type the exact quantity: a big numeric field, the ceiling under it, and
/// Min / Half / Max shortcuts. Pops with the chosen amount (clamped to the
/// ceiling), or null on Cancel.
class _AmountDialog extends StatefulWidget {
  final String title;
  final int max;
  final int current;

  const _AmountDialog({
    required this.title,
    required this.max,
    required this.current,
  });

  @override
  State<_AmountDialog> createState() => _AmountDialogState();
}

class _AmountDialogState extends State<_AmountDialog> {
  late final TextEditingController _text = TextEditingController(
    text: '${widget.current}',
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _typed => int.tryParse(_text.text) ?? 0;

  void _set(int v) => setState(() {
    _text.text = '$v';
    _text.selection = TextSelection.collapsed(offset: _text.text.length);
  });

  void _submit() =>
      Navigator.pop(context, _typed.clamp(0, widget.max).toDouble());

  @override
  Widget build(BuildContext context) {
    final over = _typed > widget.max;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: SizedBox(
        width: 320,
        child: creamCard(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: FoE.title(size: 15).copyWith(color: kBoxInk),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _text,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  textAlign: TextAlign.center,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                  cursorColor: CreamPalette.goldDeep,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: kBoxInk,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: vr(12),
                      borderSide: const BorderSide(
                        color: CreamPalette.tan,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: vr(12),
                      borderSide: const BorderSide(
                        color: CreamPalette.goldDeep,
                        width: 2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  over
                      ? 'The caravan takes at most ${widget.max} — that is what '
                            'will be set.'
                      : 'Up to ${widget.max} per trip.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: over ? CreamPalette.warn : kBoxInkSoft,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SocialTileButton(
                        'Min',
                        height: 34,
                        onTap: () => _set(1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SocialTileButton(
                        'Half',
                        height: 34,
                        onTap: () =>
                            _set((widget.max / 2).floor().clamp(1, widget.max)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SocialTileButton(
                        'Max',
                        height: 34,
                        onTap: () => _set(widget.max),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SocialTileButton(
                        'Cancel',
                        height: 38,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SocialGoldButton(
                        'Set',
                        height: 38,
                        onTap: _submit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Names a caravan about to be saved. Pops with the trimmed name, or null.
class _NameDialog extends StatefulWidget {
  final String initial;

  const _NameDialog({required this.initial});

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _text.text.trim();
    Navigator.pop(context, v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    elevation: 0,
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
    child: SizedBox(
      width: 320,
      child: creamCard(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Save this caravan',
                textAlign: TextAlign.center,
                style: FoE.title(size: 15).copyWith(color: kBoxInk),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _text,
                autofocus: true,
                maxLength: 24,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                cursorColor: CreamPalette.goldDeep,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: kBoxInk,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.55),
                  hintText: 'Name it',
                  enabledBorder: OutlineInputBorder(
                    borderRadius: vr(12),
                    borderSide: const BorderSide(
                      color: CreamPalette.tan,
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: vr(12),
                    borderSide: const BorderSide(
                      color: CreamPalette.goldDeep,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SocialTileButton(
                      'Cancel',
                      height: 38,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SocialGoldButton('Save', height: 38, onTap: _submit),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
