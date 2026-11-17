import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Text;

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/cream_kit.dart';
import '../../core/ui/game_text.dart';
import '../../core/ui/pressable.dart';
import '../../core/ui/snack.dart';
import '../creatures/services/breeding_controller.dart';
import '../creatures/services/creatures_controller.dart';
import '../settlement/settlement_controller.dart';
import 'guild_service.dart';
import 'guild_studs.dart';

/// What a guild help is worth, and the most one request takes — the database
/// enforces the cap of 10 (migration 0070); this number is the tuning dial for
/// the worth. Percent of the time STILL TO RUN, no minimum.
const double kGuildHelpFraction = 0.03;
const int kGuildHelpCap = 10;

enum GuildHelpKind {
  build('build', 'Construction'),
  breed('breed', 'Breeding'),
  heal('heal', 'Healing');

  final String key;
  final String noun;
  const GuildHelpKind(this.key, this.noun);

  static GuildHelpKind? parse(String? s) {
    for (final k in values) {
      if (k.key == s) return k;
    }
    return null;
  }
}

/// A guild mate's request that I could help with.
class GuildHelpRequest {
  final String id;
  final String requesterName;
  final GuildHelpKind kind;
  final String label;
  final int helps;
  final DateTime expiresAt;

  const GuildHelpRequest({
    required this.id,
    required this.requesterName,
    required this.kind,
    required this.label,
    required this.helps,
    required this.expiresAt,
  });
}

/// Asking for help, giving it, and applying what came in. One instance; the
/// settlement load starts it for guild members.
///
/// Receiving never touches anyone else's data: a help is its own database row,
/// and THIS game shortens ITS OWN timers when it collects them ([applyPending]),
/// a minute at a time while the app is open and once on every start.
class GuildHelp extends ChangeNotifier {
  GuildHelp._();
  static final GuildHelp instance = GuildHelp._();

  Timer? _timer;

  /// My live requests, by `kind:target` → helps so far.
  final Map<String, int> _mine = {};

  /// Requests from guild mates waiting for me.
  List<GuildHelpRequest> open = [];

  String _key(GuildHelpKind k, String target) => '${k.key}:$target';

  /// Null = not asked for; otherwise how many helps it has so far.
  int? requestedHelps(GuildHelpKind kind, String target) =>
      _mine[_key(kind, target)];

  /// Begins (or stops) the minute loop to match the membership.
  void sync() {
    if (GuildMembership.instance.inGuild) {
      _timer ??= Timer.periodic(const Duration(seconds: 60), (_) => tick());
      unawaited(tick());
    } else {
      _timer?.cancel();
      _timer = null;
      _mine.clear();
      open = [];
      notifyListeners();
    }
  }

  int _ticks = 0;

  Future<void> tick() async {
    if (!GuildMembership.instance.inGuild) return;
    // The level moves as points come in; look again every few minutes.
    if (++_ticks % 5 == 0) await GuildMembership.instance.refresh();
    unawaited(GuildStuds.instance.takeFees());
    await applyPending();
    await refresh();
  }

