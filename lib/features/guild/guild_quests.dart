import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/supabase/supabase_client.dart';
import 'guild_service.dart';

/// One of the guild's three weekly quests. See migration 0072.
class GuildQuest {
  final String kind; // 'wins' | 'helps' | 'builds'
  final int goal;
  final int progress;
  final bool rewarded;

  const GuildQuest({
    required this.kind,
    required this.goal,
    required this.progress,
    required this.rewarded,
  });

  String get title => switch (kind) {
    'wins' => 'Win battles together',
    'helps' => 'Help each other',
    _ => 'Finish buildings',
  };

  bool get done => progress >= goal;

  /// Guild points the quest pays when its goal is reached.
  static const int reward = 100;
}

class GuildQuests {
  GuildQuests._();

  /// This week's quests, plus when they end. Null when not in a guild or the
  /// table is not there yet.
  static Future<({List<GuildQuest> quests, DateTime endsAt})?> current() async {
    try {
      final rows = await supabase.rpc('guild_quests_current') as List;
      if (rows.isEmpty) return null;
      final list = rows.cast<Map<String, dynamic>>();
      return (
        quests: [
          for (final r in list)
            GuildQuest(
              kind: r['kind'] as String,
              goal: (r['goal'] as num).toInt(),
              progress: (r['progress'] as num).toInt(),
              rewarded: r['rewarded'] as bool,
            ),
        ],
        endsAt: DateTime.parse(list.first['ends_at'] as String).toLocal(),
      );
    } catch (e) {
      debugPrint('[GuildQuests] load failed: $e');
      return null;
    }
  }

  /// Something that counts towards a quest happened ('wins' or 'builds').
  /// Fire and forget; outside a guild it does nothing.
  static void report(String kind, {int n = 1}) {
    if (!GuildMembership.instance.inGuild) return;
    unawaited(() async {
      try {
        await supabase.rpc(
          'guild_quest_progress',
          params: {'p_kind': kind, 'p_n': n},
        );
      } catch (e) {
        debugPrint('[GuildQuests] report failed: $e');
      }
    }());
  }
}
