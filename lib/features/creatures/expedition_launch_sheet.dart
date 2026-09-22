import 'package:flutter/material.dart';

import '../../core/theme/cream_kit.dart' show goldButton;
import '../../core/theme/foe_theme.dart';
import '../../core/theme/strategy_theme.dart' show Strategy;
import '../../core/ui/feel.dart';
import '../settlement/settlement_controller.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/area.dart';
import 'models/expedition.dart' show ExpeditionType;
import 'models/creature_enums.dart';
import 'models/creature_instance.dart';
import 'models/species_def.dart';
import 'services/capture_math.dart';
import 'services/creatures_controller.dart';
import 'services/expedition_controller.dart';
import '../settlement/data/gather_defs.dart';
import 'services/expedition_targets.dart';
import 'services/gather_math.dart';
import 'widgets/creature_card.dart';
import '../common/widgets/empty_monster_slot.dart';
import '../common/widgets/filter_pills.dart';
import '../common/widgets/monster_tile_grid.dart';
import '../common/widgets/parchment_kit.dart';
import '../common/widgets/recess_bar.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';

/// Picks the group for [target] and sends the trip. Returns true when one was
/// actually dispatched.
///
/// A SHEET over the expeditions screen, not a page (user 2026-07-25): the trips
/// already out are the context for deciding who to send next — how many slots
/// are left, who is still away — so covering that list with a full screen threw
/// away the thing you were reading. It also merges the two old planner screens
/// (expedition_planner_screen / capture_planner_screen), which had drifted into
/// two different layouts for the same decision: pick a group, read the
/// forecast, send.
Future<bool?> showExpeditionLaunchSheet(
  BuildContext context,
  ExpeditionTarget target,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => ExpeditionLaunchPanel(target: target),
);

/// The same picker, [inline] on the page instead of under a modal sheet —
/// used when the Expeditions hub has exactly one hunt to offer, so there is
/// nothing left to disambiguate by covering the page (user 2026-09-08:
/// "Ich möchte, dass der Inhalt von diesem Overlay auf dieser Seite
/// angezeigt wird" — the FIRST version of this request just auto-opened the
/// modal on tap, which still covered the page; this is what was actually
/// asked for). [showExpeditionLaunchSheet] still wraps this in
/// [ParchmentSheet] for every other case — gathering, and a hunt where more
/// than one region is open and which one was meant is a real question.
class ExpeditionLaunchPanel extends StatefulWidget {
  final ExpeditionTarget target;
  final bool inline;
  const ExpeditionLaunchPanel({
    super.key,
    required this.target,
    this.inline = false,
  });

  @override
  State<ExpeditionLaunchPanel> createState() => _ExpeditionLaunchPanelState();
}

class _ExpeditionLaunchPanelState extends State<ExpeditionLaunchPanel> {
  final _creatures = CreaturesController();
  final _expeditions = ExpeditionController();
  final _settlement = SettlementController();

  final Set<String> _selected = {};
  bool _sending = false;

  /// Set while the roster is open FOR A SWAP — which member tapping a
  /// candidate replaces (user 2026-08-31: "da ich mit anklicken das Monster
  /// austauschen kann" — a filled place now opens the roster instead of
  /// removing itself). Null means the roster was opened from an empty
  /// place instead, and a pick just fills the next open one, same as
  /// before.
  String? _swapTargetId;

  /// Hunt only: which variant (index into kCaptureHuntOptions). Each has a
  /// fixed duration and find count — no longer a hunter count (2026-09-11).
  int _optionIndex = 0;

  /// The roster picker's own search box — a FIELD tied to this State's own
  /// lifecycle, not a local variable created and disposed per [_openPicker]
  /// call. Disposing it right after that call's `await` fired the sheet's
  /// CLOSING animation, not its removal from the tree: the sheet keeps
  /// rebuilding (and the SearchPill's TextField keeps reading the
  /// controller) for the rest of that animation, so an immediate dispose
  /// crashed it with "TextEditingController was used after being disposed".
  final _pickerSearch = TextEditingController();

  @override
  void dispose() {
    _pickerSearch.dispose();
    super.dispose();
  }

  AreaDef get _area => widget.target.area;
  bool get _isHunt => widget.target.isHunt;
  CaptureHuntOption get _option => kCaptureHuntOptions[_optionIndex];