  /// Reloads my requests and the ones waiting for me. Never throws.
  Future<void> refresh() async {
    try {
      final mine = await supabase.rpc('guild_my_requests') as List;
      final open_ = await supabase.rpc('guild_open_requests') as List;
      _mine
        ..clear()
        ..addAll({
          for (final r in mine.cast<Map<String, dynamic>>())
            '${r['kind']}:${r['target_id']}': (r['helps'] as num).toInt(),
        });
      open = [
        for (final r in open_.cast<Map<String, dynamic>>())
          if (GuildHelpKind.parse(r['kind'] as String?) != null)
            GuildHelpRequest(
              id: r['id'] as String,
              requesterName: r['requester_name'] as String,
              kind: GuildHelpKind.parse(r['kind'] as String?)!,
              label: r['label'] as String,
              helps: (r['helps'] as num).toInt(),
              expiresAt: DateTime.parse(r['expires_at'] as String).toLocal(),
            ),
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('[GuildHelp] refresh failed: $e');
    }
  }

  /// Collects the helps that came in and shortens my own timers.
  Future<void> applyPending() async {
    try {
      final rows = await supabase.rpc('guild_take_helps') as List;
      for (final r in rows.cast<Map<String, dynamic>>()) {
        final n = (r['n'] as num).toInt();
        // n helps in a row: each takes the same share of what is left.
        final fraction = 1 - math.pow(1 - kGuildHelpFraction, n).toDouble();
        final target = r['target_id'] as String;
        switch (GuildHelpKind.parse(r['kind'] as String?)) {
          case GuildHelpKind.build:
            await SettlementController().applyGuildHelpBuild(target, fraction);
          case GuildHelpKind.breed:
            await BreedingController().applyGuildHelp(target, fraction);
          case GuildHelpKind.heal:
            await CreaturesController().applyGuildHelpHeal(target, fraction);
          case null:
            break;
        }
      }
    } catch (e) {
      debugPrint('[GuildHelp] apply failed: $e');
    }
  }

  /// Asks the guild. Returns an error text, or null on success.
  Future<String?> request(
    GuildHelpKind kind,
    String target,
    String label,
    DateTime endsAt,
  ) async {
    try {
      await supabase.rpc(
        'guild_request_help',
        params: {
          'p_kind': kind.key,
          'p_target': target,
          'p_label': label,
          'p_expires': endsAt.toUtc().toIso8601String(),
        },
      );
      _mine[_key(kind, target)] = 0;
      notifyListeners();
      return null;
    } catch (e) {
      return guildErrorText(e);
    }
  }

  /// Helps one request. Returns 'ok', 'already', 'capped', 'expired' or an
  /// error text starting with '!'.
  Future<String> give(GuildHelpRequest r) async {
    try {
      final res =
          await supabase.rpc('guild_give_help', params: {'p_request': r.id})
              as String;
      open = [for (final x in open) if (x.id != r.id) x];
      notifyListeners();
      return res;
    } catch (e) {
      return '!${guildErrorText(e)}';
    }
  }
}

/// "Ask guild" for one running timer. Draws nothing for a player in no guild.
/// After asking it reads "Asked · 3 helped" and cannot be pressed again.
class GuildHelpButton extends StatelessWidget {
  final GuildHelpKind kind;
  final String target;
  final String label;

  /// When the timer would end without help.
  final DateTime endsAt;

  /// A small pill for tight spots (a slot card, an egg row).
  final bool compact;

  const GuildHelpButton({
    this.compact = false,
    super.key,
    required this.kind,
    required this.target,
    required this.label,
    required this.endsAt,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([GuildMembership.instance, GuildHelp.instance]),
    builder: (context, _) {
      if (!GuildMembership.instance.inGuild || !endsAt.isAfter(DateTime.now())) {
        return const SizedBox.shrink();
      }
      final helps = GuildHelp.instance.requestedHelps(kind, target);
      final asked = helps != null;
      return Pressable(
        onTap: asked
            ? null
            : () async {
                final err = await GuildHelp.instance.request(
                  kind,
                  target,
                  label,
                  endsAt,
                );
                if (context.mounted) {
                  context.snack(err ?? 'Your guild has been asked.', error: err != null);
                }
              },
        child: Container(
          height: compact ? 24 : 28,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          alignment: Alignment.center,
          decoration: asked ? menuButton(locked: true) : goldButton(),
          child: Text(
            compact
                ? (asked ? '{1F6E1} $helps' : '{1F6E1} Help')
                : (asked ? 'Asked · $helps helped' : 'Ask guild'),
            style: TextStyle(
              fontSize: 12,
              color: asked ? kBoxInkSoft : goldButtonInk(),
            ),
          ),
        ),
      );
    },
  );
}
