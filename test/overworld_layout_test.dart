import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:boddygame/features/creatures/models/path_node.dart'
    show kLastPathBattle;

import 'package:boddygame/features/creatures/models/area.dart';
import 'package:boddygame/features/creatures/services/overworld_layout.dart';
import 'package:boddygame/features/creatures/services/overworld_path.dart';

// The overworld is ONE straight line of numbered battles (linear rebuild
// 2026-07-24). These run against the bundled fallback areas (verdant_hollow /
// stone_reach / emberwastes at battleStage 1/2/3).

void main() {
  setUp(() {
    kAreaDefs
      ..clear()
      ..addAll({for (final a in kFallbackAreaDefs) a.id: a});
  });

  // Every node on the line IS a battle since 2026-07-25 (spots and the hunt
  // moved to the Expeditions screen), so this is now just a rename.
  List<OverworldNode> battles(List<OverworldNode> nodes) => nodes;

  group('linear layout at the very start (battlesCleared 0)', () {
    test('shows only Era I — battles 1..boss, nothing beyond', () {
      final b = battles(buildLinearOverworld(battlesCleared: 0));
      final numbers = b.map((n) => n.battleNumber).toList()..sort();
      expect(numbers.first, 1);
      expect(numbers.last, bossBattleForEra(1));
      expect(numbers, everyElement(lessThanOrEqualTo(bossBattleForEra(1))));
      // Contiguous 1..boss, no gaps.
      expect(numbers, List.generate(bossBattleForEra(1), (i) => i + 1));
    });

    test('battle 1 is current, everything above it is locked', () {
      final b = battles(buildLinearOverworld(battlesCleared: 0));
      final one = b.firstWhere((n) => n.battleNumber == 1);
      expect(one.state, OverworldNodeState.current);
      expect(
        b.where((n) => n.battleNumber > 1),
        everyElement(
          predicate<OverworldNode>((n) => n.state == OverworldNodeState.locked),
        ),
      );
      expect(b.where((n) => n.state == OverworldNodeState.done), isEmpty);
    });

    test('every node sits on the SAME vertical line (it is straight)', () {
      final nodes = buildLinearOverworld(battlesCleared: 0);
      final xs = nodes.map((n) => n.pos.dx).toSet();
      expect(xs, hasLength(1), reason: 'all nodes share one x — a straight line');
    });

    test('battle 1 is at the foot; the boss is at the top', () {
      final nodes = buildLinearOverworld(battlesCleared: 0);
      final one = nodes.firstWhere((n) => n.battleNumber == 1);
      final boss = nodes.firstWhere((n) => n.isBoss);
      expect(one.pos.dy, greaterThan(boss.pos.dy),
          reason: 'the trail climbs upward, so lower battle = larger y');
    });

    test('the line is battles ONLY — no spot or hunt detours', () {
      // Expeditions moved off the map (2026-07-25): every node must be a real
      // fight with a battle number, or the map has grown a second purpose again.
      final nodes = buildLinearOverworld(battlesCleared: 0);
      expect(nodes, isNotEmpty);
      expect(nodes.every((n) => n.battleNumber > 0), isTrue);
    });

    test('every node carries its enemy level + party allowance', () {
      final nodes = buildLinearOverworld(battlesCleared: 0);
      for (final n in nodes) {
        expect(n.enemyLevel, enemyLevelForBattle(n.battleNumber));
        expect(n.partySize, partySizeForBattle(n.battleNumber));
      }
    });
  });

  group('progress moves the frontier and unfogs the next era', () {
    test('cleared battles read done, the next reads current', () {
      final b = battles(buildLinearOverworld(battlesCleared: 5));
      for (var i = 1; i <= 5; i++) {
        expect(b.firstWhere((n) => n.battleNumber == i).state,
            OverworldNodeState.done);
      }
      expect(b.firstWhere((n) => n.battleNumber == 6).state,
          OverworldNodeState.current);
      expect(b.firstWhere((n) => n.battleNumber == 7).state,
          OverworldNodeState.locked);
    });

    test('clearing the Era-I boss brings Era II onto the line', () {
      final beforeBoss = battles(buildLinearOverworld(battlesCleared: 0));
      expect(beforeBoss.any((n) => n.battleNumber > bossBattleForEra(1)),
          isFalse);

      final afterBoss =
          battles(buildLinearOverworld(battlesCleared: bossBattleForEra(1)));
      expect(afterBoss.any((n) => n.battleNumber == bossBattleForEra(1) + 1),
          isTrue);
      // Era II's BOSS is not asserted here any more: the bundled path stops at
      // kLastPathBattle (user 2026-07-30, "bitte lösche alle knoten ab Battle
      // 21"), so region II has whatever nodes are authored for it and no seeded
      // boss. What this test is about is the LAYOUT rule — the next region comes
      // into view when the previous boss falls — and that is unchanged.
      expect(kLastPathBattle, greaterThanOrEqualTo(bossBattleForEra(1) + 1),
          reason: 'the seed must still reach into era II for this to mean '
              'anything');
    });
  });

  test('the layout is deterministic across builds', () {
    final a = buildLinearOverworld(battlesCleared: 3);
    final b = buildLinearOverworld(battlesCleared: 3);
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].id, b[i].id);
      expect(a[i].pos, b[i].pos);
      expect(a[i].battleNumber, b[i].battleNumber);
    }
  });

  // ── Keine Balken links und rechts (user 2026-07-31) ─────────
  // "balken links und rechts dürfen nicht sichtbar sein, daher den zoom
  //  anpassen."
  //
  // The map's canvas is ONE fixed-width lane, so covering the screen is a zoom
  // question, not a layout one. The screen uses this both as the opening scale
  // and as the viewer's minScale — if the two ever came apart, the first pinch
  // would put the bars back.
  group('the map fills the screen', () {
    test('a wider screen zooms in by exactly its overhang', () {
      final canvas = overworldCanvasSize(buildLinearOverworld(battlesCleared: 0));
      expect(canvas.width, 300, reason: 'the fixed lane this is all about');
      // A real era-I path is far taller than a phone, so width is what falls
      // short and width is what decides.
      expect(canvas.height, greaterThan(900));
      expect(overworldFillScale(const Size(411, 900), canvas), 411 / 300);
    });

    test('a screen exactly as wide as the canvas needs no zoom', () {
      expect(overworldFillScale(const Size(300, 600), const Size(300, 900)), 1.0);
    });

    test('a SHORT path zooms to cover the height instead', () {
      // Two nodes and a tall screen: covering the width would leave bare
      // background above and below (user: "oben und unten will ich die balken
      // auch nicht sehen"), so the taller ratio wins.
      expect(overworldFillScale(const Size(400, 900), const Size(300, 450)), 2.0);
    });

    test('the scaled canvas is never smaller than the screen', () {
      // The invariant the whole feature rests on — and what keeps the screen's
      // vertical clamp well-formed instead of throwing on an inverted range.
      for (final canvas in const [
        Size(300, 450),
        Size(300, 3000),
        Size(300, 899),
      ]) {
        const screen = Size(411, 900);
        final s = overworldFillScale(screen, canvas);
        expect(canvas.width * s, greaterThanOrEqualTo(screen.width - 0.001));
        expect(canvas.height * s, greaterThanOrEqualTo(screen.height - 0.001));
      }
    });

    test('no size yet is 1.0, never an infinity in the matrix', () {
      // The first frame asks before layout has happened.
      expect(overworldFillScale(Size.zero, const Size(300, 900)), 1.0);
      expect(overworldFillScale(const Size(411, -5), const Size(300, 900)), 1.0);
      expect(overworldFillScale(const Size(411, 900), Size.zero), 1.0);
    });
  });
}