  List<CreatureInstance> get _available => _creatures.availableForExpedition();
  List<CreatureInstance> get _members =>
      _available.where((c) => _selected.contains(c.id)).toList();

  /// Gather still uses the same growing party cap Battle does. Hunt instead
  /// scales with the chosen length ALONE (user 2026-09-11, confirmed after
  /// an earlier version of this also capped it at
  /// [CreaturesController.teamSizeCap]: "wenn ich 30' hunt auswähle, sollten
  /// unten 2 '+' Boxen sein" — that cap silently held every hunt at 1 slot
  /// until battle progress separately unlocked more, which is exactly the
  /// coupling hunt group size was supposed to have dropped) — one monster
  /// more per rung of [kCaptureHuntOptions], from 1 at 10 min up to 6 at
  /// 24 h, full stop.
  int get _groupCap => _isHunt ? _optionIndex + 1 : _creatures.teamSizeCap;

  GatherPlan? get _plan => widget.target.spot == null
      ? null
      : _expeditions.preview(
          area: _area,
          spot: widget.target.spot!,
          members: _members,
        );

  /// What a hunt here can find. EVERY species, minus the legendaries still
  /// standing (user 2026-07-27) — the area decides the danger, the level and
  /// the travel, no longer the guest list.
  List<SpeciesDef> get _pool => catchableSpecies(_settlement.dungeonMaxStage);

  int get _unlockedOptions => maxHuntOptionCount(
    _settlement.buildingHuntOptions + _settlement.pathHuntOptions,
  );

  void _toggle(CreatureInstance c) {
    final selected = _selected.contains(c.id);
    if (!selected && _selected.length >= _groupCap) {
      // Silently swapping the oldest pick would hide which monster left the
      // group. Say what the limit is instead — same message hunt and gather
      // now share, since both are capped by the same growing party size.
      _say(
        'You may send $_groupCap monster${_groupCap > 1 ? 's' : ''} — '
        'win battles to widen the party.',
      );
      return;
    }
    setState(() => selected ? _selected.remove(c.id) : _selected.add(c.id));
  }

  void _selectOption(int i) {
    setState(() {
      _optionIndex = i;
      // Switching to a shorter hunt can drop the cap below what's already
      // picked — trim from the end of the roster's own order rather than
      // leave more members filled in than the new cap has places for.
      while (_selected.length > _groupCap) {
        _selected.remove(_members.last.id);
      }
    });
  }

  // No pop-up any more (user 2026-08-29: "wirklich alle pop up
  // nachrichten... löschen") — kept as a real no-op method rather than
  // removed so its five call sites don't all need touching for the same
  // request.
  void _say(String message) {}

