import 'package:flutter/foundation.dart';

import '../supabase/supabase_client.dart';

/// The dial DECLARATIONS and the named getters the game reads them through.
/// Split out so this file stays about the mechanism and that one about the
/// game; a part rather than an import because the two are mutually recursive
/// (the getters read [GameTuning], [GameTuning] walks [kDials]).
part 'dials.dart';

// ignore_for_file: unnecessary_library_name

// ── Every hardcoded number, in one place and editable ──────────────────────
// User 2026-07-29: "Grundsätzlich will ich dies alles einstellen können … Ich
// will 'unabhängig' von dir sein. Alles was ich im Devmode eingebe, soll direkt
// übernommen werden für alle." — and, on the shape of it: "mir ist wichtig,
// dass es so einfach und übersichtlich wie nur möglich ist."
//
// Before this, ~40 gameplay numbers lived as `const` in a dozen files: the base
// slot counts, the +50 %/level curve, the build- and breeding-time curves, the
// energy budget, the healing and trade ceilings, the party-size ladder, the
// risk model, every AP cost, the crit and accuracy dials, the gene spread, the
// catch minigame. Each was a decision nobody could revisit without a code
// change — the exact opposite of "ich muss dies noch sehr oft machen".
//
// ── Why a REGISTRY and not forty fields ──
// Each dial is declared ONCE, right here, with the four things both sides need:
// what it is called, what it means, what it defaults to, and how to read its
// value back in words. The game reads it through a named getter (so no call
// site changed) and Dev Mode RENDERS THE SAME DECLARATION — there is no second
// list of labels to keep in sync, and adding a dial is one entry, not a model
// field plus a form field plus a save path.
//
// Values live in the `game_config` table (key/value jsonb), one row per group —
// the very pattern species_balance / xp_balance / heal_balance already use. So
// a dial set in Dev Mode is live for everyone on the next load, and a dial
// never set falls back to the code default below.

/// Which menu a dial belongs to, and where its values are stored.
enum TuningGroup {
  settlement('Settlement', '🏛', 'tuning_settlement'),
  campaign('Kampagne', '🗺', 'tuning_campaign'),
  monster('Monster', '🐾', 'tuning_monster');

  final String label;
  final String emoji;

  /// The `game_config.key` this group's values are stored under.
  final String configKey;
  const TuningGroup(this.label, this.emoji, this.configKey);
}

/// How a dial's number is entered and read back.
enum DialKind {
  /// A whole count — slots, levels, action points.
  count,

  /// A fraction stored as 0..1 but ENTERED AND SHOWN as a percent, because
  /// that is how every other number in this game is discussed (user
  /// 2026-07-26: "zeige, um wieviel Prozent …").
  percent,

  /// A plain decimal — a multiplier, a curve constant, a rate.
  decimal,

  /// Seconds, entered as MINUTES: nobody tunes a trip in seconds.
  minutes,

  /// Hours.
  hours,
}

/// One tunable number: what the game reads and what the menu renders.
class Dial {
  final String id;
  final TuningGroup group;

  /// The heading this dial sits under in the menu. Dials sharing a section
  /// appear together, in declaration order.
  final String section;

  /// What it is, in the words the author thinks in.
  final String label;

  /// One line on what it actually does. Kept short on purpose — a paragraph
  /// per dial would defeat "übersichtlich".
  final String help;

  /// The value shipped in code, used until someone changes it.
  final double def;

  final DialKind kind;

  /// The lowest value that still makes sense, if any. Guards against a typo
  /// silently disabling a whole system (a 0 here is often a real choice
  /// though, so most dials leave it null).
  final double? min;

  /// "What does this number MEAN" — one live line under the field, in felt
  /// units. Null when the label already says it.
  final String Function(double v)? felt;

  const Dial({
    required this.id,
    required this.group,
    required this.section,
    required this.label,
    required this.help,
    required this.def,
    this.kind = DialKind.decimal,
    this.min,
    this.felt,
  });

  /// The unit shown next to the input.
  String get unit => switch (kind) {
    DialKind.percent => '%',
    DialKind.minutes => 'min',
    DialKind.hours => 'h',
    _ => '',
  };

  /// Stored value → what the field shows.
  double toField(double stored) => switch (kind) {
    DialKind.percent => stored * 100,
    DialKind.minutes => stored / 60,
    _ => stored,
  };

  /// What the field shows → stored value.
  double fromField(double shown) => switch (kind) {
    DialKind.percent => shown / 100,
    DialKind.minutes => shown * 60,
    _ => shown,
  };
}

/// The live values. Read through the named getters in `dials.dart` — nothing
/// outside this file and the Dev-Mode menu should touch it by id.
class GameTuning extends ChangeNotifier {
  GameTuning._();
  static final GameTuning i = GameTuning._();

  /// Overrides, by dial id. A dial absent here is at its code default, which
  /// is why a fresh install and a never-touched dial behave identically.
  final Map<String, double> _values = {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// The raw value of [id] — its override, else the declared default.
  double raw(String id) => _values[id] ?? _dialById[id]?.def ?? 0;

  /// [raw] rounded to a whole number, for the count dials.
  int count(String id) => raw(id).round();

  /// Whether [id] has been changed away from what the code ships.
  bool isOverridden(String id) => _values.containsKey(id);

  /// Sets [id] in memory. Nothing is persisted until [save] — so a half-typed
  /// number can't reach the other players mid-keystroke.
  void set(String id, double value) {
    _values[id] = value;
    notifyListeners();
  }

  /// Drops [id] back to the code default.
  void reset(String id) {
    _values.remove(id);
    notifyListeners();
  }

  /// Every dial of [group], with its current value — what the menu renders and
  /// what [save] writes.
  Map<String, double> valuesOf(TuningGroup group) => {
    for (final d in kDials)
      if (d.group == group) d.id: raw(d.id),
  };

  /// Loads every group. Silent on failure (missing table, offline): the code
  /// defaults are a complete, playable configuration, so tuning must never be
  /// able to break startup.
  Future<void> load() async {
    try {
      final rows = await supabase
          .from('game_config')
          .select('key, value')
          .inFilter(
            'key',
            [for (final g in TuningGroup.values) g.configKey],
          );
      for (final row in (rows as List)) {
        final v = (row as Map)['value'];
        if (v is! Map) continue;
        for (final e in v.entries) {
          final id = e.key.toString();
          // Ignore keys no dial declares any more — a renamed or deleted dial
          // must not resurrect as a value nothing reads.
          if (!_dialById.containsKey(id)) continue;
          final n = e.value;
          if (n is num) _values[id] = n.toDouble();
        }
      }
    } catch (e) {
      debugPrint('[GameTuning] load failed, using code defaults: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Writes one group's dials. Returns an error message, or null on success.
  Future<String?> save(TuningGroup group) async {
    try {
      await supabase.from('game_config').upsert({
        'key': group.configKey,
        'value': valuesOf(group),
      });
      return null;
    } catch (e) {
      return 'Speichern fehlgeschlagen: $e';
    }
  }

  /// Test hook: forget every override.
  @visibleForTesting
  void debugClear() {
    _values.clear();
    _loaded = false;
  }
}

/// Declaration lookup, built once.
final Map<String, Dial> _dialById = {for (final d in kDials) d.id: d};