  Future<void> _send() async {
    setState(() => _sending = true);
    final err = _isHunt
        ? await _expeditions.startCapture(
            area: _area,
            members: _members,
            option: _option,
          )
        : await _expeditions.startGather(
            area: _area,
            spot: widget.target.spot!,
            members: _members,
          );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      // No more energy-specific exception here (user 2026-09-14): starting a
      // trip can no longer fail for energy at all — low energy now scales
      // the trip's own duration instead of blocking it, see
      // ExpeditionController.startGather/startCapture.
      Feel.deny();
      _say(err);
      return;
    }
    Feel.success();
    if (widget.inline) {
      // No modal to pop — the panel stays right where it is (still one hunt
      // to offer, most likely), ready for another group if slots allow.
      // ExpeditionController's own notifyListeners() is what actually moves
      // the new trip into "Out now"; this only clears this panel's own pick.
      setState(_selected.clear);
      if (context.mounted) context.snack('Off they go!');
      return;
    }
    Navigator.pop(context, true);
  }

  // WHERE, under the title — the region and its danger decide the level of
  // what lives there and how likely a casualty is, so they belong with the
  // heading rather than buried in the body.
  //
  // Hunt doesn't get this row any more (user 2026-09-11) — every species is
  // catchable everywhere now (see catchableSpecies's own doc comment), so
  // the area name/danger no longer explains what you might find, only where
  // the trip physically happens, which the "Hunt" title next to it already
  // implies well enough. Gather keeps it: the region genuinely decides which
  // resource is here.
  Widget _whereRow() {
    if (_isHunt) return const SizedBox.shrink();
    return Padding(
      // kMonsterTilePageMargin (24), not ParchmentPage.kParchmentPagePad —
      // this comment used to claim those were the same value (2026-08-31
      // audit: "24, not 26... matching the Monsters screen"), but
      // kParchmentPagePad is actually 36 (2026-09-11 fix, alongside the
      // Group grid below finally getting the same margin): this row sat
      // 12px further right than the content under it the whole time.
      padding: const EdgeInsets.fromLTRB(
        kMonsterTilePageMargin,
        0,
        kMonsterTilePageMargin,
        6,
      ),
      child: Row(
        children: [
          Text(widget.target.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_area.emoji} ${_area.name}',
              style: FoE.dim(size: 11).copyWith(color: ParchmentSheet.inkSoft),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.inline
      ? _buildInline()
      : ParchmentSheet(
          title: _isHunt ? 'Hunt' : 'Gather ${widget.target.label}',
          initialSize: 0.85,
          minSize: 0.5,
          maxSize: 0.95,
          trailing: Text(
            '${_expeditions.activeCount}/${_expeditions.maxSlots}',
            style: FoE.value(size: 13).copyWith(color: kAccent),
          ),
          builder: (context, scrollCtrl) => Column(
            children: [
              _whereRow(),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  // kMonsterTilePageMargin (24), not
                  // ParchmentPage.kParchmentPagePad (36) — user 2026-09-11:
                  // "bitte 3 Boxen nebeneinander und nicht nur 2". The
                  // Group section's [monsterTileGrid] sizes its tiles off
                  // the raw device width assuming a 24px host margin, same
                  // as the Monsters screen and this sheet's own roster
                  // GridView below; hosting it at 36 left just short of
                  // room for a third tile per row.
                  padding: const EdgeInsets.fromLTRB(
                    kMonsterTilePageMargin,
                    4,
                    kMonsterTilePageMargin,
                    14,
                  ),
                  children: _isHunt ? _huntBody() : _gatherBody(),
                ),
              ),
              _sendBar(),
            ],
          ),
        );

  /// The [ParchmentSheet]'s own chrome (drag handle, drag-sized sheet, title
  /// bar) dropped — embedded straight in the host page instead of under a
  /// sheet. NOT "sized to itself" any more (2026-09-22 fix): its one caller
  /// ([ExpeditionsScreen._targetsColumn]) hands it a bounded height through
  /// an `Expanded` slot beside the region rail, not an ambient scrolling
  /// list the way the doc comment here used to assume — a hunt with a big
  /// enough roster (a real, reported crash: "RenderFlex overflowed… Column
  /// ← ExpeditionLaunchPanel") simply had nowhere to go. The body scrolls
  /// within whatever height it is actually given now, exactly the way the
  /// modal sheet's own [build] already does above; [_whereRow] and
  /// [_sendBar] stay fixed top and bottom either way.
  Widget _buildInline() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _whereRow(),
      Expanded(
        child: ListView(
          padding: EdgeInsets.zero,
          children: _isHunt ? _huntBody() : _gatherBody(),
        ),
      ),
      const SizedBox(height: 12),
      _sendBar(),
    ],
  );

  // ── Gather ────────────────────────────────────────────────
  List<Widget> _gatherBody() {
    final spot = widget.target.spot!;
    final plan = _plan;
    final stock = _expeditions.availableStock(spot);
    // Capacity / regen / mining speed are per-RESOURCE dials now (Dev Mode →
    // Resources), not per spot.
    final dials = gatherDefFor(spot.resource);
    return [
      _panel([
        _kv(
          'In the ground',
          '${stock.toStringAsFixed(0)} / '
              '${dials.spotCapacity.toStringAsFixed(0)}',
        ),
        _bar(
          dials.spotCapacity <= 0 ? 0 : stock / dials.spotCapacity,
          kParchmentGo,
        ),
        const SizedBox(height: 8),
        _kv('Regrows', '${dials.regenPerHour.toStringAsFixed(0)}/h'),
        _kv(
          'One carry point holds',
          '${_fmtNum(dials.unitsPerCarry)} ${spot.resource}',
        ),
      ]),
      const SizedBox(height: 12),
      _panel([
        Text('This trip', style: FoE.label(size: 12).copyWith(color: kAccent)),
        const SizedBox(height: 8),
        _kv(
          'Haul',
          plan == null || !plan.isViable
              ? '—'
              : '${plan.amount.toStringAsFixed(0)} ${plan.resource}',
        ),
        _kv('Carry cap', plan?.loadCap.toStringAsFixed(0) ?? '0'),
        _kv('Mining rate', '${plan?.ratePerHour.toStringAsFixed(1) ?? '0'}/h'),
        _kv(
          'Duration',
          plan != null && plan.isViable ? fmtTripDuration(plan.duration) : '—',
        ),
      ]),
      const SizedBox(height: 14),
      ..._groupSection(
        hint:
            'Mining speed is the group\'s gather stat; the load cap is its '
            'carry. A full load ends the trip.',
        // The two stats a miner is judged on, exactly where the caravan
        // picker puts its carry/speed pair.
        caption: (c) =>
            '⛏️ ${gatherPowerOf(c)}   '
            '🎒 ${c.statValue(CreatureStat.carry)}',
      ),
    ];
  }

  // ── Hunt ──────────────────────────────────────────────────
  List<Widget> _huntBody() {
    final pool = _pool;
    if (pool.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No species are defined yet.\nAdd some in '
            'Dev Mode → Species.',
            textAlign: TextAlign.center,
            style: FoE.dim(size: 12),
          ),
        ),
      ];
    }
    final present = pool.map((s) => s.rarity).toSet();

    // WHAT THE SHEET NO LONGER SHOWS (user 2026-07-30: "what lives here kann
    // komplett gelöscht werden. Catch timing kann gelöscht werden. Seltenheit
    // kann in ein kleines 'i' gepackt werden").
    //
    // Two full panels used to sit between the player and the only decision on
    // this sheet — which variant, and who goes. A roster of every catchable
    // species, and a per-rarity timing table. Neither changes with the choice;
    // both are reference. The rarity ODDS used to move with the variant too,
    // but no longer do (user 2026-09-11: length should only change how many
    // finds you get, never their odds) — still one tap away, as reference.
    return [
      ParchmentSectionHeader(
        title: 'Hunt length',
        trailing: ParchmentInfoButton(
          title: 'Find odds',
          content: (_) => _oddsRows(present),
        ),
      ),
      // No caption here (user 2026-09-11) — "a longer hunt needs more
      // hunters" is true again (see [_groupCap]) but the Group section right
      // below already says so via its own "n / cap chosen" hint.
      const SizedBox(height: 4),
      // THREE ACROSS (user 2026-07-30: "immer drei hunt optionen
      // nebeneinander"). Six full-width rows pushed the group picker off the
      // sheet entirely; as a grid the whole ladder is one glance.
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          mainAxisExtent: 92,
        ),
        itemCount: kCaptureHuntOptions.length,
        itemBuilder: (_, i) => _variantTile(i),
      ),
      const SizedBox(height: 14),
      // No hint here any more (user 2026-09-11) — the sentence explaining the
      // catch-by-hand mini-game was cut along with the length caption above.
      ..._groupSection(
        caption: (c) => '🪤 ${c.statValue(CreatureStat.catchRate)}',
      ),
    ];
  }

  /// Find odds, one row per rarity — the SAME regardless of hunt length
  /// (2026-09-11: length only changes how many finds you get, never their
  /// odds, so there is nothing left to key this off the selected variant).
  ///
  /// Legendary always gets a row, even before [present] contains it — it
  /// never joins the pool until its region's boss is down (see
  /// [catchableSpecies]), so instead of a percentage it shows the reason it
  /// is missing rather than silently vanishing from the list.
  List<Widget> _oddsRows(Set<CreatureRarity> present) {
    final legendaryUnlocked = present.contains(CreatureRarity.legendary);
    final shown = [
      for (final r in CreatureRarity.values)
        if (r != CreatureRarity.legendary && present.contains(r)) r,
      CreatureRarity.legendary,
    ];
    final weights = rarityWeights();
    final total = shown
        .where((r) => r != CreatureRarity.legendary || legendaryUnlocked)
        .fold<double>(0, (s, r) => s + (weights[r] ?? 0));
    return [
      for (final r in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Text(
                r.label,
                style: FoE.label(size: 11).copyWith(color: r.color),
              ),
              const SizedBox(width: 6),
              Text(
                '${qteHitsRequired(r)} hit${qteHitsRequired(r) > 1 ? 's' : ''}',
                style: FoE.dim(size: 9).copyWith(color: kInkFaint),
              ),
              const Spacer(),
              if (r == CreatureRarity.legendary && !legendaryUnlocked)
                Text(
                  'beat the 1st boss',
                  style: FoE.dim(size: 9).copyWith(color: kInkFaint),
                )
              else
                Text(
                  total > 0
                      ? '${((weights[r] ?? 0) / total * 100).round()}%'
                      : '0%',
                  style: FoE.value(size: 11).copyWith(color: kInk),
                ),
            ],
          ),
        ),
    ];
  }

  /// One hunt length, as a CARD rather than a row — three fit across.
  ///
  /// What survived the squeeze is what the choice is actually made on: how
  /// long, how many finds. The lock reason moved to the tap, because a grid
  /// cell has no room for a sentence and the sentence is only needed once.
  Widget _variantTile(int i) {
    final o = kCaptureHuntOptions[i];
    // Locked by campaign progress ONLY now (2026-09-11) — team size stopped
    // gating a variant the moment hunts stopped requiring an exact,
    // variant-sized team (see kCaptureHuntOptions's own comment).
    final locked = i >= _unlockedOptions;
    final active = _optionIndex == i;
    return Pressable(
      onTap: () {
        if (!locked) {
          _selectOption(i);
        } else {
          _say('Win more battles to unlock the ${o.label} hunt.');
        }
      },
      child: Opacity(
        opacity: locked ? 0.5 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: ShapeDecoration(
            color: active
                ? kAccent.withValues(alpha: 0.12)
                : kInk.withValues(alpha: 0.06),
            shape: FoE.facet(
              radius: 10,
              side: BorderSide(
                color: active
                    ? kAccent.withValues(alpha: 0.55)
                    : kInk.withValues(alpha: 0.18),
                width: active ? 1.6 : 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${locked ? '🔒 ' : ''}${o.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FoE.title(
                  size: 13,
                ).copyWith(color: active ? kAccent : kInk),
              ),
              const SizedBox(height: 3),
              Text(
                '🪤 ${o.finds} find${o.finds > 1 ? 's' : ''}',
                style: FoE.label(size: 11).copyWith(color: kInkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Group picker (shared) ─────────────────────────────────
  // PLACES, NOT A ROSTER (user 2026-07-30: "Unten nicht alle monster, sondern
  // diese Buttons entsprechend der möglichen Monsterzahl").
  //
  // It listed every free monster, which on a full collection is a wall of tiles
  // between the player and the Send button — and it never showed the one number
  // that decides the trip: how many may go. Now the sheet shows exactly that
  // many PLACES, the way the Market shows a caravan's, and filling one opens the
  // roster. Same frame as the Hatchery's egg slot and the breeding screen's
  // parents, so an empty place lines up with the tile that will fill it.
  //
  // Shared by hunt and gather: both ask "who goes", only the cap and the
  // caption differ.
  List<Widget> _groupSection({
    String? hint,
    required String Function(CreatureInstance) caption,
  }) => [
    ParchmentSectionHeader(
      title: 'Group',
      hint: '${_members.length} / $_groupCap chosen',
    ),
    if (hint != null)
      Text(hint, style: FoE.dim(size: 10).copyWith(color: kInkFaint)),
    // "THE SAME AGAIN" (user 2026-07-30). Sending a party is the most repeated
    // action in the game, and it was a fresh hunt through the roster every time.
    // Only shown when it would actually DO something: there is a remembered
    // party, somebody in it is still free, and they are not already picked.
    if (_lastPartyAvailable().isNotEmpty) ...[
      const SizedBox(height: 8),
      _sameAgainButton(),
    ],
    const SizedBox(height: 10),
    // The shared tile size (user 2026-08-31: "genau gleich gross sein wie
    // die Kacheln beim Monstersscreen"), not this sheet's own delegate.
    // Centred rather than left-hugging when there is only ONE place (user
    // 2026-09-11: "das '+' Feld zentrieren") — the 10 min hunt (and Gather,
    // early on) still caps at a single hunter, and a lone tile pinned to the
    // left of a full-width row reads as stranded.
    monsterTileGrid([
      for (var i = 0; i < _groupCap; i++)
        i < _members.length
            ? _filledPlace(_members[i])
            : _emptyPlace(isNext: i == _members.length),
    ], alignment: _groupCap == 1 ? WrapAlignment.center : WrapAlignment.start),
  ];

  /// A place waiting to be filled. A tap opens the roster.
  ///
  /// Only the NEXT one to be filled says "Add" — six copies of the word is
  /// noise, and one is a caption for the whole rank.
  Widget _emptyPlace({required bool isNext}) =>
      EmptyMonsterSlot(label: isNext ? 'Add' : null, onTap: _openPicker);

  /// A filled place: THE monster tile, unchanged from every other screen.
  ///
  /// A TAP OPENS THE ROSTER TO SWAP IT (user 2026-08-31: "das x im Kreis
  /// löschen, da ich mit anklicken das Monster austauschen kann") — no more
  /// ✗ badge; the tile itself is the only entry point now, same as the
  /// work-post picker's own filled seats. The roster offers a dedicated
  /// EMPTY tile for the case that used to be this tap's whole job.
  Widget _filledPlace(CreatureInstance c) => CreatureCard(
    creature: c,
    onTap: () => _openPicker(swapTargetId: c.id),
  );

  /// The roster, as a sheet over this one — opened only while a place is being
  /// filled, which is what keeps it off the page the rest of the time.

  /// The remembered party, minus whoever cannot go now (K.O., stationed away,
  /// breeding, already out) and minus anyone already picked — capped at the
  /// group size. Empty when the shortcut would change nothing.
  List<CreatureInstance> _lastPartyAvailable() {
    final ids = _expeditions
        .lastParty[_isHunt ? ExpeditionType.capture : ExpeditionType.gather];
    if (ids == null) return const [];
    final free = {for (final c in _available) c.id: c};
    final out = <CreatureInstance>[];
    for (final id in ids) {
      final c = free[id];
      if (c == null || _selected.contains(id)) continue;
      if (out.length + _selected.length >= _groupCap) break;
      out.add(c);
    }
    return out;
  }

  Widget _sameAgainButton() {
    final party = _lastPartyAvailable();
    final missing =
        (_expeditions
                .lastParty[_isHunt
                    ? ExpeditionType.capture
                    : ExpeditionType.gather]
                ?.length ??
            0) -
        party.length -
        _selected.length;
    return Pressable(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Feel.tap();
        setState(() {
          for (final c in party) {
            _selected.add(c.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: goldButton(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.replay_rounded, size: 14, color: kInk),
            const SizedBox(width: 6),
            Text(
              'Same as last time (${party.length})',
              style: FoE.label(size: 11).copyWith(color: kInk),
            ),
            // Honest about what it CANNOT bring back — silently sending a
            // smaller party than the one you remember is the worse failure.
            if (missing > 0) ...[
              const SizedBox(width: 6),
              Text(
                '· $missing busy',
                style: FoE.dim(size: 10).copyWith(color: kInkFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Candidates the roster actually offers. Opened plain (from an empty
  /// place), it is every free monster, exactly as before — the multi-pick
  /// flow taps several in a row. Opened to SWAP one member, the outgoing
  /// monster is left off the list (the dedicated empty tile is how you
  /// clear it instead) and so is anyone ELSE already in the group — picking
  /// one of those would silently shrink the party rather than swap it.
  List<CreatureInstance> get _pickerCandidates {
    final swapping = _swapTargetId;
    if (swapping == null) return _available;
    return _available
        .where((c) => c.id != swapping && !_selected.contains(c.id))
        .toList();
  }

  Future<void> _openPicker({String? swapTargetId}) async {
    if (_available.isEmpty) {
      _say('Nobody is free — everyone is K.O., stationed, breeding or out.');
      return;
    }
    _swapTargetId = swapTargetId;
    final swapping = swapTargetId != null;

    // Sort/filter/search, added everywhere a monster or a group is picked
    // (user 2026-09-11: "überall, wo ich ein Monster oder eine Gruppe
    // auswähle, sollen diese nach dem entsprechenden Wert geordnet sein und
    // eine Sortier, Filter- und Suchfunktion haben"). The controller is
    // [_pickerSearch], a State field — NOT created and disposed here per
    // open (see that field's own comment for why that crashed).
    _pickerSearch.clear();
    String query = '';
    CreatureElement? filterElement;
    String? sortKey; // null = the trip's own stat (catch rate / mining power)
    bool descending = true;

    double primary(CreatureInstance c) => _isHunt
        ? c.statValue(CreatureStat.catchRate).toDouble()
        : gatherPowerOf(c).toDouble();

    List<CreatureInstance> filtered() {
      final q = query.trim().toLowerCase();
      final list = [
        for (final c in _pickerCandidates)
          if ((filterElement == null || c.species?.element == filterElement) &&
              (q.isEmpty || c.displayName.toLowerCase().contains(q)))
            c,
      ];
      int cmp(CreatureInstance a, CreatureInstance b) {
        final r = switch (sortKey) {
          'level' => a.level.compareTo(b.level),
          'name' => a.displayName.compareTo(b.displayName),
          _ => primary(a).compareTo(primary(b)),
        };
        return descending ? -r : r;
      }

      list.sort(cmp);
      return list;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ParchmentSheet(
        // Named for what it picks, not the question that opens it (user
        // 2026-08-31: "dieser Screen heisst Group") — the same word the
        // section above it already carries.
        title: 'Group',
        initialSize: 0.7,
        builder: (sheetCtx, scrollCtrl) => StatefulBuilder(
          // Its own builder so a pick repaints the picker; the places behind it
          // catch up when it closes.
          builder: (sheetCtx, setSheetState) {
            final candidates = filtered();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kMonsterTilePageMargin,
                    4,
                    kMonsterTilePageMargin,
                    8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: SearchPill(
                          controller: _pickerSearch,
                          palette: PillPalette.cream,
                          onChanged: (v) => setSheetState(() => query = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: MenuPill<String>(
                          palette: PillPalette.cream,
                          icon: Icons.swap_vert,
                          label: switch (sortKey) {
                            'level' => 'Level',
                            'name' => 'Name',
                            _ => _isHunt ? 'Catch' : 'Mining',
                          },
                          engaged: sortKey != null || !descending,
                          value: sortKey ?? '',
                          entries: [
                            MapEntry('', _isHunt ? 'Catch' : 'Mining'),
                            const MapEntry('level', 'Level'),
                            const MapEntry('name', 'Name'),
                          ],
                          trailing: Icon(
                            descending
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 14,
                            color: FoE.goldBright,
                          ),
                          selectedTrailing: descending ? '↓' : '↑',
                          onSelected: (v) => setSheetState(() {
                            final picked = v.isEmpty ? null : v;
                            if (picked == sortKey) {
                              descending = !descending;
                            } else {
                              sortKey = picked;
                              descending = true;
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: MenuPill<String>(
                          palette: PillPalette.cream,
                          icon: Icons.filter_alt_outlined,
                          label: filterElement?.label ?? 'Every type',
                          engaged: filterElement != null,
                          value: filterElement?.name ?? '',
                          entries: [
                            const MapEntry('', 'Every type'),
                            for (final e in CreatureElement.values)
                              if (e != CreatureElement.neutral)
                                MapEntry(e.name, '${e.emoji} ${e.label}'),
                          ],
                          onSelected: (v) => setSheetState(
                            () => filterElement = v.isEmpty
                                ? null
                                : CreatureElement.fromName(v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    controller: scrollCtrl,
                    // 24, not 26 (user 2026-08-31: "genau gleich gross sein
                    // wie die Kacheln beim Monstersscreen") — the 2px
                    // difference from [kMonsterTilePageMargin] was enough to
                    // hand every tile in this sheet a slightly narrower cell
                    // than the Monsters grid's own.
                    padding: const EdgeInsets.fromLTRB(
                      kMonsterTilePageMargin,
                      0,
                      kMonsterTilePageMargin,
                      20,
                    ),
                    gridDelegate: monsterTileGridDelegate(sheetCtx),
                    itemCount: candidates.length + (swapping ? 1 : 0),
                    itemBuilder: (_, i) {
                      // A dedicated EMPTY tile (user 2026-08-31: "beim
                      // Auswahlscreen eine 'leere' Kachel anbieten, wenn ich
                      // diese anwähle, dann ist dieser Slot leer") —
                      // swapping in nothing, the same clearing job the ✗
                      // badge used to do, but as a real choice in the roster
                      // instead of a shortcut on the tile behind it.
                      if (swapping && i == 0) {
                        return EmptyMonsterSlot(
                          label: 'Empty',
                          onTap: () {
                            setState(() => _selected.remove(_swapTargetId));
                            Navigator.pop(sheetCtx);
                          },
                        );
                      }
                      final c = candidates[i - (swapping ? 1 : 0)];
                      return _pickerTile(c, sheetCtx, setSheetState);
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    _swapTargetId = null;
    if (mounted) setState(() {});
  }

  Widget _pickerTile(
    CreatureInstance c,
    BuildContext sheetCtx,
    void Function(VoidCallback) setSheetState,
  ) {
    final picked = _selected.contains(c.id);
    return Stack(
      children: [
        Positioned.fill(
          child: Opacity(
            opacity: picked ? 0.45 : 1,
            child: CreatureCard(
              creature: c,
              // The stat this trip is actually judged on, in the tile
              // itself (user 2026-08-31: "den gleichen Stil übernehmen" —
              // the work-post picker's flag on the tile)
              // instead of a caption line below it.
              extras: [
                TileValue(
                  _isHunt ? 'Catch' : 'Mining',
                  _isHunt
                      ? c.statValue(CreatureStat.catchRate)
                      : gatherPowerOf(c),
                ),
              ],
              onTap: () {
                if (_swapTargetId != null) {
                  setState(() {
                    _selected.remove(_swapTargetId);
                    _selected.add(c.id);
                  });
                  Navigator.pop(sheetCtx);
                  return;
                }
                _toggle(c);
                setSheetState(() {});
                // A full group means the question is answered; holding
                // the picker open would leave a list that refuses every
                // further tap.
                if (_members.length >= _groupCap) {
                  Navigator.pop(sheetCtx);
                }
              },
            ),
          ),
        ),
        if (picked)
          const Positioned(
            top: 2,
            left: 2,
            child: Icon(Icons.check_circle, size: 18, color: kAccent),
          ),
      ],
    );
  }

  // ── Send ──────────────────────────────────────────────────
  Widget _sendBar() {
    final full = _expeditions.slotsFull;
    final plan = _plan;
    final ready = _isHunt
        ? _members.isNotEmpty
        : _members.isNotEmpty && plan != null && plan.isViable;
    final canSend = !_sending && !full && ready;

    final label = full
        // Zero slots is not a queue — name the building that opens them
        // instead of a busy party that isn't there (user 2026-07-29).
        ? _expeditions.noSlots
              ? 'No expedition slots — build a Scout Post'
              : 'All expedition slots busy '
                    '(${_expeditions.activeCount}/${_expeditions.maxSlots})'
        : _isHunt
        ? ready
              ? 'Send ${_option.label} hunt · '
                    '${fmtTripDuration(captureDuration(_option))}'
              : 'Pick who goes'
        : ready
        ? 'Send expedition · ${fmtTripDuration(plan!.duration)}'
        : _members.isEmpty
        ? 'Pick who goes'
        : 'Nothing left to mine here';

    // The send bar is a FOOTER cut from the same paper, not a dark strip
    // bolted under the sheet (user 2026-07-29 redraw). A hairline above it is
    // what separates it from the scrolling list; the shadow does the rest.
    // Inline, there is no fixed-height sheet to foot — it is just the next
    // thing in the page's own flow, so the footer chrome and the bottom
    // safe-area padding (meant for a bar actually pinned to the screen's own
    // edge) both drop.
    return Container(
      width: double.infinity,
      decoration: widget.inline
          ? null
          : BoxDecoration(
              color: Strategy.cream,
              border: Border(
                top: BorderSide(color: kInk.withValues(alpha: 0.18)),
              ),
              boxShadow: [
                BoxShadow(
                  color: kInk.withValues(alpha: 0.16),
                  blurRadius: 0,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
      padding: widget.inline
          ? EdgeInsets.zero
          : EdgeInsets.fromLTRB(
              20,
              10,
              20,
              10 + MediaQuery.of(context).viewPadding.bottom,
            ),
      child: _sending
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kAccent,
                  ),
                ),
              ),
            )
          : ParchmentButton(
              label: label,
              expand: true,
              primary: canSend,
              onTap: canSend ? _send : null,
            ),
    );
  }

  // ── Small shared pieces ───────────────────────────────────
  Widget _panel(List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: ParchmentSheet.card,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );

  Widget _kv(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Text(label, style: FoE.dim(size: 11).copyWith(color: kInkFaint)),
        const Spacer(),
        Text(value, style: FoE.value(size: 12).copyWith(color: kInk)),
      ],
    ),
  );

  Widget _bar(double fraction, Color color) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: RecessBar(value: fraction.clamp(0.0, 1.0), color: color, height: 9),
  );

  /// 20 → "20", 0.5 → "0.5" — carry weights are not always whole.
  static String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

/// Trip lengths read as "1h 20m" / "12m" / "45s" everywhere they appear — the
/// planner sheet and the running-trip cards shared two near-identical copies of
/// this before.
String fmtTripDuration(Duration d) {
  if (d.inSeconds <= 0) return 'instant';
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s}s';
  return '${s}s';
}
